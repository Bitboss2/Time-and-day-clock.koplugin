local load=...
local Time=load("core/time")
local P={}
function P.new(env)
    local self=setmetatable({env=env,generation=0,active=false,stats={cycles=0,errors=0,consecutive_errors=0,dispatches=0,recoveries=0,events={}}}, {__index=P})
    -- Stable callback reference is required by WakeupMgr:removeTasks.
    self.callback=function()
        local token=self.generation
        if not self.active then return end
        if self.deferred then return end
        self.stats.dispatches=self.stats.dispatches+1
        self.stats.alarm_lag_s=self.stats.next and math.max(0,os.time()-self.stats.next) or nil
        self.scheduled=false
        -- Never mutate WakeupMgr's queue from inside wakeupAction's callback:
        -- its caller removes index 1 *after* callback returns.
        self.deferred=function()
            self.deferred=nil
            if not self.active or self.generation~=token then return end
            local ok,err=pcall(self.env.refresh)
            if not ok then
                self.stats.errors=self.stats.errors+1;self.stats.consecutive_errors=self.stats.consecutive_errors+1
                self.stats.last_error=tostring(err);self:record("render_error",tostring(err))
            else self.stats.consecutive_errors=0 end
            self.stats.cycles=self.stats.cycles+1;self.stats.last=os.time()
            if self.stats.consecutive_errors>=3 then self:stop();self.env.failed("Rendu RTC interrompu après trois erreurs consécutives.");return end
            local armed,e=self:arm()
            if not armed and e then self.env.failed(e) end
            if self.active then
                local slept,sleep_error=pcall(self.env.sleep,token,ok)
                if not slept then self:record("sleep_error",tostring(sleep_error));self.env.failed(tostring(sleep_error)) end
            end
        end
        self.env.ui:nextTick(self.deferred)
    end
    return self
end
function P:record(kind,detail)
    local events=self.stats.events
    events[#events+1]={at=os.time(),kind=kind,detail=detail}
    if #events>24 then table.remove(events,1) end
end
-- Called only while Kobo is already awake, after a shared-alarm collision or
-- a delayed/missed dispatch. Repair our task, never execute a foreign callback.
function P:recoverDue(now,reason)
    if not self.active or self.deferred or not self.stats.next or self.stats.next>now then return false end
    self.env.mgr:removeTasks(nil,self.callback)
    self.scheduled=false;self.stats.recoveries=self.stats.recoveries+1
    self:record("due_recovery",reason);self.callback();return true
end
function P:start(settings)
    self:stop("nouvelle session")
    self.stats={cycles=0,errors=0,consecutive_errors=0,dispatches=0,recoveries=0,events={}}
    self.settings=settings;self.active=true
    return self:arm()
end
function P:arm()
    if not self.active then return false end
    local now=os.time();local epoch=Time.next(now,self.settings)
    if not epoch then self.stats.next=nil;return true end
    -- Kobo still needs time to finish suspend preparation. An alarm one second
    -- away can fire while the CPU is awake, before the kernel enters mem, and
    -- then leave the clock asleep with a past alarm. Delay that one update by
    -- a few seconds instead of skipping an entire minute or losing the alarm.
    local lead=self.env.minimum_lead and self.env.minimum_lead()or math.ceil((self.settings.wake_margin or .3)+3)
    epoch=math.max(epoch,now+math.max(4,lead))
    if not self.env.mgr then
        self.active=false;self:record("arm_error","no WakeupMgr")
        return nil,"RTC indisponible : écran statique."
    end
    if self.scheduled then self.env.mgr:removeTasks(nil,self.callback) end
    local ok,err=load("power/alarm").add(self.env.mgr,math.max(1,epoch-now),self.callback)
    if not ok then pcall(self.env.mgr.removeTasks,self.env.mgr,nil,self.callback)end
    self.scheduled=ok;self.stats.next=ok and epoch or nil;self.armed_at=now
    if not ok then
        self.active=false;self.stats.last_error=tostring(err)
        self:record("arm_error",tostring(err));return nil,"Programmation RTC : "..tostring(err)
    end
    return true
end
function P:stop(reason)
    if self.active then self:record("stop",reason or "arrêt de la session")end
    self.active=false;self.generation=self.generation+1
    if self.deferred then self.env.ui:unschedule(self.deferred);self.deferred=nil end
    if self.env.mgr and self.scheduled then
        local mgr=self.env.mgr;local epoch=self.stats.next
        mgr:removeTasks(nil,self.callback)
        -- Upstream removeTasks does not clear the physical alarm when the last
        -- entry disappears. Clear only the alarm we owned, with an empty queue.
        -- On i.MX5 RTCs (dodgy_rtc) a long wait is a chain of dummy alarms that
        -- removeTasks drops with ours; its first link may still be programmed.
        local alarm=mgr.getWakeupAlarmEpoch and tonumber(mgr:getWakeupAlarmEpoch())
        local ours=alarm and epoch and(alarm==epoch or(mgr.dodgy_rtc and alarm<epoch and alarm>=(self.armed_at or epoch)-1))
        if mgr._task_queue and #mgr._task_queue==0 and mgr.unsetWakeupAlarm and ours then mgr:unsetWakeupAlarm() end
    end
    self.scheduled=false;self.stats.next=nil
end
return P
