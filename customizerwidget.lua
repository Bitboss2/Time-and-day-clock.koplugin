-- customizerwidget.lua
-- Fullscreen watchface customizer for DtDisplay on e-ink devices.
-- Uses direct Blitbuffer painting with DPI-scaled sizes.
-- Designed for Kobo Aura 2 (758x1024 @ 212 DPI).

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen         = Device.screen
local UIManager      = require("ui/uimanager")
local TextWidget     = require("ui/widget/textwidget")
local logger         = require("logger")

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"

-- DPI scaling
local function S(n) return math.floor(Screen:scaleBySize(n)) end

local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deep_copy(v) end
    return res
end

-- Draw rounded rectangle (border only)
local function drawRoundedBorder(bb, x, y, w, h, r, thickness, color)
    color = color or Blitbuffer.COLOR_BLACK
    -- Top/bottom edges (inset by radius)
    for t = 0, thickness - 1 do
        bb:paintRect(x + r, y + t, w - 2*r, 1, color)
        bb:paintRect(x + r, y + h - 1 - t, w - 2*r, 1, color)
        bb:paintRect(x + t, y + r, 1, h - 2*r, color)
        bb:paintRect(x + w - 1 - t, y + r, 1, h - 2*r, color)
    end
    -- Corner arcs (simple quarter-circle approximation)
    for i = 0, r - 1 do
        local j = r - math.floor(math.sqrt(r*r - (r-i)*(r-i)) + 0.5)
        for t = 0, math.min(thickness - 1, 1) do
            -- top-left
            bb:paintRect(x + j + t, y + i, 1, 1, color)
            bb:paintRect(x + i, y + j + t, 1, 1, color)
            -- top-right
            bb:paintRect(x + w - 1 - j - t, y + i, 1, 1, color)
            bb:paintRect(x + w - 1 - i, y + j + t, 1, 1, color)
            -- bottom-left
            bb:paintRect(x + j + t, y + h - 1 - i, 1, 1, color)
            bb:paintRect(x + i, y + h - 1 - j - t, 1, 1, color)
            -- bottom-right
            bb:paintRect(x + w - 1 - j - t, y + h - 1 - i, 1, 1, color)
            bb:paintRect(x + w - 1 - i, y + h - 1 - j - t, 1, 1, color)
        end
    end
end

-- Draw filled rounded rectangle
local function fillRoundedRect(bb, x, y, w, h, r, color)
    -- Central rect
    bb:paintRect(x + r, y, w - 2*r, h, color)
    -- Side rects
    bb:paintRect(x, y + r, r, h - 2*r, color)
    bb:paintRect(x + w - r, y + r, r, h - 2*r, color)
    -- Corner fills
    for i = 0, r - 1 do
        local dx = r - math.floor(math.sqrt(r*r - (r-i)*(r-i)) + 0.5)
        bb:paintRect(x + dx, y + i, r - dx, 1, color)
        bb:paintRect(x + w - r, y + i, r - dx, 1, color)
        bb:paintRect(x + dx, y + h - 1 - i, r - dx, 1, color)
        bb:paintRect(x + w - r, y + h - 1 - i, r - dx, 1, color)
    end
end

-- Draw a rounded button with text centered
local function drawRoundedButton(bb, bx, by, bw, bh, text, is_sel, face, radius)
    radius = radius or S(6)
    if is_sel then
        fillRoundedRect(bb, bx, by, bw, bh, radius, Blitbuffer.COLOR_BLACK)
    else
        fillRoundedRect(bb, bx, by, bw, bh, radius, Blitbuffer.COLOR_WHITE)
        drawRoundedBorder(bb, bx, by, bw, bh, radius, 1, Blitbuffer.COLOR_BLACK)
    end
    local tw = TextWidget:new { 
        text = text, 
        face = face, 
        bold = is_sel,
        fgcolor = is_sel and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    }
    local tsz = tw:getSize()
    local tx = bx + math.floor((bw - tsz.w) / 2)
    local ty = by + math.floor((bh - tsz.h) / 2)
    tw:paintTo(bb, tx, ty)
    tw:free()
end

-----------------------------------------------------------------------
local CustomizerWidget = InputContainer:extend {
    plugin_ref = nil,
    on_save = nil,
    temp_settings = nil,
    active_tab = 1,
    time_font_page = 1,
    date_font_page = 1,
    _buttons = {},  -- flat list of {x,y,w,h,callback} for hit testing
}

function CustomizerWidget:init()
    self.temp_settings = deep_copy(self.plugin_ref.settings)
    self.temp_settings.rotation = self.temp_settings.rotation or { follow_koreader = true }
    self.temp_settings.time_widget = self.temp_settings.time_widget or { font_name = "infofont" }
    self.temp_settings.date_widget = self.temp_settings.date_widget or { font_name = "infofont" }
    self.temp_settings.status_widget = self.temp_settings.status_widget or { font_name = "infofont" }

    -- Load font list
    self.fonts = { { name = "Default", filename = "infofont" } }
    local ok_cre, credocument = pcall(require, "document/credocument")
    if ok_cre and credocument then
        local ok_init, cre = pcall(function() return credocument:engineInit() end)
        if ok_init and cre then
            local ok_fl, face_list = pcall(function() return cre.getFontFaces() end)
            if ok_fl and face_list then
                for _, v in ipairs(face_list) do
                    local ok_fn, font_filename = pcall(function()
                        return cre.getFontFaceFilenameAndFaceIndex(v)
                    end)
                    if ok_fn and font_filename then
                        local dup = false
                        for _, f in ipairs(self.fonts) do
                            if f.filename == font_filename then dup = true; break end
                        end
                        if not dup then
                            table.insert(self.fonts, { name = v, filename = font_filename })
                        end
                    end
                end
            end
        end
    end

    self.dimen = Geom:new {
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    -- Panel height increased to S(225) to provide ~3mm padding below the Save/Cancel buttons
    self.panel_h = S(225)

    self:rebuildPreview()

    self.modal = true
    self.covers_fullscreen = true

    self.ges_events = {
        Tap = { GestureRange:new {
            ges = "tap",
            range = Geom:new { x = 0, y = 0, w = self.dimen.w, h = self.dimen.h }
        }}
    }
    if Device:hasKeys() then
        self.key_events = { AnyKeyPressed = { { Device.input.group.Any } } }
    end
end

function CustomizerWidget:rebuildPreview()
    if self.preview_widget then
        pcall(function() self.preview_widget:onCloseWidget() end)
        self.preview_widget = nil
    end
    local ok, DisplayWidget = pcall(require, "displaywidget")
    if not ok then return end
    local ok2, widget = pcall(function()
        return DisplayWidget:new {
            props = self.temp_settings,
            plugin_dir = PLUGIN_DIR,
            plugin_ref = self.plugin_ref,
            is_screensaver = true,
            is_preview = true,
            dimen = Geom:new {
                x = 0, y = 0,
                w = self.dimen.w,
                h = self.dimen.h - self.panel_h,
            }
        }
    end)
    if ok2 and widget then
        pcall(function() widget:update() end)
        self.preview_widget = widget
    end
end

function CustomizerWidget:onClose()
    if self.preview_widget then
        pcall(function() self.preview_widget:onCloseWidget() end)
        self.preview_widget = nil
    end
end

-- Register a button rectangle for hit testing
function CustomizerWidget:addButton(bx, by, bw, bh, callback)
    table.insert(self._buttons, { x = bx, y = by, w = bw, h = bh, cb = callback })
end

function CustomizerWidget:paintTo(bb, x, y)
    local sw = self.dimen.w
    local sh = self.dimen.h
    local panel_y = sh - self.panel_h
    self._buttons = {}

    -- Sizing constants
    local margin = S(10)
    local gap = S(4)
    local btn_h = S(30)
    local tab_h = S(28)
    local radius = S(7)
    local usable_w = sw - 2 * margin
    local tab_face = Font:getFace("infofont", S(14))
    local btn_face = Font:getFace("infofont", S(13))
    local label_face = Font:getFace("infofont", S(12))
    local title_face = Font:getFace("infofont", S(12))
    local action_face = Font:getFace("infofont", S(15))

    -- 1. Draw preview
    if self.preview_widget then
        pcall(function() self.preview_widget:paintTo(bb, x, y) end)
    end

    -- 2. Panel background
    bb:paintRect(x, y + panel_y, sw, self.panel_h, Blitbuffer.COLOR_WHITE)
    -- Thick separator line at top
    bb:paintRect(x, y + panel_y, sw, S(2), Blitbuffer.COLOR_BLACK)

    -- 3. Title bar
    local title_tw = TextWidget:new { text = "Customize Clock", face = title_face, bold = true }
    local tsz = title_tw:getSize()
    title_tw:paintTo(bb, x + math.floor((sw - tsz.w)/2), y + panel_y + S(6))
    title_tw:free()
    -- Thin line under title
    bb:paintRect(x + margin, y + panel_y + S(6) + tsz.h + S(4), usable_w, 1, Blitbuffer.COLOR_GRAY)

    -- 4. Tab row
    local tab_y_pos = panel_y + S(6) + tsz.h + S(10)
    local tabs = { "Style", "Format", "Fonts", "Theme", "Deco" }
    local tab_w = math.floor((usable_w - (#tabs - 1) * gap) / #tabs)
    for i, name in ipairs(tabs) do
        local tx = margin + (i-1) * (tab_w + gap)
        local is_active = (self.active_tab == i)
        drawRoundedButton(bb, x + tx, y + tab_y_pos, tab_w, tab_h, name, is_active, tab_face, S(5))
        local tab_i = i
        self:addButton(x + tx, y + tab_y_pos, tab_w, tab_h, function()
            self.active_tab = tab_i
            UIManager:setDirty(self, "ui")
        end)
    end

    -- 5. Content area
    local row1_y = tab_y_pos + tab_h + S(12)
    local row2_y = row1_y + btn_h + S(10)
    local label_w = S(48)
    local content_x = margin + label_w + S(6)
    local content_w = usable_w - label_w - S(6)

    if self.active_tab == 1 then
        -- Style
        self:drawLabeledRow(bb, x, y, margin, row1_y, "Style", label_face)
        local styles = { { "Classic", "classic" }, { "Full", "fullscreen" }, { "Analog", "analog" }, { "Outline", "outlined" }, { "Word", "wordclock" } }
        local sbw = math.floor((content_w - (#styles-1)*gap) / #styles)
        for i, s in ipairs(styles) do
            local bx = content_x + (i-1)*(sbw+gap)
            local sel = (self.temp_settings.clock_style == s[2])
            drawRoundedButton(bb, x+bx, y+row1_y, sbw, btn_h, s[1], sel, btn_face, radius)
            local val = s[2]
            self:addButton(x+bx, y+row1_y, sbw, btn_h, function()
                self.temp_settings.clock_style = val; self:applyAndRefresh()
            end)
        end
        -- Size
        self:drawLabeledRow(bb, x, y, margin, row2_y, "Size", label_face)
        local sizes = { { "Small", "small" }, { "Med", "medium" }, { "Big", "big" }, { "Huge", "huge" } }
        local zbw = math.floor((content_w - (#sizes-1)*gap) / #sizes)
        for i, s in ipairs(sizes) do
            local bx = content_x + (i-1)*(zbw+gap)
            local sel = (self.temp_settings.text_size == s[2])
            drawRoundedButton(bb, x+bx, y+row2_y, zbw, btn_h, s[1], sel, btn_face, radius)
            local val = s[2]
            self:addButton(x+bx, y+row2_y, zbw, btn_h, function()
                self.temp_settings.text_size = val; self:applyAndRefresh()
            end)
        end

    elseif self.active_tab == 2 then
        -- Format
        self:drawLabeledRow(bb, x, y, margin, row1_y, "Fmt", label_face)
        local fmts = { { "24h", "24" }, { "12h", "12" }, { "Auto", "follow" } }
        local fbw = math.floor((content_w - 2*gap) / 3)
        for i, f in ipairs(fmts) do
            local bx = content_x + (i-1)*(fbw+gap)
            local sel = (self.temp_settings.clock_format == f[2])
            drawRoundedButton(bb, x+bx, y+row1_y, fbw, btn_h, f[1], sel, btn_face, radius)
            local val = f[2]
            self:addButton(x+bx, y+row1_y, fbw, btn_h, function()
                self.temp_settings.clock_format = val; self:applyAndRefresh()
            end)
        end
        -- Info label for rotation
        self:drawLabeledRow(bb, x, y, margin, row2_y, "Rot", label_face)
        local note_tw = TextWidget:new { text = "Use main menu", face = btn_face, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        local note_sz = note_tw:getSize()
        note_tw:paintTo(bb, x + content_x, y + row2_y + math.floor((btn_h - note_sz.h) / 2))
        note_tw:free()

    elseif self.active_tab == 3 then
        -- Fonts (paginated, 3 per page)
        local per_page = 3
        local nf = #self.fonts
        local max_pg = math.max(1, math.ceil(nf / per_page))
        local arrow_w = S(30)
        local font_area_w = content_w - 2*(arrow_w + gap)
        local font_btn_w = math.floor((font_area_w - (per_page-1)*gap) / per_page)
        local font_x_start = content_x + arrow_w + gap

        -- Time font row
        self:drawLabeledRow(bb, x, y, margin, row1_y, "Time", label_face)
        -- Left arrow
        drawRoundedButton(bb, x+content_x, y+row1_y, arrow_w, btn_h, "<", false, btn_face, S(4))
        self:addButton(x+content_x, y+row1_y, arrow_w, btn_h, function()
            self.time_font_page = math.max(1, self.time_font_page - 1)
            UIManager:setDirty(self, "ui")
        end)
        -- Font buttons
        local ts = (self.time_font_page - 1) * per_page + 1
        for i = 0, per_page - 1 do
            local fi = ts + i
            if fi <= nf then
                local bx = font_x_start + i*(font_btn_w+gap)
                local f = self.fonts[fi]
                local sel = (self.temp_settings.time_widget.font_name == f.filename)
                -- Truncate name to fit
                local dname = #f.name > 8 and f.name:sub(1,7).."…" or f.name
                drawRoundedButton(bb, x+bx, y+row1_y, font_btn_w, btn_h, dname, sel, btn_face, radius)
                local fname = f.filename
                self:addButton(x+bx, y+row1_y, font_btn_w, btn_h, function()
                    self.temp_settings.time_widget.font_name = fname; self:applyAndRefresh()
                end)
            end
        end
        -- Right arrow
        local rarr_x = font_x_start + per_page*(font_btn_w+gap)
        drawRoundedButton(bb, x+rarr_x, y+row1_y, arrow_w, btn_h, ">", false, btn_face, S(4))
        self:addButton(x+rarr_x, y+row1_y, arrow_w, btn_h, function()
            self.time_font_page = math.min(max_pg, self.time_font_page + 1)
            UIManager:setDirty(self, "ui")
        end)

        -- Date font row
        self:drawLabeledRow(bb, x, y, margin, row2_y, "Date", label_face)
        drawRoundedButton(bb, x+content_x, y+row2_y, arrow_w, btn_h, "<", false, btn_face, S(4))
        self:addButton(x+content_x, y+row2_y, arrow_w, btn_h, function()
            self.date_font_page = math.max(1, self.date_font_page - 1)
            UIManager:setDirty(self, "ui")
        end)
        local ds = (self.date_font_page - 1) * per_page + 1
        for i = 0, per_page - 1 do
            local fi = ds + i
            if fi <= nf then
                local bx = font_x_start + i*(font_btn_w+gap)
                local f = self.fonts[fi]
                local sel = (self.temp_settings.date_widget.font_name == f.filename)
                local dname = #f.name > 8 and f.name:sub(1,7).."…" or f.name
                drawRoundedButton(bb, x+bx, y+row2_y, font_btn_w, btn_h, dname, sel, btn_face, radius)
                local fname = f.filename
                self:addButton(x+bx, y+row2_y, font_btn_w, btn_h, function()
                    self.temp_settings.date_widget.font_name = fname; self:applyAndRefresh()
                end)
            end
        end
        drawRoundedButton(bb, x+rarr_x, y+row2_y, arrow_w, btn_h, ">", false, btn_face, S(4))
        self:addButton(x+rarr_x, y+row2_y, arrow_w, btn_h, function()
            self.date_font_page = math.min(max_pg, self.date_font_page + 1)
            UIManager:setDirty(self, "ui")
        end)

    elseif self.active_tab == 4 then
        -- Theme
        self:drawLabeledRow(bb, x, y, margin, row1_y, "Mode", label_face)
        local themes = { { "Day", "day" }, { "Night", "night" }, { "Auto", "follow" } }
        local tbw = math.floor((content_w - 2*gap) / 3)
        for i, t in ipairs(themes) do
            local bx = content_x + (i-1)*(tbw+gap)
            local sel = (self.temp_settings.night_mode == t[2])
            drawRoundedButton(bb, x+bx, y+row1_y, tbw, btn_h, t[1], sel, btn_face, radius)
            local val = t[2]
            self:addButton(x+bx, y+row1_y, tbw, btn_h, function()
                self.temp_settings.night_mode = val; self:applyAndRefresh()
            end)
        end
        -- Auto-Layout
        self:drawLabeledRow(bb, x, y, margin, row2_y, "Layout", label_face)
        local auto_on = (self.temp_settings.auto_layout_enabled ~= false)
        local abw = math.floor((content_w - gap) / 2)
        drawRoundedButton(bb, x+content_x, y+row2_y, abw, btn_h, "Auto", auto_on, btn_face, radius)
        self:addButton(x+content_x, y+row2_y, abw, btn_h, function()
            self.temp_settings.auto_layout_enabled = true; self:applyAndRefresh()
        end)
        drawRoundedButton(bb, x+content_x+abw+gap, y+row2_y, abw, btn_h, "Manual", not auto_on, btn_face, radius)
        self:addButton(x+content_x+abw+gap, y+row2_y, abw, btn_h, function()
            self.temp_settings.auto_layout_enabled = false; self:applyAndRefresh()
        end)

    elseif self.active_tab == 5 then
        -- Separator
        self:drawLabeledRow(bb, x, y, margin, row1_y, "Sep", label_face)
        local seps = { { "Line", "line" }, { "Dots", "dots" }, { "Diam", "diamond" }, { "Orn", "ornament" }, { "Off", "none" } }
        local sbw = math.floor((content_w - (#seps-1)*gap) / #seps)
        for i, s in ipairs(seps) do
            local bx = content_x + (i-1)*(sbw+gap)
            local sel = (self.temp_settings.separator_style == s[2])
            drawRoundedButton(bb, x+bx, y+row1_y, sbw, btn_h, s[1], sel, btn_face, radius)
            local val = s[2]
            self:addButton(x+bx, y+row1_y, sbw, btn_h, function()
                self.temp_settings.separator_style = val; self:applyAndRefresh()
            end)
        end
        -- Border
        self:drawLabeledRow(bb, x, y, margin, row2_y, "Frame", label_face)
        local bords = { { "Simple", "simple" }, { "Double", "double" }, { "Corner", "corner" }, { "Off", "none" } }
        local bbw = math.floor((content_w - (#bords-1)*gap) / #bords)
        for i, b in ipairs(bords) do
            local bx = content_x + (i-1)*(bbw+gap)
            local sel = (self.temp_settings.border_frame_style == b[2])
            drawRoundedButton(bb, x+bx, y+row2_y, bbw, btn_h, b[1], sel, btn_face, radius)
            local val = b[2]
            self:addButton(x+bx, y+row2_y, bbw, btn_h, function()
                self.temp_settings.border_frame_style = val; self:applyAndRefresh()
            end)
        end
    end

    -- 6. Action buttons at bottom
    local act_y = row2_y + btn_h + S(14)
    local act_h = S(34)
    local act_w = math.floor((usable_w - S(10)) / 2)
    drawRoundedButton(bb, x+margin, y+act_y, act_w, act_h, "Cancel", false, action_face, S(10))
    self:addButton(x+margin, y+act_y, act_w, act_h, function()
        UIManager:close(self)
    end)
    drawRoundedButton(bb, x+margin+act_w+S(10), y+act_y, act_w, act_h, "Save", true, action_face, S(10))
    self:addButton(x+margin+act_w+S(10), y+act_y, act_w, act_h, function()
        for k, v in pairs(self.temp_settings) do
            self.plugin_ref.settings[k] = v
        end
        self.plugin_ref.local_storage:reset(self.plugin_ref.settings)
        self.plugin_ref.local_storage:flush()
        if self.on_save then self.on_save() end
        UIManager:close(self)
    end)

    -- 7. Night mode inversion
    local is_dark = false
    local mode = self.temp_settings.night_mode
    if mode == "night" then is_dark = true
    elseif mode == "follow" then is_dark = G_reader_settings:isTrue("night_mode") end
    if is_dark ~= G_reader_settings:isTrue("night_mode") then
        bb:invertRect(x, y, sw, sh)
    end
end

function CustomizerWidget:drawLabeledRow(bb, x, y, margin, row_y, text, face)
    local tw = TextWidget:new { text = text, face = face, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    local tsz = tw:getSize()
    tw:paintTo(bb, x + margin, y + row_y + math.floor((S(28) - tsz.h) / 2))
    tw:free()
end

function CustomizerWidget:applyAndRefresh()
    self:rebuildPreview()
    UIManager:setDirty(self, "ui")
end

function CustomizerWidget:onTap(_, ges)
    local tx, ty = ges.pos.x, ges.pos.y
    for _, btn in ipairs(self._buttons) do
        if tx >= btn.x and tx <= btn.x + btn.w and ty >= btn.y and ty <= btn.y + btn.h then
            btn.cb()
            return true
        end
    end
    return true
end

function CustomizerWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

return CustomizerWidget
