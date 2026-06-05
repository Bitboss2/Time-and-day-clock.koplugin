-- advanced_settings.lua
-- Place this file in the DtDisplay plugin folder.
-- When "Advanced settings" is enabled in the menu, values set here take
-- priority over the UI. Set any field to nil (or omit it) to keep the UI value.

return {
    -- WIDGETS --
    time_widget = {
        font_size = nil,  -- e.g. 150 (overrides the UI font size slider)
        font_name = nil,  -- e.g. "./fonts/noto/NotoSans-Bold.ttf"
    },
    date_widget = {
        font_size = nil,
        font_name = nil,
    },
    status_widget = {
        font_size = nil,
        font_name = nil,
    },

    -- CLOCK ORIENTATION --
    -- To use a custom rotation, set follow_koreader = false AND set custom_rotation.
    -- custom_rotation values: 0 = portrait, 1 = landscape CW, 2 = portrait inverted, 3 = landscape CCW
    rotation = {
        follow_koreader = true,   -- true or false
        custom_rotation = 3,   -- 0, 1, 2, or 3
    },

    -- CPU WAKE DURATION --
    -- How long the CPU stays awake after refreshing the clock display (seconds).
    -- After this delay, the wake lock is released and KOReader's AutoSuspend
    -- puts the device back to sleep. Increase if the screen doesn't update
    -- properly on your device. Range: 0.1 - 5.0, default: 0.5
    wake_duration = nil,

    png_overlay = {
        enabled                  = true,  -- true or false
        mode                     = nil,  -- "single" or "cycle"
        
        -- Single mode paths (portrait and landscape)
        single_file_path_portrait  = nil,  -- e.g. "/mnt/us/covers/my_cover.png"
        single_file_path_landscape = nil,
        single_file_path           = nil,  -- legacy fallback used if portrait/landscape are empty

        -- Cycle mode folder paths
        portrait_folder_path   = nil,  -- folder containing PNGs for portrait
        landscape_folder_path  = nil,
        folder_path            = nil,  -- legacy fallback

        cycle_minutes          = nil,  -- how often to cycle to the next image
        full_refresh_on_cycle  = nil,  -- true = full e-ink refresh on each cycle
        invert_with_night_mode = nil,  -- false = keep PNG uninverted when night mode is on
    },
    -- INDIVIDUAL STATUS WIDGETS --
    -- Leave values as nil to inherit from status_widget
    
    battery_widget = {
        font_size = 50,             -- e.g., slightly larger than the rest
        font_name = nil,            -- e.g., "./fonts/noto/NotoSans-Bold.ttf"
        format    = "icon",      -- Options: "percent", "icon", or "both"
    },
    
    wifi_widget = {
        font_size = 20,             -- e.g., smaller
        font_name = nil,
    },
    
    memory_widget = {
        font_size = 20,
        font_name = nil,
    },

    -- WIDGET BRIGHTNESS --
    -- Set to -1 to disable (use device default), or 0–24 (device max may vary)
    widget_brightness = -1,

    -- FULL REFRESH INTERVAL --
    -- Number of minutes between full e-ink refreshes. Set to 0 to disable.
    full_refresh_minutes = nil,

    -- CLOCK & DISPLAY --
    clock_format = nil,  -- "24", "12", or "follow"
    night_mode   = "normal",  -- "night", "normal", or "follow"

    -- TEXT SIZE --
    -- Controls font sizes for time, date, and status widgets.
    -- "small", "medium" (default), "big", "huge"
    -- Does NOT apply to fullscreen (auto-calculated) or analog (drawn).
    text_size = nil,

    -- CLOCK STYLE --
    -- "classic"    = standard digital clock (default)
    -- "fullscreen" = giant digits that fill the screen width (no other widgets)
    -- "analog"     = analog clock face with hour/minute hands
    -- "outlined"   = digital text with thick outline (great over images)
    -- "wordclock"  = time spelled out in French words
    clock_style = nil,

    -- ANALOG CLOCK OPTIONS --
    -- Only used when clock_style = "analog"
    analog_opts = {
        numerals        = nil,  -- "arabic", "roman", or "none"
        hand_width_hour = nil,  -- pixels (default: 6)
        hand_width_min  = nil,  -- pixels (default: 4)
    },

    -- ANALOG INFO BAR --
    -- Which mini-infos to show at the bottom of the analog clock.
    -- Available: "date", "battery", "memory", "worldclock_nyc"
    analog_infos = nil,  -- table, e.g. {"battery", "date"}

    -- OUTLINED STYLE --
    -- Only used when clock_style = "outlined"
    outline_width = nil,  -- pixels (default: 3, range: 1-8)

    -- AUTO-LAYOUT --
    -- Automatically stacks widgets vertically to prevent overlap when
    -- font sizes are changed. Set to false to use manual positioning
    -- from elements.lua instead.
    auto_layout_enabled = nil,  -- true (default) or false
    auto_layout_gap     = nil,  -- spacing in pixels between elements (default: 20)


    -- DECORATIONS --
    -- Separator drawn between time and date elements
    -- Only drawn when there is enough space (>=12px) to avoid overlap
    -- "none", "line", "dots", "diamond", "ornament"
    separator_style = nil,

    -- Decorative border frame around the screen
    -- "none", "simple", "double", "corner"
    border_frame_style = nil,

}
