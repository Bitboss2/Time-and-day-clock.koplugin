-- Declarative controls, all hosted by Atelier's fullscreen native canvas.
local C={}
function C.sections(element,units)
    element=element or "time"
    local limit=units=="px" and 2000 or 100
    local unit=units=="px" and "px" or "%"
    local r={
        Disposition={
            {"auto_layout","Automatic layout","bool"},{"gap","Spacing",0,100,5,"px"},
            {"scale","Face scale",40,150,5,"%"},{"rotation","Orientation","choice"},
            {"units","Position units","choice"},
            {element..".x","Horizontal position",-limit,limit,1,unit},{element..".y","Vertical position",-limit,limit,1,unit},
            {element..".z","Layer",0,20,1,""},{element..".visible","Visible","bool"},
        },
        Typographie={
            {element..".font","Font (KOReader name or TTF path)","text"},
            {element..".size",element=="time" and "Time size (%)" or "Element size",8,260,2,""},
            {"outline","Digit outline",0,8,1,"px"},{"format","Time format","choice"},
            {"locale","Language of dates and words","choice"},{"date_format","Date format","choice"},
        },
        Habillage={
            {"night","Light / dark","choice"},{"separator","Separator","choice"},{"border","Frame","choice"},
            {"analog_numerals","Analogue dial numerals","choice"},
            {"hour_width","Hour hand width",1,12,1,"px"},
            {"minute_width","Minute hand width",1,12,1,"px"},
            {"brightness","Frontlight (-1 = keep)",-1,100,1,"%"},
        },
        Informations={
            {"show_date","Date","bool"},{"show_battery","Battery","bool"},{"battery_format","Battery display","choice"},
            {"show_wifi","Wi-Fi state (no connection)","bool"},{"show_memory","Lua memory","bool"},
            {"show_world","Second clock","bool"},{"world_zone","Secondary IANA time zone","text"},
        },
        Images={
            {"image_enabled","Custom background","bool"},{"image_mode","Single image / slideshow","choice"},
            {"image_portrait","Portrait image: PNG path","text"},{"image_landscape","Landscape image: PNG path","text"},
            {"folder_portrait","Portrait folder","text"},{"folder_landscape","Landscape folder","text"},
            {"image_interval","Image duration",1,1440,5,"min"},{"image_invert","Invert the background in dark mode","bool"},
            {"image_full_refresh","Clean the screen on change","bool"},{"per_image","Read image.png.json settings","bool"},
        },
        Veille={
            {"interval","Refresh profile","interval"},{"fast_rtc","Aura 2 fast RTC (experimental)","bool"},
            {"wake_margin","Margin after the display finishes",0.1,5,0.1,"s"},
            {"reuse_suspend","Reuse the Aura 2 suspend preparation","bool"},
            {"full_refresh","Full refresh (0 = off)",0,1440,15,"min"},
            {"low_battery","Stop wake-ups below",0,40,1,"%"},
            {"quiet","Night pause","bool"},
            {"quiet_start","Pause start",0,23,1,"h"},{"quiet_end","Pause end",0,23,1,"h"},
        },
    }
    return r
end
-- Display names of the internal section keys.
C.section_names={Disposition="Layout",Typographie="Typography",Habillage="Finish",Informations="Information",
    Images="Images",["Lisibilité"]="Legibility",Veille="Sleep"}
C.labels={follow="Follow KOReader",light="Light",dark="Dark",["24"]="24-hour",["12"]="12-hour",
    ["0"]="Portrait",["1"]="Landscape →",["2"]="Portrait (inverted)",["3"]="Landscape ←",
    none="None",line="Line",dots="Dots",diamond="Diamond",ornament="Ornament",simple="Simple",double="Double",corner="Corners",
    arabic="Arabic",roman="Roman",both="Icon and %",percent="Percent",icon="Icon",single="Single image",cycle="Slideshow",
    px="Pixels",long="Long date",short="Short date",iso="YYYY-MM-DD",fr="Français",en="English"}
return C
