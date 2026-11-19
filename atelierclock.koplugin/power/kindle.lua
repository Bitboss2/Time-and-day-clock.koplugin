-- Kindle RTC coordination (KOReader device/kindle/powerd.lua + mockrtc.lua).
-- powerd owns suspension: on readyToSuspend KOReader programs our next
-- WakeupMgr epoch with setRtcWakeup, and after a scheduled wake it runs
-- wakeupAction(90) about 15 s later. Two Kindle specifics are handled here:
--   * the device may still be awake (screensaver state) when our minute comes;
--   * readyToSuspend drops a task whose epoch is already in the past.
-- A UI timer slightly after each epoch repairs both cases through the
-- scheduler's own recoverDue(), which never runs a foreign callback.
local load=...
local Capabilities=load("power/capabilities")
local K={grace_s=2}
function K.new(app)
    local self=setmetatable({app=app,recoveries=0}, {__index=K})
    self.caps=Capabilities.detect(app.device)
    self.active=self.caps.kind=="kindle"
    self.check=function()
        self.pending=false
        local p=self.app.scheduler
        if not p.active then return end
        if p:recoverDue(os.time(),"kindle_awake_or_dropped")then self.recoveries=self.recoveries+1 end
        self:after()
    end
    return self
end
-- Called after every arm (session start and each completed cycle).
function K:after()
    if not self.active then return end
    local p=self.app.scheduler;local ui=self.app.ui
    ui:unschedule(self.check);self.pending=false
    if not p.active or not p.stats.next then return end
    local delay=math.max(1,p.stats.next-os.time()+K.grace_s)
    ui:scheduleIn(delay,self.check);self.pending=true
end
function K:stop()
    if self.pending then self.app.ui:unschedule(self.check);self.pending=false end
end
return K
