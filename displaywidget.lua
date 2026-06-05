-- displaywidget.lua
--
-- Clock display widget with proper RTC-based standby for Kobo e-readers.
--
-- ARCHITECTURE (v6)
-- =================
-- The old implementation had critical bugs:
--   1. Timer accumulation: autoRefresh() never unscheduled old timers
--   2. setAutoSuspend(1/5) death spiral: KOReader kept waking to check
--   3. Explicit UIManager:suspend() calls fought with KOReader's AutoSuspend
--   4. keepAwake/turnOffKeepAwake race conditions
--
-- The current implementation:
--   - Uses WakeupMgr (or sysfs fallback) for RTC scheduling
--   - Always unschedules previous timers before creating new ones
--   - Does NOT modify KOReader's AutoSuspend timeout at all
--   - Does NOT call UIManager:suspend() — lets KOReader handle it naturally
--   - Only holds the wake lock during the brief render phase (configurable)
--   - On resume from RTC alarm: render → schedule next alarm → release wake lock
--   - Target consumption: ~4-5% per day on Kobo Aura 2
--
-- CYCLE (per-minute updates):
--   1. RTC fires → KOReader calls onResume()
--   2. onResume() acquires wake lock, renders clock, schedules next RTC alarm
--   3. After wake_duration (default 0.5s), releases wake lock
--   4. KOReader's AutoSuspend enters deep sleep naturally
--   5. ~59.5 seconds of deep sleep (CPU off, only RTC active)
--   6. Go to step 1

local Blitbuffer     = require("ffi/blitbuffer")
local Date           = os.date
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginShare    = require("pluginshare")
local Screen         = Device.screen
local UIManager      = require("ui/uimanager")
local logger         = require("logger")

local StatusUtils  = require("statusutils")
local PngUtils     = require("pngutils")
local TimeUtils    = require("timeutils")
local RenderUtils  = require("renderutils")
local SystemUtils  = require("systemutils")
local AutoLayout   = require("autolayout")
local ClockStyles  = require("clockstyles")

local T = require("ffi/util").template
local _ = require("gettext")


-- Helper to safely clone base settings so image configs don't permanently overwrite them
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deep_copy(v) end
    return res
end



local function makeTransparent(widget)
    if not widget._bb then return widget end -- Native transparency (SpriteTextWidget)
    widget.paintTo = function(self, bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local w = self.width
        local h = self._bb:getHeight()
        self._bb:invertRect(0, 0, w, h)
        bb:colorblitFrom(self._bb, x, y, 0, 0, w, h, Blitbuffer.COLOR_BLACK)
        self._bb:invertRect(0, 0, w, h)
    end
    return widget
end

-- ---------------------------------------------------------------------------
-- Load a PNG as a true BBRGB32 buffer with the alpha channel fully intact
-- ---------------------------------------------------------------------------
local function loadPngWidget(png_path, width, height, rotation_angle)
    local img_bb

    local ok_m, Mupdf = pcall(require, "ffi/mupdf")
    if ok_m and Mupdf then
        local saved_color = Mupdf.color
        Mupdf.color = true
        local ok_r, result = pcall(function()
            return Mupdf.renderImageFile(png_path, width, height)
        end)
        Mupdf.color = saved_color
        if ok_r and result then
            img_bb = result
        end
    end

    if not img_bb then
        local ok_ri, RenderImage = pcall(require, "ui/renderimage")
        if ok_ri and RenderImage then
            local ok_r2, result2 = pcall(function()
                return RenderImage:renderImageFile(png_path, false, width, height)
            end)
            if ok_r2 and result2 then
                img_bb = result2
            end
        end
    end

    if not img_bb then return nil end

    if rotation_angle and rotation_angle ~= 0 then
        local rotated = img_bb:rotatedCopy(rotation_angle)
        img_bb:free()
        img_bb = rotated
        if not img_bb then return nil end
    end

    local iw = img_bb:getWidth()
    local ih = img_bb:getHeight()

    return {
        _img_bb = img_bb,
        dimen   = Geom:new{ x = 0, y = 0, w = iw, h = ih },

        getSize = function(self)
            return Geom:new{ w = self._img_bb:getWidth(), h = self._img_bb:getHeight() }
        end,

        paintTo = function(self, bb, x, y)
            self.dimen.x = x
            self.dimen.y = y
            bb:alphablitFrom(self._img_bb, x, y, 0, 0,
                             self._img_bb:getWidth(), self._img_bb:getHeight(), 0xFF)
        end,

        free = function(self)
            if self._img_bb then
                self._img_bb:free()
                self._img_bb = nil
            end
        end,
    }
end


local function toAbsolute(coord, screen_dim, widget_dim, unit)
    local offset
    if unit == "%" then
        offset = (coord / 100) * screen_dim
    else
        offset = coord
    end
    return math.floor(screen_dim / 2 - widget_dim / 2 + offset)
end




local DEFAULT_ELEMENTS = {
    png     = { x = 0, y =   0, unit = "px", z = 1, visible = true },
    date    = { x = 0, y = -20, unit = "%",  z = 2, visible = true },
    time    = { x = 0, y =   0, unit = "px", z = 2, visible = true },
    status  = { x = 0, y =  20, unit = "%",  z = 2, visible = true },
    wifi    = { x = 0, y =  30, unit = "%",  z = 2, visible = false },
    battery = { x = 0, y =  35, unit = "%",  z = 2, visible = false },
    memory  = { x = 0, y =  40, unit = "%",  z = 2, visible = false },
}

local DisplayWidget = InputContainer:extend {
    props      = {},
    plugin_dir = "",
}

local function isDisplayInverted(props)
    local setting = props and props.night_mode or "follow"
    local koreader_night = G_reader_settings:isTrue("night_mode")

    if setting == "night" then return true end
    if setting == "normal" then return false end
    return koreader_night == true
end


function DisplayWidget:init()
    self.is_dtdisplay_clock = true
    self.now              = os.time()
    self.is_closing       = false
    self.render_list      = {}

    -- Store original props as the baseline
    self.base_props = deep_copy(self.props or {})
    self.base_elements = deep_copy(self.elements or {})
    self._using_custom_config = false

    self.png_cycle_index      = 1
    self.png_cycle_counter    = 0
    self.full_refresh_counter = 0
    self.png_file_list        = nil

    -- ========================================================================
    -- TIMER MANAGEMENT (Fixed)
    -- ========================================================================
    -- CRITICAL FIX: We now track ALL scheduled timers and always unschedule
    -- before creating a new one. This prevents the timer accumulation bug
    -- that caused the 2-day freeze.
    -- ========================================================================
    self.clock_timer = nil           -- UIManager:scheduleIn timer reference
    self._schedule_guard = false     -- Prevent double-scheduling

    -- Determine active clock style
    self.clock_style = (self.props and self.props.clock_style) or "classic"

    if not self.dimen then
        self.dimen = Geom:new {
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
    end

    self.original_rotation = Screen:getRotationMode()
    self:applyClockRotation()

    -- ========================================================================
    -- AUTO-REFRESH LOOP (Fixed)
    -- ========================================================================
    -- This is the core per-minute update loop. The key changes from the old
    -- implementation:
    --
    -- 1. Always unschedule previous timer before creating new one
    -- 2. Use WakeupMgr for RTC scheduling (not direct sysfs)
    -- 3. Let KOReader's AutoSuspend handle deep sleep
    -- 4. Only hold wake lock during render, release immediately after
    -- 5. NEVER set autoSuspend to 1 second (that was the death spiral)
    -- ========================================================================
    if not self.is_screensaver then
        self.autoRefresh = function()
            if self.is_closing then return end

            -- Guard against double-scheduling
            if self._schedule_guard then
                logger.dbg("DisplayWidget: autoRefresh guard blocked double-schedule")
                return
            end
            self._schedule_guard = true

            -- Step 1: Render the clock (updates self.now internally)
            self:refresh()

            -- Step 2: Determine how long to sleep until the next minute
            local sleep_seconds = SystemUtils.secondsUntilNextMinute(2)

            -- Configurable wake duration: how long the CPU stays awake after
            -- updating the screen before the wake lock is released. Some
            -- e-readers need a longer duration for the e-ink pipeline to flush.
            local wake_duration = (self.props and self.props.wake_duration) or 0.5

            -- ==================================================================
            -- RTC deep sleep (the only power-saving mode)
            -- ==================================================================
            -- Schedule RTC wakeup via WakeupMgr (preferred) or sysfs fallback.
            -- After the wake lock is released, KOReader's AutoSuspend naturally
            -- puts the device to sleep. We do NOT call UIManager:suspend()
            -- explicitly — that fights with KOReader's own suspend management.
            -- ==================================================================
            local rtc_ok = SystemUtils.scheduleRtcWakeup(sleep_seconds, function()
                logger.dbg("DisplayWidget: WakeupMgr callback triggered")
            end)

            if rtc_ok then
                -- Release the wake lock after the configured wake duration.
                -- Once released, KOReader's AutoSuspend handles deep sleep.
                self:_unscheduleTimer()
                self.clock_timer = UIManager:scheduleIn(wake_duration, function()
                    if self.is_closing then return end
                    SystemUtils.turnOffKeepAwake()
                    self._schedule_guard = false
                end)
            else
                -- RTC unavailable: fallback to simple UIManager timer
                -- (higher battery consumption, but functional)
                logger.warn("DisplayWidget: RTC wakeup unavailable, using timer fallback")
                self:_unscheduleTimer()
                self.clock_timer = UIManager:scheduleIn(sleep_seconds - 2 + 0.5, function()
                    self._schedule_guard = false
                    if not self.is_closing then self:autoRefresh() end
                end)
            end
        end
    end

    -- Tap/Touch close handling
    if not self.is_screensaver then
        local fullscreen_range = Geom:new {
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }

        self.ges_events = self.ges_events or {}

        self.ges_events.TapClose = {
            GestureRange:new { ges = "tap", range = fullscreen_range }
        }

        -- Hold gesture to launch full-screen customizer
        self.ges_events.HoldToEdit = {
            GestureRange:new { ges = "hold", range = fullscreen_range }
        }
    end



    self.covers_fullscreen = true

    -- Load the baseline elements.lua
    local elements_path = self.plugin_dir .. "elements.lua"
    local ok, file_elements = pcall(dofile, elements_path)
    if not ok or type(file_elements) ~= "table" then
        file_elements = {}
    end

    self.base_elements = {}
    for name, defaults in pairs(DEFAULT_ELEMENTS) do
        local user = file_elements[name] or {}
        self.base_elements[name] = {
            x       = user.x ~= nil and user.x or defaults.x,
            y       = user.y ~= nil and user.y or defaults.y,
            unit    = user.unit or defaults.unit,
            z       = user.z   ~= nil and user.z or defaults.z,
            visible = user.visible ~= false,
        }
    end

    -- Dynamically load image config (if any) and sync night mode
    self._using_custom_config = self:applyImageProps()
    self:syncStateFlags()

    self:render()
    UIManager:setDirty("all", "full")

    if not self.is_screensaver then
        -- ========================================================================
        -- AutoSuspend: DO NOT modify KOReader's AutoSuspend timeout.
        -- ========================================================================
        -- We save the original value only so we can restore it on close as a
        -- safety net, but we no longer change it. KOReader's own AutoSuspend
        -- will naturally put the device to sleep after we release the wake lock.
        -- This avoids the 5-second polling loop that was draining battery.
        -- ========================================================================
        local autosuspend = PluginShare.live_autosuspend
        if autosuspend then
            self.original_autosuspend_timeout = autosuspend.auto_suspend_timeout_seconds
        end

        -- Hold the wake lock during the initial render phase
        SystemUtils.turnOnKeepAwake()

        -- Set brightness if configured
        self.original_brightness = nil
        if self.props.widget_brightness and self.props.widget_brightness >= 0 then
            if SystemUtils.hasFrontlight() then
                self.original_brightness = SystemUtils.getBrightness()
                SystemUtils.setBrightness(self.props.widget_brightness)
            end
        end
    end
end


-- ---------------------------------------------------------------------------
-- Timer Helper (Fixed)
-- ---------------------------------------------------------------------------

--- Safely unschedule the current clock timer.
-- This is the key fix for the timer accumulation bug.
function DisplayWidget:_unscheduleTimer()
    if self.clock_timer then
        UIManager:unschedule(self.clock_timer)
        self.clock_timer = nil
    end
end


function DisplayWidget:render()
    local sw = self.dimen.w
    local sh = self.dimen.h
    local style = self.clock_style or "classic"

    local size_preset = (self.props and self.props.text_size) or "medium"
    local time_font_size, date_font_size, status_font_size
            = ClockStyles.resolvePresetSizes(size_preset, sh)

    local time_font_name   = self.props.time_widget.font_name
    local date_font_name   = self.props.date_widget.font_name
    local status_font_name = self.props.status_widget.font_name

    local function getStatusFace()
        return Font:getFace(status_font_name, status_font_size)
    end

    if style == "fullscreen" then
        self.time_widget = makeTransparent(ClockStyles.renderFullscreen(
            self.now, sw, sh, time_font_name, self.props.clock_format
        ))
    elseif style == "analog" then
        local analog_opts = (self.props and self.props.analog_opts) or {}
        self.analog_widget = ClockStyles.renderAnalog(self.now, sw, sh, analog_opts)
        local infos = (self.props and self.props.analog_infos) or {"battery"}
        self.analog_info_widget = ClockStyles.renderAnalogInfoBar(
            self.now, sw, sh, infos, getStatusFace()
        )
        self.time_widget = makeTransparent(RenderUtils.renderTimeWidget(
            self.now, sw,
            Font:getFace(time_font_name, time_font_size),
            self.props.clock_format
        ))
    elseif style == "outlined" then
        local outline_px = (self.props and self.props.outline_width) or 3
        self.time_widget = ClockStyles.renderOutlinedTimeWidget(
            self.now, sw,
            Font:getFace(time_font_name, time_font_size),
            self.props.clock_format, outline_px
        )
    elseif style == "wordclock" then
        self.time_widget = makeTransparent(ClockStyles.renderWordClock(
            self.now, sw,
            Font:getFace(time_font_name, time_font_size)
        ))
    else
        self.time_widget = makeTransparent(RenderUtils.renderTimeWidget(
            self.now, sw,
            Font:getFace(time_font_name, time_font_size),
            self.props.clock_format
        ))
    end

    local is_minimal_mode = (style == "fullscreen" or style == "analog")

    self.date_widget = makeTransparent(RenderUtils.renderDateWidget(
        self.now, sw,
        Font:getFace(date_font_name, date_font_size), true
    ))
    self.status_widget = makeTransparent(RenderUtils.renderStatusWidget(
        sw, getStatusFace()
    ))
    self.wifi_widget    = makeTransparent(RenderUtils.renderWifiWidget(sw, getStatusFace()))
    self.memory_widget  = makeTransparent(RenderUtils.renderMemoryWidget(sw, getStatusFace()))

    local batt_props  = self.props.battery_widget or {}
    local batt_format = batt_props.format or "both"
    self.battery_widget = makeTransparent(RenderUtils.renderBatteryWidget(sw, getStatusFace(), batt_format))

    self.png_file_list      = nil
    self.png_overlay_widget = self:createPngOverlayWidget()

    self.render_list = {}

    local function addWidget(name, widget)
        local elem = self.elements[name]
        if not elem or not elem.visible then return end
        if is_minimal_mode and name ~= "png" then return end
        local size = widget:getSize()
        table.insert(self.render_list, {
            widget = widget,
            px     = toAbsolute(elem.x, sw, size.w, elem.unit),
            py     = toAbsolute(elem.y, sh, size.h, elem.unit),
            z      = elem.z,
            is_png = false,
            name   = name,
        })
    end

    if not is_minimal_mode then
        addWidget("time",    self.time_widget)
        addWidget("date",    self.date_widget)
        addWidget("status",  self.status_widget)
        addWidget("wifi",    self.wifi_widget)
        addWidget("battery", self.battery_widget)
        addWidget("memory",  self.memory_widget)
    end

    if style == "fullscreen" then
        local time_size = self.time_widget:getSize()
        table.insert(self.render_list, {
            widget = self.time_widget,
            px     = math.floor((sw - time_size.w) / 2),
            py     = math.floor((sh - time_size.h) / 2),
            z      = 50,
            is_png = false,
            name   = "time",
        })
    end

    local png_elem = self.elements["png"]
    if self.png_overlay_widget and png_elem and png_elem.visible then
        table.insert(self.render_list, {
            widget = self.png_overlay_widget,
            px     = toAbsolute(png_elem.x, sw, sw, png_elem.unit),
            py     = toAbsolute(png_elem.y, sh, sh, png_elem.unit),
            z      = png_elem.z,
            is_png = true,
            name   = "png",
        })
    end

    local auto_layout = self.props and self.props.auto_layout_enabled
    if style == "wordclock" then
        auto_layout = true
    end
    if auto_layout ~= false and not is_minimal_mode then
        local gap = (self.props and self.props.auto_layout_gap) or AutoLayout.DEFAULT_GAP
        self.render_list = AutoLayout.apply(self.render_list, self.elements, gap)
    end

    table.sort(self.render_list, function(a, b) return a.z < b.z end)
end

function DisplayWidget:syncStateFlags()
    local is_dark = isDisplayInverted(self.props)
    local system_night = G_reader_settings:isTrue("night_mode")

    self.apply_manual_inversion = (is_dark == true and system_night == false)

    self.invert_png_overlay = true
    if self.props.png_overlay and self.props.png_overlay.invert_with_night_mode == false then
        self.invert_png_overlay = false
    end
end

function DisplayWidget:applyImageProps()
    self.props = deep_copy(self.base_props)
    self.elements = deep_copy(self.base_elements)

    if not self.props.png_overlay or not self.props.png_overlay.use_image_config then
        return false
    end

    local png_path = self:getCurrentPngPathAndType()
    if not png_path then return false end

    local config_path = png_path:gsub("%.[pP][nN][gG]$", ".lua")

    local ok, img_cfg = pcall(dofile, config_path)
    if not ok or type(img_cfg) ~= "table" then
        return false
    end

    for k, v in pairs(img_cfg) do
        if k ~= "elements" then
            if type(v) == "table" and type(self.props[k]) == "table" then
                for k2, v2 in pairs(v) do
                    if v2 ~= nil then self.props[k][k2] = v2 end
                end
            elseif v ~= nil then
                self.props[k] = v
            end
        end
    end

    if img_cfg.elements then
        for name, user in pairs(img_cfg.elements) do
            if self.elements[name] then
                if user.x ~= nil then self.elements[name].x = user.x end
                if user.y ~= nil then self.elements[name].y = user.y end
                if user.unit ~= nil then self.elements[name].unit = user.unit end
                if user.z ~= nil then self.elements[name].z = user.z end
                if user.visible ~= nil then self.elements[name].visible = user.visible end
            end
        end
    end

    return true
end

function DisplayWidget:update()
    local style = self.clock_style or "classic"

    if style == "analog" then
        local sw = self.dimen.w
        local sh = self.dimen.h
        local analog_opts = (self.props and self.props.analog_opts) or {}
        if self.analog_widget and type(self.analog_widget.free) == "function" then
            self.analog_widget:free()
        end
        self.analog_widget = ClockStyles.renderAnalog(self.now, sw, sh, analog_opts)
        local infos = (self.props and self.props.analog_infos) or {"battery"}
        local size_preset = (self.props and self.props.text_size) or "medium"
        local _, _, status_font_size = ClockStyles.resolvePresetSizes(size_preset, sh)
        local status_font_name = self.props.status_widget.font_name
        if self.analog_info_widget and type(self.analog_info_widget.free) == "function" then
            self.analog_info_widget:free()
        end
        self.analog_info_widget = ClockStyles.renderAnalogInfoBar(
            self.now, sw, sh, infos, Font:getFace(status_font_name, status_font_size)
        )
    elseif style == "wordclock" then
        local new_text = ClockStyles.getWordClockText(self.now)
        if self.time_widget.text ~= new_text and self.time_widget._wc_text ~= new_text then
            self.time_widget:setText(new_text)
            self.time_widget._wc_text = new_text
        end
    elseif style == "fullscreen" then
        local is_12_hour = (self.props.clock_format == "12h")
        local format_str = is_12_hour and "%I\n%M" or "%H\n%M"
        local time_text = os.date(format_str, self.now)
        
        -- Fallback if widget got destroyed or is missing
        if not self.time_widget or not self.time_widget.setText then
            local sw, sh = self.dimen.w, self.dimen.h
            self.time_widget = makeTransparent(ClockStyles.renderFullscreen(
                self.now, sw, sh,
                self.props.time_widget.font_name,
                self.props.clock_format
            ))
            for _, item in ipairs(self.render_list) do
                if item.name == "time" then item.widget = self.time_widget; break end
            end
        elseif self.time_widget.text ~= time_text then
            self.time_widget:setText(time_text)
            self.time_widget.text = time_text
        end
    else
        local time_text = TimeUtils.getTimeText(self.now, self.props.clock_format)
        if self.time_widget.text ~= time_text then self.time_widget:setText(time_text) end
    end

    local date_text   = TimeUtils.getDateText(self.now, true)
    local status_text = StatusUtils.getStatusText()
    local wifi_text   = StatusUtils.getWifiStatusText()
    local memory_text = StatusUtils.getMemoryStatusText() or ""
    local batt_props  = self.props.battery_widget or {}
    local batt_format = batt_props.format or "both"
    local batt_text   = StatusUtils.getBatteryText(batt_format)

    if self.date_widget.text   ~= date_text   then self.date_widget:setText(date_text)     end
    if self.status_widget.text ~= status_text then self.status_widget:setText(status_text) end
    if self.wifi_widget.text    ~= wifi_text   then self.wifi_widget:setText(wifi_text)    end
    if self.memory_widget.text  ~= memory_text then self.memory_widget:setText(memory_text) end
    if self.battery_widget.text ~= batt_text   then self.battery_widget:setText(batt_text)  end

    local auto_layout = self.props and self.props.auto_layout_enabled
    if style == "wordclock" then
        auto_layout = true
    end
    local is_minimal_mode = (style == "fullscreen" or style == "analog")
    if auto_layout ~= false and not is_minimal_mode then
        local gap = (self.props and self.props.auto_layout_gap) or AutoLayout.DEFAULT_GAP
        self.render_list = AutoLayout.apply(self.render_list, self.elements, gap)
    end
end

function DisplayWidget:paintTo(bb, x, y)
    local sw = self.dimen.w
    local sh = self.dimen.h
    local style = self.clock_style or "classic"

    local is_dark = isDisplayInverted(self.props)
    local system_night = G_reader_settings:isTrue("night_mode")
    local force_software_invert = (is_dark ~= system_night)
    local needs_png_pre_inversion = (is_dark and not self.invert_png_overlay)
    local draw_color = is_dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

    bb:paintRect(x, y, sw, sh, Blitbuffer.COLOR_WHITE)

    for _, item in ipairs(self.render_list) do
        if item.is_png then
            if needs_png_pre_inversion then
                local pw, ph = item.widget:getSize().w, item.widget:getSize().h
                local px, py = x + item.px, y + item.py
                bb:invertRect(px, py, pw, ph)
                item.widget:paintTo(bb, px, py)
                bb:invertRect(px, py, pw, ph)
            else
                item.widget:paintTo(bb, x + item.px, y + item.py)
            end
        else
            item.widget:paintTo(bb, x + item.px, y + item.py)
        end
    end

    if style == "analog" and self.analog_widget then
        self.analog_widget:paintTo(bb, x, y)
        if self.analog_info_widget then
            local info_sz = self.analog_info_widget:getSize()
            self.analog_info_widget:paintTo(bb,
                x + math.floor((sw - info_sz.w) / 2),
                y + sh - info_sz.h - 20
            )
        end
    end

    if style ~= "fullscreen" and style ~= "analog" then
        local sep_style = self.props and self.props.separator_style
        if sep_style and sep_style ~= "none" then
            local time_top, time_bottom, date_top, date_bottom
            for _, item in ipairs(self.render_list) do
                if item.name == "time" then
                    time_top = item.py
                    time_bottom = item.py + item.widget:getSize().h
                elseif item.name == "date" then
                    date_top = item.py
                    date_bottom = item.py + item.widget:getSize().h
                end
            end
            if time_bottom and date_top then
                local y1, y2
                if date_top > time_bottom then
                    y1 = time_bottom
                    y2 = date_top
                elseif time_top > date_bottom then
                    y1 = date_bottom
                    y2 = time_top
                end
                if y1 and y2 and (y2 - y1) >= 12 then
                    local sep_y = math.floor((y1 + y2) / 2)
                    ClockStyles.drawSeparator(bb, x, y + sep_y, sw, sep_style, draw_color)
                end
            end
        end

        local frame_style = self.props and self.props.border_frame_style
        if frame_style and frame_style ~= "none" then
            ClockStyles.drawBorderFrame(bb, sw, sh, frame_style, draw_color)
        end
    end

    if force_software_invert then
        bb:invertRect(x, y, sw, sh)
    end
end

function DisplayWidget:refresh()
    self:syncStateFlags()
    self.now = os.time()
    self:update()

    if type(self.cyclePngOverlay) == "function" then
        self:cyclePngOverlay()
    end

    local frm = self.props.full_refresh_minutes
    if frm and frm > 0 then
        self.full_refresh_counter = self.full_refresh_counter + 1
        if self.full_refresh_counter >= frm then
            self.full_refresh_counter = 0
            UIManager:setDirty("all", "full")
            return
        end
    end

    UIManager:setDirty("all", "ui")
end

function DisplayWidget:cyclePngOverlay()
    local o = self.base_props and self.base_props.png_overlay
    if not o or not o.enabled or o.mode ~= "cycle" then return end

    local files = self:getPngFileList()
    if not files or #files == 0 then return end

    self.png_cycle_counter = self.png_cycle_counter + 1
    if self.png_cycle_counter >= self:getCycleMinutes() then
        self.png_cycle_counter = 0
        self.png_cycle_index   = self.png_cycle_index + 1
        if self.png_cycle_index > #files then self.png_cycle_index = 1 end

        local had_custom = self._using_custom_config
        self._using_custom_config = self:applyImageProps()
        self:syncStateFlags()

        self:updatePngOverlayWidget()

        if self._using_custom_config or had_custom then
            self:render()
        end

        UIManager:setDirty("all", self:isFullRefreshOnCycle() and "full" or "ui")
    end
end

function DisplayWidget:onShow()
    if self.is_screensaver then return end
    return self:autoRefresh()
end

-- ========================================================================
-- onResume (Fixed)
-- ========================================================================
-- CRITICAL FIX: This is called when the device wakes from deep sleep
-- (either from RTC alarm or manual wake). The old implementation had
-- several issues:
--   - It set autoSuspend to 0 (preventing sleep), which fights with
--     KOReader's AutoSuspend
--   - It didn't properly manage the schedule guard
--   - It didn't distinguish between RTC wake and manual wake
--
-- The new implementation:
--   1. Acquires wake lock (we're awake, need to render)
--   2. Cancels any pending timers/alarms
--   3. Renders the clock immediately
--   4. Schedules the next RTC alarm for the next minute
--   5. After 0.5s, releases wake lock → device can sleep again
-- ========================================================================
function DisplayWidget:onResume()
    if self.is_screensaver then return end
    if self.is_closing then return end

    logger.dbg("DisplayWidget: onResume")

    -- Acquire wake lock: we're awake and need to render
    SystemUtils.turnOnKeepAwake()

    -- Cancel any pending timer and schedule guard
    self:_unscheduleTimer()
    self._schedule_guard = false

    -- Cancel any pending RTC alarm (we'll reschedule after rendering)
    SystemUtils.cancelRtcWakeup()

    -- Render the clock immediately and schedule next RTC alarm
    if not self.is_closing then
        self:autoRefresh()
    end
end

-- ========================================================================
-- onSuspend (Fixed)
-- ========================================================================
-- Called when KOReader is about to enter deep sleep.
-- We just cancel any pending UIManager timers. The RTC alarm is already
-- scheduled and will survive deep sleep (that's the whole point of RTC).
-- ========================================================================
function DisplayWidget:onSuspend()
    if self.is_screensaver then return end
    logger.dbg("DisplayWidget: onSuspend")
    self:_unscheduleTimer()
    self._schedule_guard = false
end

function DisplayWidget:onIgnoreTouch()
    return true
end



-- ========================================================================
-- Clock Close (Fixed)
-- ========================================================================
-- CRITICAL FIX: The old implementation didn't properly clean up all
-- resources. The new implementation:
--   1. Sets is_closing flag FIRST to prevent any re-scheduling
--   2. Cancels ALL timers and RTC alarms
--   3. Restores all hardware state (touch, CPU governor, brightness)
--   4. Restores AutoSuspend to its original value
--   5. Releases the wake lock
-- ========================================================================
function DisplayWidget:onTapClose()
    if self.is_closing then return end
    self.is_closing = true

    -- Step 1: Cancel all scheduled timers
    self:_unscheduleTimer()
    self._schedule_guard = false

    if self.is_screensaver then
        UIManager:close(self)
        return
    end

    -- Step 2: Cancel RTC alarm (prevent ghost wakeups)
    SystemUtils.cancelRtcWakeup()

    -- Step 3: Restore rotation
    self:restoreRotation()

    -- Step 4: Restore brightness
    if self.original_brightness then
        SystemUtils.setBrightness(self.original_brightness)
        self.original_brightness = nil
    end

    -- Step 5: Restore AutoSuspend (safety net)
    SystemUtils.restoreAutoSuspend()

    -- Step 6: Release wake lock
    SystemUtils.turnOffKeepAwake()

    -- Step 7: Close the widget
    UIManager:close(self)

    -- Notify the plugin that the clock is closed
    if self.plugin_ref then
        self.plugin_ref.last_clock_close_time = os.time()
        self.plugin_ref.active_clock_widget = nil
    end
end

-- Close via any key press (e.g. POWER button)
DisplayWidget.onAnyKeyPressed = function(self)
    if self.is_screensaver then return end
    self:onTapClose()
end

function DisplayWidget:onCloseWidget()
    -- Failsafe: ensure all resources are cleaned up even if onTapClose
    -- wasn't called (e.g., widget closed by KOReader directly)
    self.is_closing = true
    self:_unscheduleTimer()

    if self.is_screensaver then
        return
    end

    SystemUtils.cancelRtcWakeup()
    self:restoreRotation()



    -- Restore AutoSuspend
    SystemUtils.restoreAutoSuspend()

    if self.original_brightness then
        SystemUtils.setBrightness(self.original_brightness)
        self.original_brightness = nil
    end

    SystemUtils.turnOffKeepAwake()
end

function DisplayWidget:free()
    -- Free C-level Blitbuffers to prevent severe memory leaks
    if self.time_widget and type(self.time_widget.free) == "function" then self.time_widget:free() end
    if self.date_widget and type(self.date_widget.free) == "function" then self.date_widget:free() end
    if self.status_widget and type(self.status_widget.free) == "function" then self.status_widget:free() end
    if self.wifi_widget and type(self.wifi_widget.free) == "function" then self.wifi_widget:free() end
    if self.battery_widget and type(self.battery_widget.free) == "function" then self.battery_widget:free() end
    if self.memory_widget and type(self.memory_widget.free) == "function" then self.memory_widget:free() end
    if self.analog_widget and type(self.analog_widget.free) == "function" then self.analog_widget:free() end
    if self.analog_info_widget and type(self.analog_info_widget.free) == "function" then self.analog_info_widget:free() end
    if self.png_overlay_widget and type(self.png_overlay_widget.free) == "function" then self.png_overlay_widget:free() end
end

function DisplayWidget:applyClockRotation()
    if self.is_preview then return end
    local r = self.props and self.props.rotation
    if r and not r.follow_koreader then
        Screen:setRotationMode(r.custom_rotation or 0)
    end
end

function DisplayWidget:restoreRotation()
    if self.is_preview then return end
    if self.original_rotation then
        Screen:setRotationMode(self.original_rotation)
        self.original_rotation = nil
    end
end

function DisplayWidget:getActiveFolderPath()
    local o = self.props and self.props.png_overlay
    if not o then return nil end
    if PngUtils.isPortraitOrientation() then
        if o.portrait_folder_path  and o.portrait_folder_path  ~= "" then return o.portrait_folder_path  end
        if o.folder_path           and o.folder_path           ~= "" then return o.folder_path           end
    else
        if o.landscape_folder_path and o.landscape_folder_path ~= "" then return o.landscape_folder_path end
        if o.folder_path           and o.folder_path           ~= "" then return o.folder_path           end
    end
end

function DisplayWidget:getActiveSingleFilePath()
    local o = self.props and self.props.png_overlay
    if not o then return nil end
    if PngUtils.isPortraitOrientation() then
        if o.single_file_path_portrait  and o.single_file_path_portrait  ~= "" then return o.single_file_path_portrait  end
        if o.single_file_path           and o.single_file_path           ~= "" then return o.single_file_path           end
    else
        if o.single_file_path_landscape and o.single_file_path_landscape ~= "" then return o.single_file_path_landscape end
        if o.single_file_path           and o.single_file_path           ~= "" then return o.single_file_path           end
    end
end

function DisplayWidget:getPngFileList()
    if self.png_file_list then return self.png_file_list end
    local o = self.props and self.props.png_overlay
    if not o or not o.enabled then return nil end
    local folder = self:getActiveFolderPath()
    if not folder then return nil end
    local lfs = require("libs/libkoreader-lfs")
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, folder)
    if not ok then return nil end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." and entry:lower():match("%.png$") then
            table.insert(files, entry)
        end
    end
    table.sort(files)
    local valid = {}
    for _, fname in ipairs(files) do
        local res = PngUtils.checkPngResolution(folder .. "/" .. fname)
        if res then table.insert(valid, { filename = fname, resolution_type = res }) end
    end
    if #valid == 0 then return nil end
    self.png_file_list = valid
    return self.png_file_list
end

function DisplayWidget:getCurrentPngPathAndType()
    local o = self.props and self.props.png_overlay
    if not o or not o.enabled then return nil, nil end
    local mode = o.mode or "single"
    if mode == "single" then
        local p = self:getActiveSingleFilePath()
        if p then
            local res = PngUtils.checkPngResolution(p)
            if res then return p, res end
        end
    elseif mode == "cycle" then
        local files = self:getPngFileList()
        if not files or #files == 0 then return nil, nil end
        local folder = self:getActiveFolderPath()
        if not folder then return nil, nil end
        if self.png_cycle_index > #files then self.png_cycle_index = 1 end
        local entry = files[self.png_cycle_index]
        return folder .. "/" .. entry.filename, entry.resolution_type
    end
    return nil, nil
end

function DisplayWidget:getCycleMinutes()
    local o = self.props and self.props.png_overlay
    return (o and o.cycle_minutes) or 1
end

function DisplayWidget:isFullRefreshOnCycle()
    local o = self.props and self.props.png_overlay
    return o and o.full_refresh_on_cycle == true
end

function DisplayWidget:createPngOverlayWidget()
    local png_path, res_type = self:getCurrentPngPathAndType()
    if not png_path then return nil end
    local ss = Screen:getSize()
    return loadPngWidget(
        png_path, ss.w, ss.h,
        PngUtils.getImageRotationAngle(res_type)
    )
end

function DisplayWidget:updatePngOverlayWidget()
    local png_path, res_type = self:getCurrentPngPathAndType()
    if not png_path then return end
    local ss = Screen:getSize()

    if self.png_overlay_widget and self.png_overlay_widget._img_bb then
        self.png_overlay_widget._img_bb:free()
    end

    local new_widget = loadPngWidget(
        png_path, ss.w, ss.h,
        PngUtils.getImageRotationAngle(res_type)
    )
    self.png_overlay_widget = new_widget
    for _, item in ipairs(self.render_list) do
        if item.is_png then item.widget = new_widget; break end
    end
end

function DisplayWidget:onHoldToEdit()
    if self.is_closing or self.is_screensaver then return end
    logger.info("DisplayWidget: Hold gesture detected, opening watchface customizer")

    local CustomizerWidget = require("customizerwidget")
    local customizer = CustomizerWidget:new {
        plugin_ref = self.plugin_ref,
        on_save = function()
            -- Close the current clock
            self:onTapClose()
            -- Re-open it with the new properties
            UIManager:show(DisplayWidget:new {
                props = self.plugin_ref:getEffectiveProps(),
                plugin_dir = self.plugin_dir,
                plugin_ref = self.plugin_ref,
            })
        end
    }
    UIManager:show(customizer)
end

return DisplayWidget
