local load = ...
local U = load("core/util")
local S = {}
S.defaults = {
    schema_version = 1, face = "totem", favorites = {}, ui_scale=100, collection={}, active_id="",
    format = "follow", night = "follow", rotation = "follow", locale = "en",
    auto_layout = true, gap = 20, scale = 100, outline = 0,
    separator = "none", border = "none", analog_numerals = "arabic", hour_width = 6, minute_width = 4,
    show_date = true, show_battery = true, show_wifi = false, show_memory = false, show_world = false,
    battery_format = "both", world_zone = "America/New_York", date_format = "long",
    interval = 60, full_refresh = 60, wake_margin = 0.3, fast_rtc = false, reuse_suspend=true,
    low_battery = 10, quiet = false, quiet_start = 23, quiet_end = 7,
    brightness = -1, image_enabled = false, image_mode = "single", image_interval = 60,
    image_portrait = "", image_landscape = "", folder_portrait = "", folder_landscape = "",
    image_invert = true, image_full_refresh = true, per_image = false,
    time = {font="cfont",size=100,x=0,y=0,z=5,visible=true},
    date = {font="cfont",size=24,x=0,y=0,z=6,visible=true},
    battery = {font="cfont",size=20,x=0,y=0,z=7,visible=true},
    wifi = {font="cfont",size=18,x=0,y=0,z=8,visible=true},
    memory = {font="cfont",size=18,x=0,y=0,z=9,visible=true},
    world = {font="cfont",size=22,x=0,y=0,z=10,visible=true},
    units = "percent",
    display_engine = "auto", display_fps = 30, display_rest = true, motion = "full",
}
S.choices = {
    format={"follow","24","12"}, night={"follow","light","dark"}, rotation={"follow","0","1","2","3"},
    separator={"none","line","dots","diamond","ornament"},border={"none","simple","double","corner"},
    analog_numerals={"arabic","roman","none"},battery_format={"both","percent","icon"},
    image_mode={"single","cycle"},units={"percent","px"},date_format={"long","short","iso"},locale={"fr","en"},
    display_engine={"auto","fluid","classic"},motion={"full","reduced"},
}
S.bounds = {
    ui_scale={85,140},gap={0,100},scale={40,150},outline={0,8},hour_width={1,12},minute_width={1,12},
    interval={0,900},full_refresh={0,1440},wake_margin={0.1,5},low_battery={0,40},
    quiet_start={0,23},quiet_end={0,23},brightness={-1,100},image_interval={1,1440},display_fps={30,60},
}
local function merge(target, source, defaults)
    for k, d in pairs(defaults) do
        local v = source[k]
        if type(d) == "table" then
            target[k] = U.copy(d)
            if k == "collection" then
                -- Variable-length records are validated below, never merged as defaults.
            elseif k == "favorites" and type(v) == "table" then
                for id, yes in pairs(v) do if type(id)=="string" and #id<80 and yes==true then target[k][id]=true end end
            elseif type(v)=="table" then merge(target[k],v,d) end
        elseif type(v) == type(d) then target[k] = v end
    end
end
function S.validate(data)
    assert(type(data)=="table", "Invalid settings")
    assert(data.schema_version == nil or data.schema_version == 1, "Unknown settings version")
    local r = U.copy(S.defaults); merge(r, data, S.defaults)
    for k, values in pairs(S.choices) do
        local ok=false; for _,v in ipairs(values) do if r[k]==v then ok=true end end
        if not ok then r[k]=S.defaults[k] end
    end
    for k, bound in pairs(S.bounds) do
        if r[k] ~= r[k] or r[k] == math.huge or r[k] == -math.huge then r[k] = S.defaults[k] end
        r[k]=U.clamp(r[k],bound[1],bound[2])
    end
    if r.display_fps~=30 and r.display_fps~=45 and r.display_fps~=60 then r.display_fps=30 end
    if r.interval~=0 and r.interval~=60 and r.interval~=300 and r.interval~=600 and r.interval~=900 then r.interval=60 end
    for _,k in ipairs({"time","date","battery","wifi","memory","world"}) do
        local e=r[k]
        for _,n in ipairs({"size","x","y","z"}) do if e[n]~=e[n] or math.abs(e[n])==math.huge then e[n]=S.defaults[k][n] end end
        e.size=U.clamp(e.size,8,260);e.x=U.clamp(e.x,-2000,2000);e.y=U.clamp(e.y,-2000,2000);e.z=U.clamp(e.z,0,20)
        if #e.font>512 then e.font="cfont" end
    end
    for k,v in pairs(r) do if type(v)=="string" and #v>1024 then r[k]=S.defaults[k] end end
    local C=load("core/collection");local ids={}
    for i,item in ipairs(type(data.collection)=="table" and data.collection or {})do
        if i>24 then break end
        if type(item)=="table" and type(item.uid)=="string" and item.uid:match("^[a-zA-Z0-9_-]+$") and #item.uid<=40
            and not ids[item.uid] and type(item.face)=="string" and #item.face<=64 and item.face:match("^[a-z][a-z0-9_-]+$")then
            local v={uid=item.uid,face=item.face,title=type(item.title)=="string" and item.title:sub(1,80) or item.face,
                style=item.style=="contour" and "contour" or item.style=="fin" and "fin" or "plein",
                appearance=item.appearance=="paper" and "paper" or item.appearance=="ink" and "ink" or "follow",slots={}}
            for id,slot in pairs(type(item.slots)=="table" and item.slots or {})do
                if type(id)=="string" and #id<=40 and id:match("^[a-zA-Z0-9_-]+$") and type(slot)=="table" then
                    local good=false;for _,provider in ipairs(C.providers)do if provider==slot.provider then good=true end end
                    local zone="UTC";for _,z in ipairs(C.zones)do if z==slot.zone then zone=z end end
                    if good then v.slots[id]={provider=slot.provider,zone=zone}end
                end
            end
            r.collection[#r.collection+1]=v;ids[v.uid]=true
        end
    end
    r.schema_version=1;return r
end
function S.new(path)
    local self = setmetatable({path=path}, {__index=S})
    self.data=U.copy(S.defaults)
    local b=U.read(path,131072)
    if b then
        local ok, data=pcall(require("json").decode,b)
        if ok then local valid, r=pcall(S.validate,data);if valid then self.data=r else self.warning=tostring(r) end
        else self.warning="Unreadable settings; fallback values loaded." end
    end
    return self
end
function S:save(data)
    local ok,r=pcall(S.validate,data);if not ok then return nil,tostring(r) end
    local encoded=require("json").encode(r)
    local written,err=U.write(self.path..".tmp",encoded);if not written then return nil,err end
    local renamed,re=os.rename(self.path..".tmp",self.path);if not renamed then return nil,re end
    self.data=r;return true
end
return S
