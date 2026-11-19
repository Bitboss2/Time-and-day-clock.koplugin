-- Read-only kernel-ring snapshots. Action 3 is READ_ALL, never READ_CLEAR.
-- At most 16 KiB; session entry, first three short returns and explicit export.
local load=...
local U=load("core/util")
local E={limit=16384}
function E.identity(device)
    if not device:isKobo()then return {available=false,reason="not_kobo"}end
    return {kernel=U.read("/proc/version",4096),cpu=U.read("/proc/cpuinfo",16384),
        framebuffer=U.read("/sys/class/graphics/fb0/name",256),
        governor=U.read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",256)}
end
function E.capture(device)
    if not device:isKobo()then return {available=false,reason="not_kobo"}end
    local good,result=pcall(function()
        local ffi=require("ffi")
        ffi.cdef[[int klogctl(int type, char *bufp, int len);]]
        local buffer=ffi.new("char[?]",E.limit)
        local count=ffi.C.klogctl(3,buffer,E.limit)
        if count<0 then return {available=false,errno=ffi.errno(),reason="kernel_log_unavailable"}end
        return {available=true,text=ffi.string(buffer,count),bytes=count,at=os.time()}
    end)
    return good and result or {available=false,reason="kernel_log_api_unavailable"}
end
function E.since(before,after)
    if not after or not after.available then return after end
    local a,b=before and before.available and before.text,after.text
    if not a or a==""then return {available=true,text=b,delta_verified=false}end
    if b:sub(1,#a)==a then return {available=true,text=b:sub(#a+1),delta_verified=true}end
    local tail=a:sub(-512);local from=1
    while #tail>=512 do
        local at=b:find(tail,from,true);if not at then break end
        local size=at+#tail-1
        if size<=#a and b:sub(1,size)==a:sub(-size)then
            return {available=true,text=b:sub(size+1),delta_verified=true}
        end
        from=at+1
    end
    return {available=true,text=b,delta_verified=false,reason="ring_overlap_not_found"}
end
return E
