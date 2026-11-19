-- All native KOReader time fields are fixed-point times, NOT plain seconds.
-- Keep a single conversion boundary and never infer units from magnitudes.
local load=...
local U=load("core/util")
local ok,Time=pcall(require,"ui/time")
local M={}
function M.seconds(value)
    if not ok or type(value)~="number"or value~=value or math.abs(value)==math.huge then return nil end
    local convert=Time.to_s or Time.to_number
    if not convert then return nil end
    local success,s=pcall(convert,value)
    return success and type(s)=="number"and s==s and math.abs(s)~=math.huge and s or nil
end
function M.now()
    if not ok then return nil end
    local fn=Time.boottime_or_realtime or Time.boottime_or_realtime_coarse
    if not fn then return nil end
    local success,value=pcall(fn)
    return success and M.seconds(value)or nil
end
-- CLOCK_MONOTONIC stops during Linux suspend; CLOCK_BOOTTIME includes it.
-- Unlike the duration of a mem write, their difference excludes a refused
-- entry and the active kernel/sync overhead. No realtime fallback here.
function M.clocks()
    if not ok or Time.boottime_or_realtime~=Time.boottime or type(Time.monotonic)~="function"then return nil end
    local good,b,m=pcall(function()return Time.boottime(),Time.monotonic()end)
    if not good then return nil end
    b,m=M.seconds(b),M.seconds(m)
    if b and m then return {boot=b,mono=m}end
end
function M.new(device)
    return setmetatable({device=device,data={unit="seconds",samples={},samples_count=0,sleep_s=0,awake_s=0,short_sleeps=0}}, {__index=M})
end
function M:start()
    self.started=M.now();self.total=self.device.total_suspend_time or 0
    self.data={unit="seconds",samples={},samples_count=0,sleep_s=0,awake_s=0,short_sleeps=0,attempt_samples={},
        attempts=0,verified_sleep_s=0,verified_complete=true}
    self.woke=nil;self.before=nil;self.path=nil;self.attempt_clocks=nil;self.completed=nil
end
function M:stop()
    self:update();self.started=nil
end
function M:wake()
    local now=M.now();local d=self.device;local total=d.total_suspend_time
    local duration=M.seconds(d.last_suspend_time)
    if now and type(total)=="number"and type(self.total)=="number"and total>self.total then
        local delta=M.seconds(total-self.total)
        -- last_suspend_time can be stale on skipped suspend requests. Only a
        -- corresponding increase in total_suspend_time is evidence of a cycle.
        if duration and delta and duration>=0 and delta>=duration-.01 then
            local data=self.data;data.last_sleep_s=duration;data.sleep_s=data.sleep_s+delta
            data.samples_count=data.samples_count+1
            if duration<1 then data.short_sleeps=data.short_sleeps+1 end
            local sample={at=os.time(),sleep_s=duration,awake_before_s=self.before,path=self.path}
            if self.completed then
                for k,v in pairs(self.completed)do sample[k]=v end
                self.completed=nil
            end
            data.samples[#data.samples+1]=sample;if #data.samples>120 then table.remove(data.samples,1)end
        end
        self.total=total
    elseif type(total)=="number"and type(self.total)=="number"and total<self.total then
        self.data.counter_reset=true;self.total=total
    end
    self.completed=nil
    self.woke=now;self.before=nil
    self:update()
end
function M:beforeSuspend(path)
    local now=M.now()
    self.before=now and self.woke and math.max(0,now-self.woke)or nil
    self.path=path
    self.data.wake_to_suspend_s=self.before
    self.data.last_path=path
    self.attempt_clocks=M.clocks()
end
function M:returned()
    local after=M.clocks();local before=self.attempt_clocks;self.attempt_clocks=nil
    local data=self.data;data.attempts=(data.attempts or 0)+1
    local sample={attempt=data.attempts,at=os.time(),path=self.path,native_call_s=M.seconds(self.device.last_suspend_time)}
    if after and before then
        local elapsed=after.boot-before.boot;local active=after.mono-before.mono;local slept=elapsed-active
        if elapsed>=0 and active>=0 and slept>=-.01 and slept<=elapsed+.01 then
            sample.kernel_sleep_s=math.max(0,slept);sample.native_phase_s=elapsed
            sample.native_phase_awake_s=active
            data.verified_sleep_s=(data.verified_sleep_s or 0)+sample.kernel_sleep_s
            data.last_kernel_sleep_s=sample.kernel_sleep_s
        else data.verified_complete=false end
    else data.verified_complete=false end
    self.completed=sample
    local samples=data.attempt_samples
    samples[#samples+1]=sample;if #samples>120 then table.remove(samples,1)end
    return sample
end
function M:standbyReturned(before,after)
    local sample={}
    local data=self.data
    data.standby_calls=(data.standby_calls or 0)+1
    if before and after then
        local elapsed=after.boot-before.boot;local active=after.mono-before.mono;local slept=elapsed-active
        if elapsed>=0 and active>=0 and slept>=-.01 and slept<=elapsed+.01 then
            sample.native_phase_s=elapsed;sample.native_phase_awake_s=active;sample.kernel_sleep_s=math.max(0,slept)
            data.standby_call_s=(data.standby_call_s or 0)+elapsed
            data.standby_verified_sleep_s=(data.standby_verified_sleep_s or 0)+sample.kernel_sleep_s
            data.verified_sleep_s=data.verified_sleep_s+sample.kernel_sleep_s
        else data.verified_complete=false end
    else data.verified_complete=false end
    return sample
end
function M:update()
    local now=M.now();local data=self.data
    if now and self.started then
        local elapsed=now-self.started
        -- The fallback clock on old kernels may jump. Never present negative
        -- awake time or a plausible-looking ratio after a clock inconsistency.
        if elapsed>=0 and elapsed+.25>=data.sleep_s then
            data.elapsed_s=elapsed;data.outside_mem_s=math.max(0,elapsed-data.sleep_s)
            data.sleep_percent=elapsed>0 and math.min(100,data.sleep_s/elapsed*100)or nil
            data.verified_sleep_percent=data.verified_complete and data.attempts and data.attempts>0 and elapsed>0
                and math.min(100,(data.verified_sleep_s or 0)/elapsed*100)or nil
            data.verified_awake_s=data.verified_complete and math.max(0,elapsed-(data.verified_sleep_s or 0))or nil
            data.awake_s=data.verified_awake_s
        else data.clock_inconsistent=true;data.sleep_percent=nil;data.verified_sleep_percent=nil end
    end
    data.native_last_sleep_s=M.seconds(self.device.last_suspend_time)
    return data
end
function M:capabilities()
    local d=self.device
    local r={model=d.model,native_time_api=ok and "ui/time"or "unavailable",
        has_native_suspend=type(d._doSuspend)=="function",reliable_screen_wait=d.hasReliableMxcWaitFor and d:hasReliableMxcWaitFor()or false,
        kernel=U.read("/proc/version",4096),power_states=U.read("/sys/power/state",256),
        suspend_flag=U.read("/sys/power/state-extended",128),
        cpu_governor=U.read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",128)}
    return r
end
return M
