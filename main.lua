local Dispatcher = require("dispatcher")
local DisplayWidget = require("displaywidget")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local LuaSettings = require("frontend/luasettings")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local SystemUtils = require("systemutils")
local logger = require("logger")
local cre -- delayed loading
local _ = require("gettext")
local T = require("ffi/util").template
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"


local DtDisplay = WidgetContainer:extend {
    name = "dtdisplay",
    config_file = "dtdisplay_config.lua",
    local_storage = nil,
    is_doc_only = false,
}

function DtDisplay:init()
    self:initLuaSettings()

    self.settings = self.local_storage.data
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:patchDofile()
    self:patchScreensaver()

    if Device.wakeup_mgr then
        self.wakeup_mgr = Device.wakeup_mgr
        logger.dbg("DtDisplay: Using device WakeupMgr")
    end

    self.rtcRefreshCallback = function()
        logger.info("DtDisplay: RTC periodic refresh triggered")

        if Device:isKobo() then
            UIManager:scheduleIn(0, function()
                local ok, err = pcall(function()
                    local Screensaver = require("ui/screensaver")
                    local ss_type = G_reader_settings:readSetting("screensaver_type")
                    if Device.screen_saver_mode and ss_type == "dtdisplay" then
                        -- Update the existing clock widget in-place (no full e-ink flash)
                        local ss_widget = Screensaver.screensaver_widget
                        local updated = false
                        if ss_widget then
                            local clock = ss_widget.widget
                            if clock and clock.is_dtdisplay_clock then
                                clock.now = os.time()
                                clock:update()
                                -- Use async "ui" refresh — no blocking forceRePaint()
                                UIManager:setDirty(ss_widget, "ui")
                                updated = true
                                logger.info("DtDisplay: In-place clock update (partial UI refresh)")
                            end
                        end
                        if not updated then
                            logger.info("DtDisplay: Falling back to Screensaver:show()")
                            Screensaver:show()
                        end
                        -- Schedule next RTC alarm
                        self:schedulePeriodicRefresh()
                        -- Release wake lock and suspend after the configured wake duration.
                        local wake_dur = (self.settings and self.settings.wake_duration) or 0.5
                        UIManager:scheduleIn(wake_dur, function()
                            logger.info("DtDisplay: Releasing wake lock and suspending after screensaver update")
                            SystemUtils.turnOffKeepAwake()
                            local Powerd = Device:getPowerDevice()
                            if Powerd and Powerd.toggleSuspend then
                                Powerd:toggleSuspend()
                            elseif Device.suspend then
                                Device:suspend()
                            end
                        end)
                    else
                        logger.info("DtDisplay: Skipping screensaver redraw on scheduled wakeup")
                        -- Release wake lock even if we skip the redraw
                        local wake_dur = (self.settings and self.settings.wake_duration) or 0.5
                        UIManager:scheduleIn(wake_dur, function()
                            logger.info("DtDisplay: Releasing wake lock after skipping redraw")
                            SystemUtils.turnOffKeepAwake()
                        end)
                    end
                end)
                if not ok then
                    logger.err("DtDisplay: Error in screensaver RTC refresh:", err)
                    pcall(function() self:schedulePeriodicRefresh() end)
                    local wake_dur = (self.settings and self.settings.wake_duration) or 0.5
                    UIManager:scheduleIn(wake_dur, function()
                        logger.info("DtDisplay: Releasing wake lock and suspending after RTC refresh error")
                        SystemUtils.turnOffKeepAwake()
                        local Powerd = Device:getPowerDevice()
                        if Powerd and Powerd.toggleSuspend then
                            Powerd:toggleSuspend()
                        elseif Device.suspend then
                            Device:suspend()
                        end
                    end)
                end
            end)
        else -- Device is Kindle
            local Powerd = Device:getPowerDevice()
            if Powerd and Powerd.toggleSuspend then
                Powerd:toggleSuspend()
            elseif Device.suspend then
                Device:suspend()
            end
            self.simulated_wakeup = true
        end
    end
end

function DtDisplay:initLuaSettings()
    self.local_storage = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.config_file))
    if next(self.local_storage.data) == nil then
        self.local_storage:reset({
            date_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 25,
            },
            time_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 119,
            },
            status_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 24,
            },
            rotation = {
                follow_koreader = true,
                custom_rotation = 0,
            },
            png_overlay = {
                enabled = false,
                folder_path = "",
                portrait_folder_path = "",
                landscape_folder_path = "",
                mode = "single",
                single_file_path = "",
                single_file_path_portrait = "",
                single_file_path_landscape = "",
                cycle_minutes = 1,
                full_refresh_on_cycle = false,
            },
            -- suspend settings removed in v6 (always uses RTC deep sleep now)
        })
        -- Migration: ensure per-image config setting exists
        if self.local_storage.data.png_overlay.use_image_config == nil then
            self.local_storage.data.png_overlay.use_image_config = false
        end
        self.local_storage:flush()
    end

    -- Migration: ensure rotation settings exist for users upgrading from older config
    if self.local_storage.data.rotation == nil then
        self.local_storage.data.rotation = {
            follow_koreader = true,
            custom_rotation = 0,
        }
        self.local_storage:flush()
    end

    -- Migration: ensure png_overlay settings exist
    if self.local_storage.data.png_overlay == nil then
        self.local_storage.data.png_overlay = {
            enabled = false,
            folder_path = "",
            portrait_folder_path = "",
            landscape_folder_path = "",
            mode = "single",
            single_file_path = "",
            single_file_path_portrait = "",
            single_file_path_landscape = "",
            cycle_minutes = 1,
            full_refresh_on_cycle = false,
        }
        self.local_storage:flush()
    end

    -- Migration: ensure cycle_minutes exists
    if self.local_storage.data.png_overlay.cycle_minutes == nil then
        self.local_storage.data.png_overlay.cycle_minutes = 1
        self.local_storage:flush()
    end

    -- Migration: ensure separate folder paths exist
    if self.local_storage.data.png_overlay.portrait_folder_path == nil then
        self.local_storage.data.png_overlay.portrait_folder_path = self.local_storage.data.png_overlay.folder_path or ""
        self.local_storage:flush()
    end
    if self.local_storage.data.png_overlay.landscape_folder_path == nil then
        self.local_storage.data.png_overlay.landscape_folder_path = self.local_storage.data.png_overlay.folder_path or ""
        self.local_storage:flush()
    end

    -- Migration: ensure separate single file paths exist
    if self.local_storage.data.png_overlay.single_file_path_portrait == nil then
        self.local_storage.data.png_overlay.single_file_path_portrait = self.local_storage.data.png_overlay.single_file_path or ""
        self.local_storage:flush()
    end
    if self.local_storage.data.png_overlay.single_file_path_landscape == nil then
        self.local_storage.data.png_overlay.single_file_path_landscape = self.local_storage.data.png_overlay.single_file_path or ""
        self.local_storage:flush()
    end

    -- Migration: ensure full_refresh_on_cycle exists
    if self.local_storage.data.png_overlay.full_refresh_on_cycle == nil then
        self.local_storage.data.png_overlay.full_refresh_on_cycle = false
        self.local_storage:flush()
    end

    if self.local_storage.data.png_overlay.invert_with_night_mode == nil then
        self.local_storage.data.png_overlay.invert_with_night_mode = true
        self.local_storage:flush()
    end

    -- Migration: remove obsolete suspend settings (v6)
    -- Keep the table for backward compat but values are no longer used
    if self.local_storage.data.suspend ~= nil then
        self.local_storage.data.suspend = nil
        self.local_storage:flush()
    end

    -- Migration: wake duration (how long CPU stays awake after RTC wakeup)
    if self.local_storage.data.wake_duration == nil then
        self.local_storage.data.wake_duration = 0.5
        self.local_storage:flush()
    end

    if self.local_storage.data.widget_brightness == nil then
        self.local_storage.data.widget_brightness = -1
    end

    if self.local_storage.data.full_refresh_minutes == nil then
        self.local_storage.data.full_refresh_minutes = 0 -- 0 = disabled
    end

    if self.local_storage.data.night_mode == nil then
        self.local_storage.data.night_mode = "follow"
        self.local_storage:flush()
    end

    if self.local_storage.data.clock_format == nil then
        self.local_storage.data.clock_format = "follow"
        self.local_storage:flush()
    end
    -- Migration: ensure advanced_settings toggle exists
    if self.local_storage.data.advanced_settings_enabled == nil then
        self.local_storage.data.advanced_settings_enabled = false
        self.local_storage:flush()
    end

    -- Migration: clock style
    if self.local_storage.data.clock_style == nil then
        self.local_storage.data.clock_style = "classic"
        self.local_storage:flush()
    end

    -- Migration: auto-layout
    if self.local_storage.data.auto_layout_enabled == nil then
        self.local_storage.data.auto_layout_enabled = true
        self.local_storage:flush()
    end
    if self.local_storage.data.auto_layout_gap == nil then
        self.local_storage.data.auto_layout_gap = 20
        self.local_storage:flush()
    end

    -- Migration: CPU governor removed in v5

    -- Migration: decorations
    if self.local_storage.data.separator_style == nil then
        self.local_storage.data.separator_style = "none"
        self.local_storage:flush()
    end
    if self.local_storage.data.border_frame_style == nil then
        self.local_storage.data.border_frame_style = "none"
        self.local_storage:flush()
    end

    -- Migration: outline width
    if self.local_storage.data.outline_width == nil then
        self.local_storage.data.outline_width = 3
        self.local_storage:flush()
    end

    -- Migration: analog options
    if self.local_storage.data.analog_opts == nil then
        self.local_storage.data.analog_opts = {
            numerals = "arabic",
            hand_width_hour = 6,
            hand_width_min = 4,
        }
        self.local_storage:flush()
    end

    -- Migration: text size preset
    if self.local_storage.data.text_size == nil then
        self.local_storage.data.text_size = "medium"
        self.local_storage:flush()
    end

    -- Migration: analog mini-infos
    if self.local_storage.data.analog_infos == nil then
        self.local_storage.data.analog_infos = {"battery"}
        self.local_storage:flush()
    end

end






function DtDisplay:addToMainMenu(menu_items)
    -- Quick-launch shortcut in the "screen" section, near KOReader's night mode toggle
    menu_items.dtdisplay_shortcut = {
        text = _("Time & Day clock"),
        sorting_hint = "screen",
        callback = function()
            UIManager:show(DisplayWidget:new { props = self:getEffectiveProps(), plugin_dir = PLUGIN_DIR, plugin_ref = self })
        end,
    }

    -- Main settings entry
    menu_items.dtdisplay = {
        text = _("Time & Day"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Launch"),
                callback = function()
                    UIManager:show(DisplayWidget:new { props = self:getEffectiveProps(), plugin_dir = PLUGIN_DIR, plugin_ref = self })
                end,
            },
            {
                text = _("Customise clock (UI version)"),
                separator = true,
                callback = function()
                    local CustomizerWidget = require("customizerwidget")
                    local customizer = CustomizerWidget:new {
                        plugin_ref = self,
                        on_save = function()
                            -- Redraw active clock if currently shown
                        end
                    }
                    UIManager:show(customizer)
                end,
            },
            {
                text = _("Clock settings"),
                sub_item_table = {
                    {
                        text = _("Clock format"),
                        sub_item_table = self:getClockFormatMenuList(),
                    },
                    {
                        text = _("Clock style"),
                        sub_item_table = self:getClockStyleMenuList(),
                    },
                    {
                        text = _("Clock orientation"),
                        sub_item_table = self:getRotationMenuList(),
                    },
                },
            },
            {
                text = _("Appearance"),
                sub_item_table = {
                    {
                        text = _("Text size"),
                        sub_item_table = self:getTextSizeMenuList(),
                    },
                    {
                        text = _("Time font face"),
                        sub_item_table = self:getFontFaceOnlyMenuList({
                            font_callback = function(font_name)
                                self:setTimeFont(font_name)
                            end,
                            checked_func = function(font)
                                return font == self.settings.time_widget.font_name
                            end,
                        }),
                    },
                    {
                        text = _("Date font face"),
                        sub_item_table = self:getFontFaceOnlyMenuList({
                            font_callback = function(font_name)
                                self:setDateFont(font_name)
                            end,
                            checked_func = function(font)
                                return font == self.settings.date_widget.font_name
                            end,
                        }),
                        separator = true,
                    },
                    {
                        text_func = function()
                            local b = self.settings.widget_brightness
                            if not b or b < 0 then
                                return _("Widget brightness: disabled")
                            end
                            return T(_("Widget brightness: %1"), b)
                        end,
                        keep_menu_open = true,
                        separator = true,
                        callback = function(touchmenu_instance)
                            self:showBrightnessSpinWidget(
                                touchmenu_instance,
                                self.settings.widget_brightness,
                                function(new_val)
                                    self.settings.widget_brightness = new_val
                                    self.local_storage:reset(self.settings)
                                    self.local_storage:flush()
                                end
                            )
                        end,
                    },
                    {
                        text = _("Night mode"),
                        sub_item_table = self:getNightModeMenuList(),
                    },
                    {
                        text = _("Image overlay"),
                        sub_item_table = self:getPngOverlayMenuList(),
                        separator = true,
                    },
                    {
                        text = _("Auto-layout (prevent overlap)"),
                        checked_func = function()
                            return self.settings.auto_layout_enabled ~= false
                        end,
                        callback = function()
                            self.settings.auto_layout_enabled = not (self.settings.auto_layout_enabled ~= false)
                            self.local_storage:reset(self.settings)
                            self.local_storage:flush()
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Auto-layout gap: %1 px"), self.settings.auto_layout_gap or 20)
                        end,
                        keep_menu_open = true,
                        enabled_func = function()
                            return self.settings.auto_layout_enabled ~= false
                        end,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new {
                                value = self.settings.auto_layout_gap or 20,
                                value_min = 0,
                                value_max = 100,
                                value_step = 5,
                                value_hold_step = 10,
                                ok_text = _("Set gap"),
                                title_text = _("Spacing between elements (pixels)"),
                                callback = function(spin)
                                    self.settings.auto_layout_gap = spin.value
                                    self.local_storage:reset(self.settings)
                                    self.local_storage:flush()
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                        separator = true,
                    },
                    {
                        text = _("Decorations"),
                        sub_item_table = self:getDecorationMenuList(),
                    },
                },
            },
            {
                text_func = function()
                    local total = self.settings.full_refresh_minutes or 0
                    if total == 0 then
                        return _("Full refresh: disabled")
                    end
                    local h = math.floor(total / 60)
                    local m = total % 60
                    if h == 0 then
                        return T(_("Full refresh: every %1 min"), m)
                    elseif m == 0 then
                        return T(_("Full refresh: every %1 h"), h)
                    else
                        return T(_("Full refresh: every %1 h %2 min"), h, m)
                    end
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:showFullRefreshSpinWidget(touchmenu_instance)
                end,
            },
            {
                text = _("Power & suspend"),
                sub_item_table = self:getPowerMenuList(),
            },
            {
                text_func = function()
                    if self.settings.advanced_settings_enabled then
                        return _("Advanced settings: ON ✓")
                    else
                        return _("Advanced settings: OFF")
                    end
                end,
                checked_func = function()
                    return self.settings.advanced_settings_enabled == true
                end,
                separator = true,
                callback = function(touchmenu_instance)
                    self.settings.advanced_settings_enabled = not self.settings.advanced_settings_enabled
                    self.local_storage:reset(self.settings)
                    self.local_storage:flush()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
        },
    }
end

function DtDisplay:getRotationMenuList()
    local rotation_labels = {
        [0] = _("0° (Portrait)"),
        [1] = _("90° (Landscape clockwise)"),
        [2] = _("180° (Portrait inverted)"),
        [3] = _("270° (Landscape counter-clockwise)"),
    }

    local menu_list = {
        {
            text = _("Follow KOReader orientation"),
            checked_func = function()
                return self.settings.rotation.follow_koreader
            end,
            callback = function()
                self:setRotationFollowKOReader(true)
            end,
            separator = true,
        },
    }

    for rotation = 0, 3 do
        table.insert(menu_list, {
            text = rotation_labels[rotation],
            checked_func = function()
                return not self.settings.rotation.follow_koreader
                    and self.settings.rotation.custom_rotation == rotation
            end,
            callback = function()
                self:setCustomRotation(rotation)
            end,
        })
    end

    return menu_list
end

function DtDisplay:getClockFormatMenuList()
    return {
        {
            text = _("Follow KOReader setting"),
            checked_func = function()
                return self.settings.clock_format == "follow"
            end,
            callback = function()
                self:setClockFormat("follow")
            end,
            separator = true,
        },
        {
            text = _("24-hour"),
            checked_func = function()
                return self.settings.clock_format == "24"
            end,
            callback = function()
                self:setClockFormat("24")
            end,
        },
        {
            text = _("12-hour (AM/PM)"),
            checked_func = function()
                return self.settings.clock_format == "12"
            end,
            callback = function()
                self:setClockFormat("12")
            end,
        },
    }
end

function DtDisplay:getNightModeMenuList()
    return {
        {
            text = _("Follow KOReader setting"),
            checked_func = function()
                return self.settings.night_mode == "follow"
            end,
            callback = function()
                self:setNightMode("follow")
            end,
            separator = true,
        },
        {
            text = _("Light mode"),
            checked_func = function()
                return self.settings.night_mode == "normal"
            end,
            callback = function()
                self:setNightMode("normal")
            end,
        },
        {
            text = _("Night mode"),
            checked_func = function()
                return self.settings.night_mode == "night"
            end,
            callback = function()
                self:setNightMode("night")
            end,
        },
    }
end

function DtDisplay:setNightMode(mode)
    self.settings.night_mode = mode
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setClockFormat(fmt)
    self.settings.clock_format = fmt
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

-- ---------------------------------------------------------------------------
-- Clock style menu
-- ---------------------------------------------------------------------------

function DtDisplay:getClockStyleMenuList()
    local styles = {
        { id = "classic",    label = _("Digital classic") },
        { id = "fullscreen", label = _("Digital fullscreen") },
        { id = "analog",     label = _("Analog") },
        { id = "outlined",   label = _("Outlined digital") },
        { id = "wordclock",  label = _("Word clock (French)") },
    }

    local menu_list = {}
    for _, s in ipairs(styles) do
        table.insert(menu_list, {
            text = s.label,
            checked_func = function()
                return (self.settings.clock_style or "classic") == s.id
            end,
            callback = function()
                self.settings.clock_style = s.id
                self.local_storage:reset(self.settings)
                self.local_storage:flush()
            end,
        })
    end

    -- Add analog sub-options
    table.insert(menu_list, {
        text = _("Analog: numeral style"),
        enabled_func = function() return self.settings.clock_style == "analog" end,
        sub_item_table = self:getAnalogNumeralMenuList(),
    })

    -- Add analog mini-infos chooser
    table.insert(menu_list, {
        text = _("Analog: info bar"),
        enabled_func = function() return self.settings.clock_style == "analog" end,
        sub_item_table = self:getAnalogInfosMenuList(),
        separator = true,
    })

    -- Add outline width option
    table.insert(menu_list, {
        text_func = function()
            return T(_("Outline width: %1 px"), self.settings.outline_width or 3)
        end,
        keep_menu_open = true,
        enabled_func = function() return self.settings.clock_style == "outlined" end,
        callback = function(touchmenu_instance)
            local SpinWidget = require("ui/widget/spinwidget")
            UIManager:show(SpinWidget:new {
                value = self.settings.outline_width or 3,
                value_min = 1,
                value_max = 8,
                value_step = 1,
                ok_text = _("Set width"),
                title_text = _("Text outline width (pixels)"),
                callback = function(spin)
                    self.settings.outline_width = spin.value
                    self.local_storage:reset(self.settings)
                    self.local_storage:flush()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    })

    return menu_list
end

function DtDisplay:getAnalogNumeralMenuList()
    local options = {
        { id = "arabic", label = _("Arabic (1, 2, 3…)") },
        { id = "roman",  label = _("Roman (I, II, III…)") },
        { id = "none",   label = _("No numerals") },
    }
    local menu_list = {}
    for _, opt in ipairs(options) do
        table.insert(menu_list, {
            text = opt.label,
            checked_func = function()
                local opts = self.settings.analog_opts or {}
                return (opts.numerals or "arabic") == opt.id
            end,
            callback = function()
                if not self.settings.analog_opts then
                    self.settings.analog_opts = {}
                end
                self.settings.analog_opts.numerals = opt.id
                self.local_storage:reset(self.settings)
                self.local_storage:flush()
            end,
        })
    end
    return menu_list
end

-- ---------------------------------------------------------------------------
-- Decoration menu
-- ---------------------------------------------------------------------------

function DtDisplay:getDecorationMenuList()
    return {
        {
            text = _("Separator between elements"),
            sub_item_table = self:getSeparatorStyleMenuList(),
        },
        {
            text = _("Border frame"),
            sub_item_table = self:getBorderFrameMenuList(),
        },
    }
end

function DtDisplay:getSeparatorStyleMenuList()
    local options = {
        { id = "none",     label = _("None") },
        { id = "line",     label = _("Line with diamond") },
        { id = "dots",     label = _("Dotted line") },
        { id = "diamond",  label = _("Triple diamond") },
        { id = "ornament", label = _("Ornamental") },
    }
    local menu_list = {}
    for _, opt in ipairs(options) do
        table.insert(menu_list, {
            text = opt.label,
            checked_func = function()
                return (self.settings.separator_style or "none") == opt.id
            end,
            callback = function()
                self.settings.separator_style = opt.id
                self.local_storage:reset(self.settings)
                self.local_storage:flush()
            end,
        })
    end
    return menu_list
end

function DtDisplay:getBorderFrameMenuList()
    local options = {
        { id = "none",   label = _("None") },
        { id = "simple", label = _("Simple border") },
        { id = "double", label = _("Double border") },
        { id = "corner", label = _("Corner marks") },
    }
    local menu_list = {}
    for _, opt in ipairs(options) do
        table.insert(menu_list, {
            text = opt.label,
            checked_func = function()
                return (self.settings.border_frame_style or "none") == opt.id
            end,
            callback = function()
                self.settings.border_frame_style = opt.id
                self.local_storage:reset(self.settings)
                self.local_storage:flush()
            end,
        })
    end
    return menu_list
end

-- ---------------------------------------------------------------------------
-- Power & suspend menu
-- ---------------------------------------------------------------------------

function DtDisplay:getPowerMenuList()
    return self:getSuspendMenuList()
end

-- ---------------------------------------------------------------------------
-- Text size preset menu
-- ---------------------------------------------------------------------------

function DtDisplay:getTextSizeMenuList()
    local presets = {
        { id = "small",  label = _("Small") },
        { id = "medium", label = _("Medium") },
        { id = "big",    label = _("Big") },
        { id = "huge",   label = _("Huge") },
    }
    local menu_list = {}
    for _, p in ipairs(presets) do
        table.insert(menu_list, {
            text = p.label,
            checked_func = function()
                return (self.settings.text_size or "medium") == p.id
            end,
            callback = function()
                self.settings.text_size = p.id
                self.local_storage:reset(self.settings)
                self.local_storage:flush()
            end,
        })
    end
    return menu_list
end

-- ---------------------------------------------------------------------------
-- Font face menu (no size spinner — size is handled by text_size preset)
-- ---------------------------------------------------------------------------

function DtDisplay:getFontFaceOnlyMenuList(args)
    local font_callback = args.font_callback
    local checked_func  = args.checked_func

    cre = require("document/credocument"):engineInit()
    local face_list = cre.getFontFaces()
    local menu_list = {}

    for k, v in ipairs(face_list) do
        local font_filename, font_faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(v)
        table.insert(menu_list, {
            text_func = function()
                local default_font = G_reader_settings:readSetting("cre_font")
                local fallback_font = G_reader_settings:readSetting("fallback_font")
                local monospace_font = G_reader_settings:readSetting("monospace_font")
                local text = v
                if font_filename and font_faceindex then
                    text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
                end
                if v == monospace_font then
                    text = text .. " \u{1F13C}"
                elseif is_monospace then
                    text = text .. " \u{1D39}"
                end
                if v == default_font then
                    text = text .. "   ★"
                end
                if v == fallback_font then
                    text = text .. "   "
                end
                return text
            end,
            font_func = function(size)
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if font_filename and font_faceindex then
                        return Font:getFace(font_filename, size, font_faceindex)
                    end
                end
            end,
            callback = function()
                return font_callback(font_filename)
            end,
            checked_func = function()
                return checked_func(font_filename)
            end,
            menu_item_id = v,
        })
    end

    return menu_list
end

-- ---------------------------------------------------------------------------
-- Analog clock mini-info chooser
-- ---------------------------------------------------------------------------

function DtDisplay:getAnalogInfosMenuList()
    local available = {
        { id = "date",            label = _("Date") },
        { id = "battery",        label = _("Battery level") },
        { id = "memory",         label = _("RAM usage") },
        { id = "worldclock_nyc", label = _("World clock: NYC") },
    }
    local menu_list = {}

    local function hasInfo(info_id)
        local infos = self.settings.analog_infos or {"battery"}
        for _, v in ipairs(infos) do
            if v == info_id then return true end
        end
        return false
    end

    local function toggleInfo(info_id)
        local infos = self.settings.analog_infos or {"battery"}
        local new_infos = {}
        local found = false
        for _, v in ipairs(infos) do
            if v == info_id then
                found = true  -- skip to remove
            else
                table.insert(new_infos, v)
            end
        end
        if not found then
            table.insert(new_infos, info_id)
        end
        self.settings.analog_infos = new_infos
        self.local_storage:reset(self.settings)
        self.local_storage:flush()
    end

    for _, opt in ipairs(available) do
        table.insert(menu_list, {
            text = opt.label,
            checked_func = function() return hasInfo(opt.id) end,
            callback = function() toggleInfo(opt.id) end,
        })
    end

    return menu_list
end

-- ---------------------------------------------------------------------------
-- Quick menu (shown when tapping to exit the clock display)
-- ---------------------------------------------------------------------------

function DtDisplay:showQuickMenu()
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local dialog

    local style_labels = {
        classic    = _("Digital Classic"),
        fullscreen = _("Digital Fullscreen"),
        analog     = _("Analog"),
        outlined   = _("Outlined"),
        wordclock  = _("Word Clock"),
    }
    local current_style = self.settings.clock_style or "classic"
    local current_label = style_labels[current_style] or current_style

    dialog = ButtonDialogTitle:new {
        title = _("Time & Day"),
        info = T(_("Current style: %1"), current_label),
        buttons = {
            {
                {
                    text = _("⟳ Relaunch"),
                    callback = function()
                        UIManager:close(dialog)
                        UIManager:show(DisplayWidget:new {
                            props = self:getEffectiveProps(),
                            plugin_dir = PLUGIN_DIR,
                            plugin_ref = self,
                        })
                    end,
                },
                {
                    text = _("Change style ▸"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showStyleQuickPicker()
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function DtDisplay:showStyleQuickPicker()
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local dialog
    local styles = {
        {"classic", _("Classic")}, {"fullscreen", _("Fullscreen")},
        {"analog", _("Analog")}, {"outlined", _("Outlined")},
        {"wordclock", _("Word Clock")},
    }

    local buttons = {}
    for _, s in ipairs(styles) do
        local is_current = (self.settings.clock_style or "classic") == s[1]
        table.insert(buttons, {
            {
                text = (is_current and "● " or "○ ") .. s[2],
                callback = function()
                    self.settings.clock_style = s[1]
                    self.local_storage:reset(self.settings)
                    self.local_storage:flush()
                    UIManager:close(dialog)
                    -- Launch with new style
                    UIManager:show(DisplayWidget:new {
                        props = self:getEffectiveProps(),
                        plugin_dir = PLUGIN_DIR,
                        plugin_ref = self,
                    })
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("← Back"),
            callback = function()
                UIManager:close(dialog)
                self:showQuickMenu()
            end,
        },
    })

    dialog = ButtonDialogTitle:new {
        title = _("Choose clock style"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end


function DtDisplay:setRotationFollowKOReader(follow)
    self.settings.rotation.follow_koreader = follow
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setCustomRotation(rotation)
    self.settings.rotation.follow_koreader = false
    self.settings.rotation.custom_rotation = rotation
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

--- Build the power settings submenu
function DtDisplay:getSuspendMenuList()
    local menu_list = {}

    -- Wake duration spinner
    table.insert(menu_list, {
        text_func = function()
            local dur = self.settings.wake_duration or 0.5
            return T(_("CPU wake duration: %1 s"), string.format("%.1f", dur))
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local SpinWidget = require("ui/widget/spinwidget")
            local current_value = math.floor((self.settings.wake_duration or 0.5) * 10)
            UIManager:show(
                SpinWidget:new {
                    value = current_value,
                    value_min = 1,   -- 0.1s
                    value_max = 50,  -- 5.0s
                    value_step = 1,
                    value_hold_step = 5,
                    ok_text = _("Set duration"),
                    title_text = _("CPU wake duration (×0.1 seconds)\nHow long the CPU stays awake after refreshing\nthe clock. Increase if the screen doesn't\nupdate properly on your device."),
                    callback = function(spin)
                        self.settings.wake_duration = spin.value / 10
                        self.local_storage:reset(self.settings)
                        self.local_storage:flush()
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end
                }
            )
        end,
        separator = true,
    })

    -- Info: current behavior
    table.insert(menu_list, {
        text_func = function()
            return _("Status: Always uses RTC deep sleep (most efficient)")
        end,
        keep_menu_open = true,
        callback = function() end,
    })

    return menu_list
end

--- Save power settings
function DtDisplay:saveSuspendSettings()
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

--- Get the recommended resolution string based on current screen size
function DtDisplay:getRecommendedResolutionText()
    local screen_size = Screen:getSize()
    local sw, sh = screen_size.w, screen_size.h
    local pw, ph
    if sw > sh then
        pw, ph = sh, sw
    else
        pw, ph = sw, sh
    end
    return T(_("Recommended: %1x%2 (portrait) / %3x%4 (landscape)"), pw, ph, ph, pw)
end

--- Build the PNG overlay submenu
function DtDisplay:getPngOverlayMenuList()
    local menu_list = {}

    -- Info: recommended resolution
    table.insert(menu_list, {
        text_func = function()
            return self:getRecommendedResolutionText()
        end,
        keep_menu_open = true,
        callback = function() end,
        separator = true,
    })

    -- Toggle: enable/disable overlay
    table.insert(menu_list, {
        text = _("Enable PNG overlay"),
        checked_func = function()
            return self.settings.png_overlay.enabled
        end,
        callback = function()
            self.settings.png_overlay.enabled = not self.settings.png_overlay.enabled
            self:savePngOverlaySettings()
        end,
        separator = true,
    })

    -- Portrait folder selection
    table.insert(menu_list, {
        text_func = function()
            local folder = self.settings.png_overlay.portrait_folder_path
            if folder and folder ~= "" then
                local short = folder:match("([^/]+)$") or folder
                return T(_("Portrait PNG folder: %1"), short)
            else
                return _("Select portrait PNG folder")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:showPngFolderChooser(touchmenu_instance, "portrait")
        end,
    })

    -- Landscape folder selection
    table.insert(menu_list, {
        text_func = function()
            local folder = self.settings.png_overlay.landscape_folder_path
            if folder and folder ~= "" then
                local short = folder:match("([^/]+)$") or folder
                return T(_("Landscape PNG folder: %1"), short)
            else
                return _("Select landscape PNG folder")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:showPngFolderChooser(touchmenu_instance, "landscape")
        end,
        separator = true,
    })

    -- Select single PNG file for portrait
    table.insert(menu_list, {
        text_func = function()
            local fpath = self.settings.png_overlay.single_file_path_portrait
            if fpath and fpath ~= "" then
                local fname = fpath:match("([^/]+)$") or fpath
                return T(_("Portrait file: %1"), fname)
            else
                return _("Select a portrait PNG file")
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            local folder = self.settings.png_overlay.portrait_folder_path
            return folder and folder ~= ""
        end,
        callback = function(touchmenu_instance)
            self:showPngFileSelector(touchmenu_instance, "portrait")
        end,
    })

    -- Select single PNG file for landscape
    table.insert(menu_list, {
        text_func = function()
            local fpath = self.settings.png_overlay.single_file_path_landscape
            if fpath and fpath ~= "" then
                local fname = fpath:match("([^/]+)$") or fpath
                return T(_("Landscape file: %1"), fname)
            else
                return _("Select a landscape PNG file")
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            local folder = self.settings.png_overlay.landscape_folder_path
            return folder and folder ~= ""
        end,
        callback = function(touchmenu_instance)
            self:showPngFileSelector(touchmenu_instance, "landscape")
        end,
        separator = true,
    })

    -- Image selection mode: single
    table.insert(menu_list, {
        text = _("Use single image"),
        checked_func = function()
            return self.settings.png_overlay.mode == "single"
        end,
        callback = function()
            self.settings.png_overlay.mode = "single"
            self:savePngOverlaySettings()
        end,
    })

    -- Image selection mode: cycle
    table.insert(menu_list, {
        text = _("Cycle through all images in folder"),
        checked_func = function()
            return self.settings.png_overlay.mode == "cycle"
        end,
        callback = function()
            self.settings.png_overlay.mode = "cycle"
            self:savePngOverlaySettings()
        end,
        separator = true,
    })

    -- Cycle interval setting
    table.insert(menu_list, {
        text_func = function()
            local mins = self.settings.png_overlay.cycle_minutes or 1
            if mins == 1 then
                return T(_("Cycle interval: %1 minute"), mins)
            else
                return T(_("Cycle interval: %1 minutes"), mins)
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            return self.settings.png_overlay.mode == "cycle"
        end,
        callback = function(touchmenu_instance)
            self:showCycleIntervalSpinWidget(touchmenu_instance)
        end,
        separator = true,
    })

    -- Full refresh on cycle toggle
    table.insert(menu_list, {
        text = _("Full screen refresh on image change"),
        checked_func = function()
            return self.settings.png_overlay.full_refresh_on_cycle
        end,
        callback = function()
            self.settings.png_overlay.full_refresh_on_cycle = not self.settings.png_overlay.full_refresh_on_cycle
            self:savePngOverlaySettings()
        end,
    })

    -- Night mode image inversion toggle
    table.insert(menu_list, {
        text = _("Invert image in night mode"),
        checked_func = function()
            return self.settings.png_overlay.invert_with_night_mode ~= false
        end,
        callback = function()
            self.settings.png_overlay.invert_with_night_mode =
                not (self.settings.png_overlay.invert_with_night_mode ~= false)
            self:savePngOverlaySettings()
        end,
        separator = true,
    })
    table.insert(menu_list, {
        text = _("Use per-image config files (*.lua)"),
        checked_func = function()
            return self.settings.png_overlay.use_image_config == true
        end,
        callback = function()
            self.settings.png_overlay.use_image_config = not self.settings.png_overlay.use_image_config
            self:savePngOverlaySettings()
        end,
        separator = true,
    })

    return menu_list
end

--- Save PNG overlay settings to persistent storage
function DtDisplay:savePngOverlaySettings()
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

--- Show folder chooser dialog for PNG folder selection
function DtDisplay:showPngFolderChooser(touchmenu_instance, orientation_type)
    local PathChooser = require("ui/widget/pathchooser")
    local setting_key
    if orientation_type == "portrait" then
        setting_key = "portrait_folder_path"
    else
        setting_key = "landscape_folder_path"
    end

    local start_path = self.settings.png_overlay[setting_key]
    if not start_path or start_path == "" then
        start_path = DataStorage:getDataDir()
    end

    local path_chooser = PathChooser:new {
        select_directory = true,
        select_file = false,
        path = start_path,
        onConfirm = function(chosen_path)
            self.settings.png_overlay[setting_key] = chosen_path
            self.settings.png_overlay.folder_path = chosen_path
            if orientation_type == "portrait" then
                self.settings.png_overlay.single_file_path_portrait = ""
            else
                self.settings.png_overlay.single_file_path_landscape = ""
            end
            self:savePngOverlaySettings()
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }
    UIManager:show(path_chooser)
end

--- Show file selector dialog to pick a single PNG.
function DtDisplay:showPngFileSelector(touchmenu_instance, orientation_type)
    local folder_key, file_key
    if orientation_type == "portrait" then
        folder_key = "portrait_folder_path"
        file_key = "single_file_path_portrait"
    else
        folder_key = "landscape_folder_path"
        file_key = "single_file_path_landscape"
    end

    local folder = self.settings.png_overlay[folder_key]
    if not folder or folder == "" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = _("Please select a PNG folder first."),
        })
        return
    end

    local lfs = require("libs/libkoreader-lfs")
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, folder)
    if not ok then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = _("Cannot open the selected folder."),
        })
        return
    end

    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local lower = entry:lower()
            if lower:match("%.png$") then
                table.insert(files, entry)
            end
        end
    end

    table.sort(files)

    local valid_files = {}
    local screen_size = Screen:getSize()
    local sw, sh = screen_size.w, screen_size.h
    local native_w, native_h
    if sw > sh then
        native_w, native_h = sh, sw
    else
        native_w, native_h = sw, sh
    end

    for _, fname in ipairs(files) do
        local fpath = folder .. "/" .. fname
        local img_w, img_h = self:readPngDimensions(fpath)
        if img_w and img_h then
            if (img_w == native_w and img_h == native_h) or (img_w == native_h and img_h == native_w) then
                table.insert(valid_files, fname)
            end
        end
    end

    if #valid_files == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = T(_("No PNG files with valid resolution found.\nExpected: %1x%2 or %3x%4"), native_w, native_h, native_h, native_w),
        })
        return
    end

    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local buttons = {}
    for _, fname in ipairs(valid_files) do
        table.insert(buttons, {
            {
                text = fname,
                callback = function()
                    self.settings.png_overlay[file_key] = folder .. "/" .. fname
                    self.settings.png_overlay.single_file_path = folder .. "/" .. fname
                    self:savePngOverlaySettings()
                    UIManager:close(self._png_file_dialog)
                    self._png_file_dialog = nil
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
        })
    end

    self._png_file_dialog = ButtonDialogTitle:new {
        title = T(_("Select a %1 PNG file"), orientation_type),
        buttons = buttons,
    }
    UIManager:show(self._png_file_dialog)
end

--- Read PNG dimensions from file header.
function DtDisplay:readPngDimensions(filepath)
    local f = io.open(filepath, "rb")
    if not f then
        return nil, nil
    end
    local header = f:read(24)
    f:close()
    if not header or #header < 24 then
        return nil, nil
    end
    local png_sig = "\137PNG\r\n\026\n"
    if header:sub(1, 8) ~= png_sig then
        return nil, nil
    end
    local function read_be_uint32(s, offset)
        local b1, b2, b3, b4 = s:byte(offset, offset + 3)
        return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    end
    local w = read_be_uint32(header, 17)
    local h = read_be_uint32(header, 21)
    return w, h
end

--- Show spin widget for cycle interval setting
function DtDisplay:showCycleIntervalSpinWidget(touchmenu_instance)
    local SpinWidget = require("ui/widget/spinwidget")
    local current_value = self.settings.png_overlay.cycle_minutes or 1
    UIManager:show(
        SpinWidget:new {
            value = current_value,
            value_min = 1,
            value_max = 120,
            value_step = 1,
            value_hold_step = 5,
            ok_text = _("Set interval"),
            title_text = _("Image cycle interval (minutes)"),
            callback = function(spin)
                self.settings.png_overlay.cycle_minutes = spin.value
                self:savePngOverlaySettings()
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end
        }
    )
end

function DtDisplay:getFontMenuList(args)
    -- Unpack arguments
    local font_callback = args.font_callback
    local font_size_callback = args.font_size_callback
    local font_size_func = args.font_size_func
    local checked_func = args.checked_func

    -- Based on readerfont.lua
    cre = require("document/credocument"):engineInit()
    local face_list = cre.getFontFaces()
    local menu_list = {}

    -- Font size
    table.insert(menu_list, {
        text_func = function()
            return T(_("Font size: %1"), font_size_func())
        end,
        callback = function(touchmenu_instance)
            self:showFontSizeSpinWidget(touchmenu_instance, font_size_func(), font_size_callback)
        end,
        keep_menu_open = true,
        separator = true
    })

    -- Font list
    for k, v in ipairs(face_list) do
        local font_filename, font_faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(v)
        table.insert(menu_list, {
            text_func = function()
                local default_font = G_reader_settings:readSetting("cre_font")
                local fallback_font = G_reader_settings:readSetting("fallback_font")
                local monospace_font = G_reader_settings:readSetting("monospace_font")
                local text = v
                if font_filename and font_faceindex then
                    text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
                end

                if v == monospace_font then
                    text = text .. " \u{1F13C}"
                elseif is_monospace then
                    text = text .. " \u{1D39}"
                end
                if v == default_font then
                    text = text .. "   ★"
                end
                if v == fallback_font then
                    text = text .. "   "
                end
                return text
            end,
            font_func = function(size)
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if font_filename and font_faceindex then
                        return Font:getFace(font_filename, size, font_faceindex)
                    end
                end
            end,
            callback = function()
                return font_callback(font_filename)
            end,
            hold_callback = function(touchmenu_instance)
            end,
            checked_func = function()
                return checked_func(font_filename)
            end,
            menu_item_id = v,
        })
    end

    return menu_list
end

function DtDisplay:setDateFont(font)
    self.settings["date_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setTimeFont(font)
    self.settings["time_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setStatuslineFont(font)
    self.settings["status_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setDateFontSize(font_size)
    self.settings["date_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setTimeFontSize(font_size)
    self.settings["time_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:setStatuslineFontSize(font_size)
    self.settings["status_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function DtDisplay:showDateTimeWidget()
    UIManager:show(DisplayWidget:new { plugin_dir = PLUGIN_DIR })
end

function DtDisplay:onDTDisplayLaunch()
    UIManager:show(DisplayWidget:new { props = self:getEffectiveProps(), plugin_dir = PLUGIN_DIR })
end

function DtDisplay:showFontSizeSpinWidget(touchmenu_instance, font_size, callback)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(
        SpinWidget:new {
            value = font_size,
            value_min = 8,
            value_max = 256,
            value_step = 1,
            value_hold_step = 10,
            ok_text = _("Set font size"),
            title_text = _("Set font size"),
            callback = function(spin)
                callback(spin.value)
                touchmenu_instance:updateItems()
            end
        }
    )
end

function DtDisplay:onDispatcherRegisterActions()
    Dispatcher:registerAction("dtdisplay_launch", { category="none", event="DTDisplayLaunch", title=_("Launch Time & Day"), general=true})
end

function DtDisplay:showBrightnessSpinWidget(touchmenu_instance, current_brightness, callback)
    local SpinWidget = require("ui/widget/spinwidget")
    local max_intensity = 24
    if Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        if powerd and powerd.fl_max then
            max_intensity = powerd.fl_max
        end
    end
    UIManager:show(
        SpinWidget:new {
            value = current_brightness,
            value_min = -1, -- Allow -1 to disable the feature
            value_max = max_intensity,
            value_step = 1,
            value_hold_step = 5,
            ok_text = _("Set brightness"),
            title_text = _("Widget Brightness (-1 to disable)"),
            callback = function(spin)
                callback(spin.value)
                touchmenu_instance:updateItems()
            end
        }
    )
end

function DtDisplay:showFullRefreshSpinWidget(touchmenu_instance)
    local total_minutes = self.settings.full_refresh_minutes or 0
    local current_hours = math.floor(total_minutes / 60)
    local current_minutes = total_minutes % 60

    local DateTimeWidget = require("ui/widget/datetimewidget")

    UIManager:show(DateTimeWidget:new {
        hour = current_hours,
        min = current_minutes,
        ok_text = _("Set interval"),
        title_text = _("Full refresh interval (0h 0min = disabled)"),
        callback = function(time)
            local total = time.hour * 60 + time.min
            self.settings.full_refresh_minutes = total
            self.local_storage:reset(self.settings)
            self.local_storage:flush()
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    })
end

--- Returns self.settings merged with advanced_settings.lua when the toggle is on.
--- Values in the file win over UI values, but only if they are not nil.
function DtDisplay:getEffectiveProps()
    -- When the toggle is off, use UI settings as-is
    if not self.settings.advanced_settings_enabled then
        return self.settings
    end

    local adv_path = PLUGIN_DIR .. "advanced_settings.lua"
    local ok, adv = pcall(dofile, adv_path)

    -- If the file is missing, empty, or has a syntax error, fall back silently
    if not ok or type(adv) ~= "table" then
        return self.settings
    end

    -- Shallow-clone self.settings so we don't mutate the stored settings
    local merged = {}
    for k, v in pairs(self.settings) do
        if type(v) == "table" then
            local sub = {}
            for k2, v2 in pairs(v) do sub[k2] = v2 end
            merged[k] = sub
        else
            merged[k] = v
        end
    end

    -- Overlay with values from the file (nil values are skipped → UI wins)
    for k, v in pairs(adv) do
        if type(v) == "table" and type(merged[k]) == "table" then
            for k2, v2 in pairs(v) do
                if v2 ~= nil then
                    merged[k][k2] = v2
                end
            end
        elseif v ~= nil then
            merged[k] = v
        end
    end

    return merged
end

function DtDisplay:patchDofile()
    if not _G._orig_dofile_before_dtdisplay then
        local orig_dofile = dofile
        _G._orig_dofile_before_dtdisplay = orig_dofile

        _G.dofile = function(filepath)
            local result = orig_dofile(filepath)

            -- Check if this is the screensaver menu being loaded
            if filepath and filepath:match("screensaver_menu%.lua$") then
                logger.dbg("DtDisplay: Patching screensaver menu")

                if result and result[1] and result[1].sub_item_table then
                    local wallpaper_submenu = result[1].sub_item_table

                    local function genMenuItem(text, setting, value, enabled_func, separator)
                        return {
                            text = text,
                            enabled_func = enabled_func,
                            checked_func = function()
                                return G_reader_settings:readSetting(setting) == value
                            end,
                            radio = true,
                            separator = separator,
                            callback = function()
                                G_reader_settings:saveSetting(setting, value)
                            end,
                        }
                    end

                    -- Add clock screensaver option
                    local dtdisplay_item = genMenuItem(_("Show clock on sleep screen"), "screensaver_type", "dtdisplay")

                    -- Insert before "Leave screen as-is" option (typically position 6)
                    table.insert(wallpaper_submenu, 6, dtdisplay_item)
                    logger.dbg("DtDisplay: Added clock option to screensaver menu")
                end

                -- Restore original dofile after patching
                _G.dofile = orig_dofile
                _G._orig_dofile_before_dtdisplay = nil
            end

            return result
        end
    end
end

function DtDisplay:patchScreensaver()
    local plugin_instance = self
    local Screensaver = require("ui/screensaver")

    if not Screensaver._orig_show_before_dtdisplay then
        Screensaver._orig_show_before_dtdisplay = Screensaver.show
    end

    Screensaver.show = function(screensaver_instance)
        local ss_type = G_reader_settings:readSetting("screensaver_type")
        if ss_type == "dtdisplay" then
            screensaver_instance.screensaver_type = "dtdisplay"
            logger.dbg("DtDisplay: Clock screensaver activated")

            -- Capture original rotation before screensaver changes it!
            if not plugin_instance.original_rotation then
                plugin_instance.original_rotation = Screen:getRotationMode()
                logger.info("DtDisplay: Captured original rotation mode before sleep:", plugin_instance.original_rotation)
            end

            -- Schedule periodic refresh when screen locks
            plugin_instance:schedulePeriodicRefresh()

            -- Close any existing screensaver widget
            if screensaver_instance.screensaver_widget then
                UIManager:close(screensaver_instance.screensaver_widget)
                screensaver_instance.screensaver_widget = nil
            end

            -- Set device to screen saver mode first
            Device.screen_saver_mode = true

            -- Handle rotation if needed
            local ScreenSaverWidget = require("ui/widget/screensaverwidget")
            local Blitbuffer = require("ffi/blitbuffer")

            local rotation_mode = Screen:getRotationMode()
            Device.orig_rotation_mode = rotation_mode
            local bit = require("bit")
            if bit.band(Device.orig_rotation_mode, 1) == 1 then
                Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
            else
                Device.orig_rotation_mode = nil
            end

            logger.dbg("DtDisplay: Creating widget")
            local clock_widget = plugin_instance:createClockWidget()

            if clock_widget then
                logger.dbg("DtDisplay: Clock widget created successfully")
                local bg_color = Blitbuffer.COLOR_WHITE
                -- Simple check for night mode inversion
                local is_dark = false
                local mode = plugin_instance.settings.night_mode
                if mode == "night" then
                    is_dark = true
                elseif mode == "follow" then
                    is_dark = G_reader_settings:readSetting("night_mode")
                end

                if is_dark then
                    bg_color = Blitbuffer.COLOR_BLACK
                end

                screensaver_instance.screensaver_widget = ScreenSaverWidget:new {
                    widget = clock_widget,
                    background = bg_color,
                    covers_fullscreen = true,
                }
                screensaver_instance.screensaver_widget.modal = true
                screensaver_instance.screensaver_widget.dithered = true

                -- Wrap onCloseWidget to restore original rotation mode
                local orig_onCloseWidget = screensaver_instance.screensaver_widget.onCloseWidget
                screensaver_instance.screensaver_widget.onCloseWidget = function(this)
                    logger.dbg("DtDisplay: screensaver_widget onCloseWidget called")
                    if plugin_instance.original_rotation then
                        logger.info("DtDisplay: Restoring original rotation mode on screensaver close:", plugin_instance.original_rotation)
                        Screen:setRotationMode(plugin_instance.original_rotation)
                        plugin_instance.original_rotation = nil
                    end
                    if orig_onCloseWidget then
                        orig_onCloseWidget(this)
                    end
                end

                UIManager:show(screensaver_instance.screensaver_widget, "full")
                logger.dbg("DtDisplay: Widget displayed")
            else
                logger.warn("DtDisplay: No clock widget created, using fallback cover")
                -- Reset state we've already set up so original screensaver can set it properly
                Device.screen_saver_mode = false
                if Device.orig_rotation_mode then
                    Screen:setRotationMode(Device.orig_rotation_mode)
                    Device.orig_rotation_mode = nil
                end

                -- Temporarily set screensaver type to fallback cover (don't flush to disk)
                G_reader_settings:saveSetting("screensaver_type", "cover")

                -- Let KOReader's screensaver handle setup and display
                Screensaver:setup()
                Screensaver._orig_show_before_dtdisplay(screensaver_instance)

                -- Restore clock as the screensaver type (don't flush to disk)
                G_reader_settings:saveSetting("screensaver_type", "dtdisplay")
            end
        else
            logger.dbg("DtDisplay: Non-dtdisplay screensaver activated, calling original show")
            Screensaver._orig_show_before_dtdisplay(screensaver_instance)
        end
    end
end

function DtDisplay:schedulePeriodicRefresh()
    -- Cancel any existing RTC wakeup
    if self.rtc_wakeup_scheduled then
        if self.wakeup_mgr then
            self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
        else
            SystemUtils.cancelRtcWakeup()
        end
        self.rtc_wakeup_scheduled = false
    end

    local interval = SystemUtils.secondsUntilNextMinute(2)

    if self.wakeup_mgr then
        logger.info("DtDisplay: Scheduling RTC-based periodic refresh in", interval, "seconds using WakeupMgr")
        self.wakeup_mgr:addTask(interval, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = true
    else
        logger.info("DtDisplay: Scheduling RTC-based periodic refresh in", interval, "seconds using sysfs fallback")
        if SystemUtils.scheduleRtcWakeup(interval) then
            self.rtc_wakeup_scheduled = true
        else
            logger.warn("DtDisplay: RTC wakeup not available")
        end
    end
end

function DtDisplay:createClockWidget()
    logger.dbg("DtDisplay: Creating clock widget for screensaver")
    local clock_widget = DisplayWidget:new {
        props = self:getEffectiveProps(),
        plugin_dir = PLUGIN_DIR,
        plugin_ref = self,
        is_screensaver = true,  -- Crucial: disables standby/CPU hooks
    }
    return clock_widget
end

function DtDisplay:onSuspend()
    logger.dbg("DtDisplay: Device suspending")
end

function DtDisplay:onResume()
    logger.dbg("DtDisplay: Device resuming")

    -- Check if we woke up due to an RTC alarm
    local is_rtc_wakeup = false
    if Device:isKobo() then
        is_rtc_wakeup = Device.screen_saver_mode == true
    else
        is_rtc_wakeup = self.simulated_wakeup == true
    end

    if is_rtc_wakeup then
        -- Cancel any existing RTC wakeup
        if self.rtc_wakeup_scheduled then
            if self.wakeup_mgr then
                self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
            else
                SystemUtils.cancelRtcWakeup()
            end
            self.rtc_wakeup_scheduled = false
        end

        -- Reset the flag
        self.simulated_wakeup = false
        logger.info("DtDisplay: Woke up from scheduled RTC alarm")

        if Device:isKobo() then
            -- For Kobo, if WakeupMgr is not available, we trigger the refresh callback manually.
            -- If WakeupMgr is available, it triggers it automatically, so we do nothing here.
            if not self.wakeup_mgr then
                UIManager:scheduleIn(0, function()
                    self.rtcRefreshCallback()
                end)
            end
        else
            -- For Kindle, schedule redraw on Kindle UI loop
            UIManager:scheduleIn(0, function()
                local Screensaver = require("ui/screensaver")
                local ss_type = G_reader_settings:readSetting("screensaver_type")
                if Device.screen_saver_mode and ss_type == "dtdisplay" then
                    Screensaver:show()
                end
            end)

            -- Release wake lock after refresh completes; let KOReader suspend naturally
            local wake_dur = (self.settings and self.settings.wake_duration) or 0.5
            UIManager:scheduleIn(wake_dur + 2, function()
                logger.info("DtDisplay: Releasing wake lock after Kindle refresh")
                SystemUtils.turnOffKeepAwake()
            end)
        end
    else
        logger.dbg("DtDisplay: Manual wakeup, not from RTC alarm")
        if not Device.screen_saver_mode and self.original_rotation then
            logger.info("DtDisplay: Restoring original rotation mode on manual resume:", self.original_rotation)
            Screen:setRotationMode(self.original_rotation)
            self.original_rotation = nil
        end
    end
end

function DtDisplay:onCloseWidget()
    -- Cancel RTC wakeup tasks on close
    if self.rtc_wakeup_scheduled and self.wakeup_mgr then
        logger.dbg("DtDisplay: Cancelling RTC periodic refresh on close")
        self.wakeup_mgr:removeTasks(nil, self.rtcRefreshCallback)
        self.rtc_wakeup_scheduled = false
    end

    if self.original_rotation then
        logger.info("DtDisplay: Restoring original rotation mode on plugin close:", self.original_rotation)
        Screen:setRotationMode(self.original_rotation)
        self.original_rotation = nil
    end
end

return DtDisplay