-- RTC wake-up capability per reader, from KOReader's own device classes:
--   Kobo   : hardware RTC through WakeupMgr (frontend/device/kobo/device.lua),
--            suspension driven by KOReader (rescheduleSuspend/suspend).
--   Kindle : WakeupMgr backed by device/kindle/mockrtc (powerd/lipc), created
--            only when KOReader owns the screensaver; powerd itself suspends.
--   others : no WakeupMgr → the clock is drawn once (static) and says so.
local C={}
function C.detect(device)
    local mgr=device and device.wakeup_mgr
    local model=device and device.model or "?"
    local function is(name)local f=device and device[name];if type(f)~="function"then return false end
        local ok,v=pcall(f,device);return ok and v==true end
    if not mgr or type(mgr.addTask)~="function"then
        return {kind="none",model=model,available=false,label="Unavailable",
            detail="No programmable wake-up: the clock stays fixed while asleep."}
    end
    if is("isKobo")then
        return {kind="kobo",model=model,available=true,label="Hardware RTC",native_suspend=true,
            precise=true,detail="Kobo RTC wake-up, suspend handled by KOReader."}
    end
    if is("isKindle")then
        return {kind="kindle",model=model,available=true,label="Kindle · powerd",native_suspend=false,
            precise=false,recommended_interval=300,early_s=10,late_s=15,
            detail="Wake-up through powerd: about 15 s precision, 5 minutes recommended."}
    end
    return {kind="generic",model=model,available=true,label="WakeupMgr",native_suspend=false,precise=false,
        detail="Programmable wake-up; suspend left to the system."}
end
return C
