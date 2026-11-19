local load=...
local U=load("core/util")
local C={}
C.providers={"none","date","battery","day","week","world","book"}
C.names={none="Empty",date="Date",battery="Battery",day="Day",week="Week",world="World clock",book="Reading"}
C.zones={"UTC","Europe/Paris","Europe/London","America/New_York","Asia/Tokyo"}
function C.current(s)
    for _,v in ipairs(s.collection or {})do if v.uid==s.active_id and v.face==s.face then return v end end
end
function C.options(s,face)
    local item=C.current(s)
    if item and item.face==face.id then return item end
    return {face=face.id,style="plein",appearance="follow",slots={}}
end
function C.select(s,item) s.active_id=item.uid;s.face=item.face end
function C.add(s,face,copy)
    if #s.collection>=24 then return nil,"The collection is limited to 24 faces."end
    local used={};for _,v in ipairs(s.collection)do used[v.uid]=true end
    local n=1;while used["c"..n]do n=n+1 end
    local item=copy and U.copy(copy)or {face=face.id,title=face.name,style="plein",appearance="follow",slots={}}
    if not copy and face.preset then
        item.style=face.preset.style;item.appearance=face.preset.appearance;item.slots=U.copy(face.preset.slots)
    end
    item.uid="c"..n;s.collection[#s.collection+1]=item;C.select(s,item);return item
end
function C.slot(item,face,id)
    local spec
    for _,v in ipairs(face.slots or {})do if v.id==id then spec=v;break end end
    if not spec then return {provider="none",zone="UTC"}end
    return item.slots and item.slots[id]or {provider=spec.default,zone="America/New_York"}
end
function C.allowed(spec,provider)
    for _,v in ipairs(spec.allowed or C.providers)do if v==provider then return true end end
    return false
end
return C
