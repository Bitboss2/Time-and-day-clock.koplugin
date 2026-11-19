-- Parser for a *data-only* subset of Lua table syntax. Never calls load/dofile.
local load=...
local U=load("core/util")
local L={}
function L.parse(source)
    assert(type(source)=="string" and #source<=131072,"Configuration trop volumineuse")
    local p=1
    local function skip()
        while true do
            local _,e=source:find("^%s+",p)
            if e then p=e+1 end
            if source:sub(p,p+1)=="--" then
                assert(source:sub(p+2,p+3)~="[[","Commentaires longs non pris en charge")
                local n=source:find("\n",p+2,true);p=n and n+1 or #source+1
            else return end
        end
    end
    local function literal_string()
        local quote=source:sub(p,p);p=p+1;local out={}
        while p<=#source do
            local c=source:sub(p,p);p=p+1
            if c==quote then return table.concat(out) end
            if c=="\\" then
                c=source:sub(p,p);p=p+1
                local escapes={n="\n",r="\r",t="\t",['\\']='\\',["'"]="'",['"']='"'}
                assert(escapes[c],"Échappement Lua non pris en charge")
                c=escapes[c]
            end
            out[#out+1]=c
        end
        error("Chaîne non terminée")
    end
    local value
    value=function(depth)
        assert(depth<=20,"Table trop profonde");skip();local c=source:sub(p,p)
        if c=='"' or c=="'" then return literal_string() end
        if c=="{" then
            p=p+1;local t={};local index=1
            while true do
                skip();if source:sub(p,p)=="}" then p=p+1;return t end
                local key,v
                if source:sub(p,p)=="[" then
                    p=p+1;key=value(depth+1);skip();assert(source:sub(p,p)=="]","Clé invalide");p=p+1;skip()
                    assert(source:sub(p,p)=="=","Affectation attendue");p=p+1;v=value(depth+1)
                else
                    local save=p;local id=source:match("^([%a_][%w_]*)",p)
                    if id then p=p+#id;skip() end
                    if id and source:sub(p,p)=="=" then key=id;p=p+1;v=value(depth+1)
                    else p=save;key=index;index=index+1;v=value(depth+1) end
                end
                assert(type(key)=="string" or type(key)=="number","Clé interdite")
                t[key]=v;skip();local sep=source:sub(p,p)
                if sep=="," or sep==";" then p=p+1 else assert(sep=="}","Séparateur attendu") end
            end
        end
        local number=source:match("^([+-]?%d+%.?%d*)",p)
        if number then p=p+#number;return assert(tonumber(number)) end
        for _,word in ipairs({"true","false","nil"}) do
            if source:sub(p,p+#word-1)==word and not source:sub(p+#word,p+#word):match("[%w_]") then
                p=p+#word;if word=="nil" then return nil end;return word=="true"
            end
        end
        error("Expression Lua refusée à la position "..p)
    end
    skip();if source:sub(p,p+5)=="return" then p=p+6 end
    local t=value(0);skip();assert(p>#source,"Code après la table refusé");assert(type(t)=="table","Table attendue")
    return t
end
function L.convert(old,base)
    local r=U.copy(base);local report={}
    local map={clock_format="format",night_mode="night",auto_layout_enabled="auto_layout",auto_layout_gap="gap",outline_width="outline",
        separator_style="separator",border_frame_style="border",widget_brightness="brightness",full_refresh_minutes="full_refresh",wake_duration="wake_margin"}
    for from,to in pairs(map) do if old[from]~=nil then r[to]=old[from] end end
    if r.night=="normal" then r.night="light" elseif r.night=="night" then r.night="dark" end
    if old.rotation then r.rotation=old.rotation.follow_koreader and "follow" or tostring(old.rotation.custom_rotation or 0) end
    for _,kind in ipairs({"time","date","status","battery","wifi","memory"}) do
        local e=old[kind.."_widget"]
        if e and kind~="status" then
            if e.font_name then r[kind].font=e.font_name end
            if e.font_size then r[kind].size=e.font_size end
        end
    end
    if old.status_widget then
        for _,kind in ipairs({"battery","wifi","memory"}) do
            if old.status_widget.font_name and not old[kind.."_widget"] then r[kind].font=old.status_widget.font_name end
            if old.status_widget.font_size and not old[kind.."_widget"] then r[kind].size=old.status_widget.font_size end
        end
    end
    if old.battery_widget and old.battery_widget.format then r.battery_format=old.battery_widget.format end
    local o=old.png_overlay
    if o then
        local images={enabled="image_enabled",mode="image_mode",single_file_path_portrait="image_portrait",single_file_path_landscape="image_landscape",
            portrait_folder_path="folder_portrait",landscape_folder_path="folder_landscape",cycle_minutes="image_interval",
            full_refresh_on_cycle="image_full_refresh",invert_with_night_mode="image_invert",use_image_config="per_image"}
        for from,to in pairs(images) do if o[from]~=nil then r[to]=o[from] end end
        for _,suffix in ipairs({"portrait","landscape"}) do
            if r["image_"..suffix]=="" then r["image_"..suffix]=o.single_file_path or "" end
            if r["folder_"..suffix]=="" then r["folder_"..suffix]=o.folder_path or "" end
        end
    end
    if old.analog_opts then
        r.analog_numerals=old.analog_opts.numerals or r.analog_numerals
        r.hour_width=old.analog_opts.hand_width_hour or r.hour_width;r.minute_width=old.analog_opts.hand_width_min or r.minute_width
    end
    if old.analog_infos then
        r.show_date=false;r.show_battery=false;r.show_memory=false;r.show_world=false
        for _,name in ipairs(old.analog_infos) do
            if name=="worldclock_nyc" then r.show_world=true;r.world_zone="America/New_York" else r["show_"..name]=true end
        end
    end
    local elements=old.elements or old
    for _,kind in ipairs({"time","date","battery","wifi","memory"}) do
        local e=elements[kind]
        if type(e)=="table" then
            for _,key in ipairs({"x","y","z","visible"}) do if e[key]~=nil then r[kind][key]=e[key] end end
            if e.unit then r.units=e.unit=="%" and "percent" or "px" end
        end
    end
    if old.clock_style then report[#report+1]="Ancien cadran remplacé par la collection Atelier." end
    if old.text_size then
        local sizes={small=75,medium=100,big=120,huge=145};r.scale=sizes[old.text_size] or r.scale
    end
    report[#report+1]="Positions anciennes importées comme décalages : vérifier l'aperçu. Les scripts par image ne sont pas exécutés."
    return load("core/settings").validate(r),table.concat(report," ")
end
return L
