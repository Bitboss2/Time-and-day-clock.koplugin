-- Offline IANA transitions generated at build time, never changes process TZ.
local W={}
function W.new(root)
    local f=io.open(root.."/resources/timezones.json","rb")
    local self=setmetatable({}, {__index=W})
    if f then local s=f:read("*a");f:close();local ok,v=pcall(require("json").decode,s);if ok then self.data=v end end
    return self
end
function W:format(epoch,zone)
    if zone=="UTC" then return os.date("!%H:%M",epoch),"UTC" end
    local data=self.data;local z=data and data.zones[zone]
    if not z or epoch<data.start or epoch>=data.finish then return "--:--","Fuseau indisponible" end
    local offset=z[1][2]
    for _,row in ipairs(z) do if row[1]>epoch then break end;offset=row[2] end
    return os.date("!%H:%M",epoch+offset),zone:match("[^/]+$"):gsub("_"," ")
end
return W
