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
        return {kind="none",model=model,available=false,label="Indisponible",
            detail="Pas de réveil programmable : l’horloge reste fixe pendant la veille."}
    end
    if is("isKobo")then
        return {kind="kobo",model=model,available=true,label="RTC matériel",native_suspend=true,
            precise=true,detail="Réveil RTC Kobo et suspension gérée par KOReader."}
    end
    if is("isKindle")then
        return {kind="kindle",model=model,available=true,label="Kindle · powerd",native_suspend=false,
            precise=false,recommended_interval=300,early_s=10,late_s=15,
            detail="Réveil par powerd : précision d’environ 15 s, 5 minutes conseillées."}
    end
    return {kind="generic",model=model,available=true,label="WakeupMgr",native_suspend=false,precise=false,
        detail="Réveil programmable ; suspension laissée au système."}
end
return C
