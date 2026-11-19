-- Confirmed FP9928 devices can use native STOP standby for the whole RTC
-- interval. No short bridge, no auxiliary alarm, no immediate switch to mem.
local load=...
local Measure=load("power/measure")
local Evidence=load("power/evidence")
local logger=require("logger")
local S={output_delay_s=1}
function S.new(kobo)
    return setmetatable({k=kobo,data={}}, {__index=S})
end
function S:start()
    self.pending=nil;self.confirmed=false;self.disabled=false
    self.data={mode="native_rtc_standby",confirmed=false,cycles=0,attempts=0,cancelled=0,
        failures=0,early_wakes=0,samples={},output_delay_s=S.output_delay_s,auxiliary_alarms=0}
end
function S:stop()self.pending=nil end
function S:learn(kernel)
    local a=self.k.app;local identity=self.k.kernel_identity or {}
    if a.device.model~="Kobo_star"or not(identity.kernel or ""):match("^Linux version 3%.0%.35[%+%s%-]")then return end
    if kernel and kernel.available and kernel.delta_verified and type(kernel.text)=="string"
        and kernel.text:find("fp9928_suspend():waiting for VEE stable",1,true)then
        self.confirmed=true;self.data.confirmed=true
        self.data.evidence="fresh verified fp9928_suspend VEE message"
    end
end
function S:eligible(r)
    local k=self.k;local a=k.app;local d=a.device;local p=a.scheduler
    if not self.confirmed or self.disabled or not r or r~=k.return_cycle then return false end
    if not p.active or not p.scheduled or r.generation~=p.generation or r.cycle~=p.stats.cycles
        or r.epoch~=p.stats.next then return false end
    if not a.session or a.session.user_resumed or not d.screen_saver_mode or not a.settings.data.fast_rtc then return false end
    if k:suspendFlag()~=false or not k:environmentIdle()or(d.unexpected_wakeup_count or 0)>20 then return false end
    if type(d.standby)~="function"or d.standby_state~="standby"or type(d.canStandby)~="function"then return false end
    local good,can=pcall(d.canStandby,d);if not good or not can or not Measure.clocks()then return false end
    if a.session.foreign_grace_until and a.session.foreign_grace_until>os.time()then return false end
    local first=((d.wakeup_mgr or {})._task_queue or {})[1]
    return first and first.callback==p.callback and first.epoch==r.epoch and first.epoch>os.time()+3 or false
end
function S:plan(after_failure)
    local r=self.k.return_cycle
    if not self:eligible(r)then return false end
    self.pending={cycle=r,early=0,after_failure=after_failure};return true
end
function S:delay()
    -- UI-relative delays only. Old hardware clocks can jump at resume; the
    -- beta-8 BOOTTIME deadline must not decide whether the panel is ready.
    local minimum=self.pending and self.pending.after_failure and .2 or S.output_delay_s
    return math.max(minimum,tonumber(self.k.app.settings.data.wake_margin)or 0)
end
function S:run()
    local plan=self.pending;if not plan then return false end
    self.pending=nil
    if not self:eligible(plan.cycle)then self.data.cancelled=self.data.cancelled+1;return false end
    local k=self.k;local a=k.app;local d=a.device;local p=a.scheduler
    local before=Measure.clocks();local expected=plan.cycle.epoch
    local good,err=pcall(d.standby,d) -- nil duration: use the existing minute RTC alarm
    if not good and type(d.defaultCPUGovernor)=="function"then a.ui:nextTick(d.defaultCPUGovernor,d)end
    local sample=k.measure:standbyReturned(before,Measure.clocks())
    sample.expected_epoch=expected;sample.at=os.time();sample.path="standby_minute"
    self.data.attempts=self.data.attempts+1
    self.data.samples[#self.data.samples+1]=sample
    if #self.data.samples>12 then table.remove(self.data.samples,1)end
    k.measure:wake()
    if not a.session or a.session.user_resumed or not p.active or p.generation~=plan.cycle.generation
        or k.return_cycle~=plan.cycle or not d.screen_saver_mode then
        self.data.cancelled=self.data.cancelled+1;return true
    end
    local first=d.wakeup_mgr._task_queue[1]
    local same=p.active and p.generation==plan.cycle.generation and first and first.callback==p.callback
        and first.epoch==expected and a.session and not a.session.user_resumed and d.screen_saver_mode
    local valid,alarm=false,false
    if same and first.epoch<=os.time()and d.wakeup_mgr.validateWakeupAlarmByProximity then
        valid,alarm=pcall(d.wakeup_mgr.validateWakeupAlarmByProximity,d.wakeup_mgr,expected,3)
    end
    local slept=good and sample.kernel_sleep_s and sample.kernel_sleep_s>=.25
    local completed=slept and same and valid and alarm
    if completed then
        self.data.cycles=self.data.cycles+1
        if self.data.cycles==1 then logger.info("AtelierClock",load("core/version"),"native minute standby active")end
        p.stats.last_wakeup_budget=d.unexpected_wakeup_count
        d.unexpected_wakeup_count=0 -- only a real sleep followed by our verified RTC
    elseif slept and same and expected>os.time()+3 and plan.early<2 and self:eligible(plan.cycle)then
        plan.early=plan.early+1;self.pending=plan
        self.data.early_wakes=self.data.early_wakes+1
    else
        self.disabled=true;self.data.failures=self.data.failures+1
        self.data.reason=tostring(err or "Minute standby refused or repeated early wake-ups")
        self.data.kernel_failure=Evidence.since(k.kernel_cursor,Evidence.capture(d))
        logger.warn("AtelierClock",load("core/version"),"minute standby fallback",self.data.reason)
        local failure=self.data.kernel_failure
        if failure and failure.available then logger.warn("AtelierClock standby kernel",failure.text:sub(-4096))end
    end
    -- Keep the same native callback identity and its failure budget. Return
    -- to input processing before dispatching the RTC or re-entering standby.
    d:scheduleUnexpectedWakeupGuard()
    if completed or self.pending then
        a.ui:unschedule(d.checkUnexpectedWakeup)
        a.ui:scheduleIn(.2,d.checkUnexpectedWakeup,d)
        k.last_guard={at=os.time(),kind=completed and "standby_rtc"or "standby_early",delay_s=.2}
    end
    return true
end
return S
