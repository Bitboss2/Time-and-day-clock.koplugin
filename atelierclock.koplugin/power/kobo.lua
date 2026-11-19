-- Minute RTC coordination and conditional reuse of the native suspend phase.
-- Native KOReader retains mem/sync/error handling; no direct sysfs writes here.
local load=...
local Measure=load("power/measure")
local U=load("core/util")
local Evidence=load("power/evidence")
local Settle=load("power/settle")
local logger=require("logger")
local K={}
function K.new(app)
    local self=setmetatable({app=app,last_sleep_total=tonumber(app.device.total_suspend_time)or 0,suspend_owner={}}, {__index=K})
    local d=app.device
    self.measure=Measure.new(d)
    self.settle=Settle.new(self)
    self.supported=d:isKobo() and (d.model=="Kobo_star" or d.model=="Kobo_star_r2")
        and type(d.scheduleUnexpectedWakeupGuard)=="function" and type(d.checkUnexpectedWakeup)=="function"
        and type(d.rescheduleSuspend)=="function"
    self.reuse_supported=self.supported and d.model=="Kobo_star"
    return self
end
function K:beginSession()
    self.settle:start()
    self.accelerations=0
    self.last_sleep_total=tonumber(self.app.device.total_suspend_time)or 0
    self.last_observed_total=self.last_sleep_total
    self.direct_pending=false;self.direct_disabled=false;self.direct_used=0;self.direct_fallbacks=0
    self.direct_entered=false;self.direct_reason=nil
    self.return_cycle=nil;self.in_attempt=false;self.retry_count=0;self.short_returns=0;self.guard_wait_s=0
    self.short_reports={};self.last_short_return=nil;self.last_guard=nil
    self.kernel_before=Evidence.capture(self.app.device);self.kernel_first=nil;self.kernel_cursor=self.kernel_before
    self.kernel_identity=Evidence.identity(self.app.device)
    logger.info("AtelierClock",load("core/version"),"session start",self.app.device.model)
    self.measure:start()
end
function K:endSession()
    self.settle:stop()
    if self.direct_pending and self.do_wrapper then self.app.ui:unschedule(self.do_wrapper)end
    self.direct_pending=false;self.direct_entered=false;self.direct_generation=nil
    self.return_cycle=nil;self.in_attempt=false
    self.measure:stop()
end
function K:diagnostic(include_kernel)
    return {timing=self.measure:update(),capabilities=self.measure:capabilities(),
        reuse_supported=self.reuse_supported,
        direct_cycles=self.direct_used or 0,direct_fallbacks=self.direct_fallbacks or 0,
        direct_disabled=self.direct_disabled or false,direct_reason=self.direct_reason,
        screen_wait_ms=self.screen_wait_ms,fast_guards=self.accelerations or 0,
        short_returns=self.short_returns or 0,bounded_native_retries=self.retry_count or 0,
        guard_wait_requested_s=self.guard_wait_s or 0,last_guard=self.last_guard,last_short_return=self.last_short_return,
        early_short_returns=self.short_reports,kernel_first_return=self.kernel_first,kernel_identity=self.kernel_identity,
        pmic_settle=self.settle.data,
        kernel_current=include_kernel and Evidence.capture(self.app.device)or nil}
end
function K:retryEligible()
    local a=self.app;local p=a.scheduler;local r=self.return_cycle;local now=Measure.now()
    if not r then return false,"no_clock_window"end
    if not now or now>r.expires then return false,"window_expired"end
    if r.tries>=2 then return false,"retry_limit"end
    if not a.settings.data.fast_rtc then return false,"fast_rtc_disabled"end
    if not p.active or not p.scheduled or p.stats.next~=r.epoch or r.generation~=p.generation or r.cycle~=p.stats.cycles then return false,"clock_changed"end
    if not a.session or a.session.user_resumed or not a.device.screen_saver_mode then return false,"user_or_session_changed"end
    if (a.device.unexpected_wakeup_count or 0)>20 then return false,"native_failure_limit"end
    if a.session.foreign_grace_until and a.session.foreign_grace_until>os.time()then return false,"foreign_grace"end
    local first=a.device.wakeup_mgr and a.device.wakeup_mgr._task_queue[1]
    if not first or first.callback~=p.callback or first.epoch~=r.epoch or first.epoch<os.time()+6 then return false,"foreign_or_close_alarm"end
    if not self:environmentIdle()then return false,"network_or_charging"end
    return true,"clock_owned"
end
function K:rescheduleReturn(delay)
    self.planning_return=true
    local good,result=pcall(self.app.device.rescheduleSuspend,self.app.device,delay)
    self.planning_return=false
    if not good then error(result)end
    -- Keep the native callback identity so resume() can cancel it. Ownership
    -- is an explicit argument, never a comparison of two different clocks.
    local d=self.app.device;self.app.ui:unschedule(d.suspend)
    self.app.ui:scheduleIn(delay,d.suspend,d,self.suspend_owner)
    return result
end
function K:callNativeCheck(device,...)
    local was=self.checking_native;self.checking_native=true
    local good,result=pcall(self.original_check,device,...)
    self.checking_native=was
    if not good then error(result)end
    return result
end
function K:observeWake(device,count)
    if not self.app.session or self.app.session.user_resumed or count==false then return end
    self.measure:wake()
    local total=tonumber(device.total_suspend_time)or 0
    if self.direct_pending and self.direct_entered then
        local seconds=Measure.seconds(device.last_suspend_time)
        if not seconds or seconds<1 or total<=(self.last_observed_total or 0)then
            self.direct_disabled=true;self.direct_fallbacks=(self.direct_fallbacks or 0)+1
            self.direct_reason="Retour natif après suspension trop courte"
        end
        self.direct_pending=false;self.direct_entered=false
    end
    self.last_observed_total=total
end
function K:suspendFlag()
    local b=U.read("/sys/power/state-extended",128)
    if not b then return nil end
    if b:match("^%s*1%s*$")then return true end
    if b:match("^%s*0%s*$")then return false end
    return nil
end
function K:flagIsSuspended()return self:suspendFlag()==true end
function K:environmentIdle()
    local ok,network=pcall(require,"ui/network/manager")
    if not ok or type(network.isWifiOn)~="function"then return false end
    local checked,on=pcall(network.isWifiOn,network)
    if not checked or on~=false then return false end
    local power=self.app.device:getPowerDevice()
    if not power or type(power.isCharging)~="function"then return false end
    local read,charging=pcall(power.isCharging,power)
    return read and charging==false
end
function K:install()
    if self.wrapper or not self.supported then return end
    local d=self.app.device
    self.original=d.scheduleUnexpectedWakeupGuard
    self.original_check=d.checkUnexpectedWakeup
    self.original_reschedule=d.rescheduleSuspend
    self.reschedule_wrapper=function(device,...)
        -- Another component's explicit request revokes our short retry window.
        if not self.planning_return then self.return_cycle=nil end
        return self.original_reschedule(device,...)
    end
    d.rescheduleSuspend=self.reschedule_wrapper
    if type(d.suspend)=="function"then
        self.original_suspend=d.suspend
        self.suspend_wrapper=function(device,...)
            local owned=select(1,...)==self.suspend_owner
            if not self.checking_native and not owned then self.return_cycle=nil end
            -- A new full preparation (including one requested by another
            -- plugin) takes precedence over an earlier reuse request.
            self.direct_pending=false;self.direct_entered=false;self.direct_generation=nil
            if owned then return self.original_suspend(device,select(2,...))end
            return self.original_suspend(device,...)
        end
        d.suspend=self.suspend_wrapper
    end
    if type(d._doSuspend)=="function"then
        self.original_do_suspend=d._doSuspend
        self.do_wrapper=function(device,...)
            if self.direct_pending then
                local a=self.app
                if not a.session or a.session.user_resumed or not a.scheduler.active
                    or self.direct_generation~=a.scheduler.generation or not device.screen_saver_mode then
                    self.direct_pending=false;self.direct_entered=false;return
                end
                -- Revalidate at execution, after the final input-processing
                -- margin: an earlier flag read alone is not a lease.
                if not self:flagIsSuspended()or not self:environmentIdle()then
                    self.direct_pending=false;self.direct_disabled=true
                    self.direct_fallbacks=(self.direct_fallbacks or 0)+1
                    self.direct_reason="Préparation native : drapeau, réseau ou charge modifiés"
                    device:rescheduleSuspend(a.settings.data.wake_margin);return
                end
                self.direct_entered=true;self.direct_used=(self.direct_used or 0)+1
            end
            if self.app.session and not self.app.session.user_resumed then
                self.measure:beforeSuspend(self.direct_pending and "reuse"or "native")
                self.in_attempt=true
            end
            return self.original_do_suspend(device,...)
        end
        d._doSuspend=self.do_wrapper
    end
    self.check_wrapper=function(device,...)
        if self.settle:run()then return end
        local a=self.app;local p=a.scheduler
        local active=p.active and a.session and not a.session.user_resumed and device.screen_saver_mode
        local first=device.wakeup_mgr and device.wakeup_mgr._task_queue[1]
        local stale=first and first.epoch<os.time()-30
        if active and first and first.callback==p.callback and first.epoch<=os.time()
            and not stale and device.wakeup_mgr.validateWakeupAlarmByProximity then
            local ok,valid=pcall(device.wakeup_mgr.validateWakeupAlarmByProximity,device.wakeup_mgr,first.epoch,30)
            stale=not ok or not valid
        end
        -- A past owned alarm cannot wake the kernel again. Repair it while the
        -- kernel is awake, before the native unexpected-wakeup limit can stop it.
        if active and first and first.callback==p.callback and stale
            and p:recoverDue(os.time(),"échéance de l'horloge dépassée") then
            a.ui:scheduleIn(30,device.suspend,device)
            return
        end
        if active and first and first.callback~=p.callback and first.epoch<=os.time()then
            a.session.foreign_grace_until=os.time()+30
        end
        local result=self:callNativeCheck(device,...)
        -- WakeupMgr services only its first task. If a foreign task occupied the
        -- same second, the next owned task may already be in the past now.
        if active and p.active and a.session and not a.session.user_resumed then
            first=device.wakeup_mgr and device.wakeup_mgr._task_queue[1]
            if not p.deferred and first and first.callback==p.callback and first.epoch<=os.time() then
                p:recoverDue(os.time(),"collision avec une alarme KOReader")
            end
            -- The inverse ordering matters too: our callback may have been
            -- first, with another plugin due immediately after it. Delegate
            -- those tasks to KOReader, with bounded work per UI turn.
            for _=1,8 do
                first=device.wakeup_mgr._task_queue[1]
                if not first or first.callback==p.callback or first.epoch>os.time()then break end
                local ok,valid=pcall(device.wakeup_mgr.validateWakeupAlarmByProximity,device.wakeup_mgr,first.epoch,30)
                if not ok or not valid then break end
                a.session.foreign_grace_until=os.time()+30
                self:callNativeCheck(device,...)
                if not p.active or not a.session or a.session.user_resumed then return result end
            end
            first=device.wakeup_mgr._task_queue[1]
            if first and first.callback~=p.callback and first.epoch>os.time()and first.epoch<=os.time()+30 then
                -- A hardware alarm that fires while the CPU is already awake
                -- needs an existing UI callback; it cannot wake mem later.
                a.ui:unschedule(device.checkUnexpectedWakeup)
                a.ui:scheduleIn(math.max(.2,first.epoch-os.time()+.1),device.checkUnexpectedWakeup,device)
            end
            if not p.deferred and p.scheduled and p.stats.next and a.session.foreign_grace_until
                and p.stats.next<=a.session.foreign_grace_until+3 then p:arm()end
        end
        return result
    end
    d.checkUnexpectedWakeup=self.check_wrapper
    self.wrapper=function(device,count)
        local attempt=self.in_attempt;self.in_attempt=false
        local evidence
        if attempt then evidence=self.measure:returned()end
        self:observeWake(device,count)
        self.original(device,count)
        local a=self.app;local p=a.scheduler;local q=device.wakeup_mgr and device.wakeup_mgr._task_queue
        local first=q and q[1]
        local delay,kind=15,"native"
        -- Native _doSuspend clears this flag on a refused mem write. Old
        -- hardware timekeeping may report >1 s for that failed call; duration
        -- alone must not silently restore a 15-second guard.
        local rejected=attempt and self:suspendFlag()==false
        local short=attempt and evidence and evidence.native_call_s and(evidence.native_call_s<1 or rejected)
        local kernel_short
        if count~=false and short and self.short_returns<3 then
            local snapshot=Evidence.capture(device)
            kernel_short=Evidence.since(self.kernel_cursor,snapshot)
            self.kernel_cursor=snapshot;self.settle:learn(kernel_short)
        end
        local retry_ok,retry_reason=false,"not_short"
        if short then retry_ok,retry_reason=self:retryEligible()end
        if count~=false and a.settings.data.fast_rtc and p.active and a.session and not a.session.user_resumed
            and device.screen_saver_mode and first and first.callback==p.callback
            and first.epoch<=os.time()and os.time()-first.epoch<=3 then
            -- User resume uses KOReader:resume(), which unschedules this same
            -- check. Keep a small window to process physical input first.
            delay,kind=.2,"owned_alarm"
            self.accelerations=(self.accelerations or 0)+1
        elseif count~=false and short and retry_ok and self.settle:plan(true)then
            delay,kind=self.settle:delay(),"standby_minute"
        elseif count~=false and short and retry_ok then
            -- A transient failed/short return after OUR minute update must
            -- not impose an unconditional 15s awake wait. Delegate the retry
            -- to the same native check (and full 2s preparation), at most twice
            -- in a 12s window. Never reset its failure budget here.
            local r=self.return_cycle;r.tries=r.tries+1
            delay,kind=r.tries,"short_return_retry"
            self.retry_count=(self.retry_count or 0)+1
        end
        if count~=false and short then
            self.short_returns=(self.short_returns or 0)+1
            self.last_short_return={at=os.time(),duration_s=evidence.native_call_s,kernel_sleep_s=evidence.kernel_sleep_s,
                native_rejected=rejected or false,
                flag=self:suspendFlag(),next_epoch=first and first.epoch,guard_kind=kind,guard_delay_s=delay,
                wakeup_budget=device.unexpected_wakeup_count,retry_reason=retry_reason}
            if self.short_returns<=3 then
                self.last_short_return.kernel=kernel_short
                if self.short_returns==1 then self.kernel_first=self.last_short_return.kernel end
                self.last_short_return.kernel_suspend_stats=U.read("/sys/kernel/debug/suspend_stats",4096)
                self.short_reports[#self.short_reports+1]=self.last_short_return
                logger.warn("AtelierClock",load("core/version"),"short mem return",evidence.native_call_s,
                    "guard",delay,"reason",retry_reason)
                local kernel=self.last_short_return.kernel
                if kernel and kernel.available and kernel.text~=""then
                    logger.warn("AtelierClock kernel snapshot, delta verified",kernel.delta_verified,kernel.text:sub(-4096))
                end
            end
        end
        if delay~=15 then
            a.ui:unschedule(device.checkUnexpectedWakeup)
            a.ui:scheduleIn(delay,device.checkUnexpectedWakeup,device)
        end
        self.last_guard={at=os.time(),kind=kind,delay_s=delay,retry_reason=retry_reason}
        self.guard_wait_s=(self.guard_wait_s or 0)+delay
        local samples=self.measure.data.attempt_samples or {};local sample=samples[#samples]
        if attempt and sample then sample.guard_kind=kind;sample.guard_delay_s=delay end
    end
    d.scheduleUnexpectedWakeupGuard=self.wrapper
end
function K:sleep(token,render_ok)
    local a=self.app;local p=a.scheduler;local d=a.device
    if not p.active or p.generation~=token or not a.session or a.session.user_resumed or not d.screen_saver_mode then return end
    if type(d.rescheduleSuspend)~="function" then return end
    -- The native budget counts all hardware wakeups. A successfully handled
    -- scheduled clock cycle after genuine suspend is not an unexpected wakeup.
    -- Never reset this budget on a failed/very short suspend: that would hide a
    -- kernel refusal and could leave the device in an endless busy loop.
    local total=tonumber(d.total_suspend_time)
    local duration=Measure.seconds(d.last_suspend_time)
    local flag=self:suspendFlag()
    local healthy=render_ok~=false and duration and duration>=1 and total and total>self.last_sleep_total
        and flag~=false
    if healthy then
        if (d.unexpected_wakeup_count or 0)>0 then
            p.stats.last_wakeup_budget=d.unexpected_wakeup_count
            d.unexpected_wakeup_count=0
        end
        self.last_sleep_total=total
    end
    if a.session.foreign_grace_until and a.session.foreign_grace_until>os.time()then return end
    -- A due foreign task may need its own processing time; preserve KOReader's
    -- standard grace period in that case (e.g. AutoSuspend poweroff).
    local lead=p.env.minimum_lead and p.env.minimum_lead()or 4
    for _,task in ipairs((d.wakeup_mgr or {})._task_queue or {}) do
        -- A future foreign alarm need not keep the CPU awake for 30 seconds.
        -- The shared RTC remains armed for it. Only imminent tasks cannot fit
        -- a complete native suspend preparation and retain their UI callback.
        if task.callback~=p.callback and task.epoch<=os.time()+math.max(4,lead)then return end
    end
    local started=Measure.now()
    local painted,result=pcall(function()
        a.ui:forceRePaint()
        if a.ui.waitForVSync then a.ui:waitForVSync();return true end
        return false
    end)
    local waited=painted and result==true
    if not painted then
        self.direct_disabled=true;self.direct_reason="Préparation native : attente écran en échec"
        p:record("screen_wait_error",tostring(result))
    end
    local finished=Measure.now()
    self.screen_wait_ms=started and finished and math.max(0,finished-started)*1000 or nil
    -- Only reuse a suspend preparation after a real, newly observed RTC sleep.
    -- Native _doSuspend already leaves state-extended at 1 after a successful
    -- wake; resume() and a failed mem write clear it. Never assume this flag.
    local reusable=self.reuse_supported and a.settings.data.reuse_suspend~=false and render_ok~=false and waited
        and type(d._doSuspend)=="function"and d._doSuspend==self.do_wrapper
        and d.hasReliableMxcWaitFor and d:hasReliableMxcWaitFor()
        and not G_reader_settings:isTrue("mxcfb_bypass_wait_for")
        and healthy
        and not self.direct_disabled and flag==true and self:environmentIdle()
    -- This lease exists only after a completed clock callback, never for the
    -- initial suspend. A foreign grace period/request cannot inherit it.
    local first=d.wakeup_mgr and d.wakeup_mgr._task_queue[1]
    local now=Measure.now()
    if render_ok~=false and now and (p.stats.cycles or 0)>0 and p.scheduled
        and first and first.callback==p.callback and first.epoch==p.stats.next then
        self.return_cycle={generation=token,cycle=p.stats.cycles,epoch=first.epoch,expires=now+12,rendered_at=now,tries=0}
    else self.return_cycle=nil end
    if render_ok~=false and self.settle:plan()then
        a.ui:unschedule(d.suspend);a.ui:unschedule(d._doSuspend);a.ui:unschedule(d.checkUnexpectedWakeup)
        a.ui:scheduleIn(self.settle:delay(),d.checkUnexpectedWakeup,d)
        self.direct_pending=false;self.direct_reason="Veille RTC native jusqu’à la prochaine minute"
        return
    end
    self:rescheduleReturn(a.settings.data.wake_margin)
    if reusable then
        -- Keep KOReader's native mem/sync/error/RTC-guard implementation. Skip
        -- only the redundant flag=1 write + two-second preparation. The native
        -- resume method cancels this same _doSuspend callback on user input.
        a.ui:unschedule(d.suspend)
        self.direct_pending=true;self.direct_entered=false;self.direct_generation=token
        self.direct_reason="Préparation réutilisée après fin de l’affichage"
        a.ui:scheduleIn(a.settings.data.wake_margin,d._doSuspend,d)
    else
        self.direct_pending=false
        if not self.direct_disabled then
            if not self.reuse_supported then self.direct_reason="Préparation native : modèle non ciblé"
            elseif a.settings.data.reuse_suspend==false then self.direct_reason="Réutilisation désactivée"
            elseif not healthy then self.direct_reason="Préparation native : sommeil non validé"
            elseif not waited then self.direct_reason="Préparation native : attente écran indisponible"
            elseif flag~=true then self.direct_reason="Préparation native : drapeau noyau absent ou inactif"
            else self.direct_reason="Préparation native : API écran ou suspension incompatible"end
        end
    end
end
return K
