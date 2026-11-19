-- Owner of the Atelier screen output.
--   classic : KOReader refreshes (UIManager:setDirty) — always available.
--   fluid   : Fluid Ink 6.5 worker presents our 8-bit frames (A2/DU, optional pulses).
-- Lifecycle copied from Fluid Ink's demo.lua: one owner of EPDC writes at a time,
-- pause/stop barriers before suspend, and the worker is reaped and the waveform
-- restored before KOReader regains the framebuffer.
local load=...
local Profile=load("engine/profile")
local logger=require("logger")
local root=debug.getinfo(1,"S").source:sub(2):match("^(.*)/[^/]+$")
local ENGINE=root.."/fluidink/"
local D={}
-- Probe result is cached per KOReader session (the probe forks a child).
D.cache={}
local function now()
    local ok,time=pcall(require,"ui/time")
    if ok and time.now then return time.to_s(time.now())end
    return os.clock()
end
local function usleep(us)
    local ffi=require("ffi")
    if not pcall(function()ffi.C.usleep(us)end)then local t=os.clock()+us/1e6;repeat until os.clock()>=t end
end

function D.new(o)
    local self=setmetatable({app=o.app,ui=o.ui or o.app.ui,screen=o.screen or o.app.device.screen,
        device=o.device or o.app.device,on_change=o.on_change,native_factory=o.native_factory,
        startup_factory=o.startup_factory,platform_factory=o.platform_factory,
        state="classic",notice=nil,last={},rates={}}, {__index=D})
    self:select()
    return self
end
function D:settings()return self.app.settings.data end
function D:emit()
    -- The last engine state also goes into the exported diagnostic.
    local info=self:info();info.rates=nil;self.app.display_info=info
    if self.on_change then pcall(self.on_change,self.state,self)end
end

-- Decide the target profile without touching the screen.
function D:select()
    local platform,reason
    local s=self:settings()
    if s.display_engine=="classic"then
        self.profile=Profile.select(self.device.model,nil,s,"Chosen in settings");return self.profile
    end
    local factory=self.platform_factory or function(device,screen)return dofile(ENGINE.."platform.lua")(device,screen)end
    local ok,result=pcall(factory,self.device,self.screen)
    if ok then platform=result else reason=tostring(result):gsub("^.-:%d+: ","")end
    if platform then
        local bb=self.screen.bb
        local rotated=bb and bb.getRotation and bb:getRotation()~=0
        local inverted=bb and bb.getInverse and bb:getInverse()~=0
        if rotated or inverted then platform=nil;reason="Fluid engine available in portrait, without night mode"end
    end
    local cached=D.cache[self.device.model]
    if platform and cached and cached.ok==false then platform=nil;reason=cached.reason end
    self.platform=platform
    self.profile=Profile.select(self.device.model,platform,s,reason)
    return self.profile
end
function D:isFluid()return self.state=="fluid"end
function D:wanted()return self.profile and self.profile.engine=="fluid"end

-- Asynchronous RAM-only probe (child process), then worker start.
function D:start()
    if self.closed or self.state~="classic"or not self:wanted()then return false end
    local cached=D.cache[self.device.model]
    if cached and cached.ok then return self:launch()end
    local ok,err=pcall(function()
        local Startup=self.startup_factory or dofile(ENGINE.."startup.lua")
        self.probe=Startup.new(self.screen,self.platform)
    end)
    if not ok then return self:fail("Engine check: "..tostring(err),true)end
    self.state="probing";self:emit()
    self.probe_action=function()
        if self.closed or self.state~="probing"then return end
        local called,ready,reason=pcall(self.probe.poll,self.probe)
        if called and ready==nil then self.ui:scheduleIn(0.025,self.probe_action);return end
        if not called then reason=ready;ready=false end
        self.probe=nil
        if ready then D.cache[self.device.model]={ok=true};self.state="classic";self:launch()
        else
            D.cache[self.device.model]={ok=false,reason=tostring(reason)}
            self:fail("Fluid engine unavailable: "..tostring(reason),true)
        end
    end
    self.ui:scheduleIn(0.025,self.probe_action)
    return true
end
function D:launch()
    if self.closed or self.suspended then return false end
    local ok,err=pcall(function()
        local factory=self.native_factory or function(screen,platform)return dofile(ENGINE.."native.lua").new(screen,platform)end
        self.backend=factory(self.screen,self.platform)
        self.backend:start()
        local p=self.profile
        if p.phase and p.phase>0 and self.backend.setPhase then self.backend:setPhase(p.phase,p.drive_policy)end
    end)
    if not ok then
        local backend=self.backend;self.backend=nil
        if backend then pcall(backend.stop,backend);pcall(backend.kill,backend)
            for _=1,100 do if backend:done()then break end;usleep(2000)end
            pcall(backend.free,backend)end
        return self:fail("Fluid engine start: "..tostring(err),true)
    end
    self.state="fluid";self.started=now();self.last={};self.rates={};self.published_once=false
    logger.info("AtelierClock: Fluid Ink",self.profile.label)
    self:emit();return true
end
function D:fail(message,quiet)
    logger.warn("AtelierClock:",message)
    self.state="classic";self.profile=Profile.select(self.device.model,nil,self:settings(),message)
    self.notice=message;self.notice_quiet=quiet;self:emit();return false
end

-- Present one composed 8-bit frame (logical orientation, stride = width).
function D:publish(frame,moving)
    if self.state~="fluid"or not self.backend then return false end
    local p=self.profile;local rest=self:settings().display_rest~=false
    local s={wave=moving and p.wave or p.wave_still,dither=p.dither,gamma=p.gamma,window=p.window,
        capture=p.capture,paused=rest and not moving,dragging=moving,drive_policy=p.drive_policy,phase=p.phase or 0}
    local ok,result=pcall(self.backend.publish,self.backend,frame,s)
    if not ok then self:abort("Publish: "..tostring(result));return false end
    self.published_once=true
    return result>=0
end

-- Health check; call from the animation tick or a slow watch timer.
function D:check()
    if self.state~="fluid"or not self.backend then return self.state end
    local b=self.backend
    local ok,s=pcall(b.stats,b)
    if not ok then self:abort("Unreadable statistics");return self.state end
    if (s.phase_errno or 0)>0 and(self.profile.phase or 0)>0 then
        self.profile=Profile.withoutPulses(self.profile,s.phase_errno)
        pcall(b.setPhase,b,0,self.profile.drive_policy);self.notice=self.profile.detail;self:emit()
    end
    if b:done()then
        if b.watchdogTripped and b:watchdogTripped()then return self:recover()end
        self:abort("Display process stopped (state "..tostring(s.state)..")");return self.state
    end
    if (s.errors or 0)>0 then self:abort("ioctl EPDC : errno "..tostring(s.last_errno));return self.state end
    self:sample(s)
    return self.state
end
function D:sample(s)
    local t=now();local l=self.last
    if l.t and t-l.t>=1 then
        local dt=t-l.t
        local function rate(k)return ((s[k]or 0)-(l[k]or 0))%4294967296/dt end
        self.rates={publish=rate("published"),consume=rate("consumed"),scans=rate("phase_scans"),
            requests=rate("requests"),cpu=((s.worker_cpu_us or 0)-(l.worker_cpu_us or 0))%4294967296/(dt*1e4)}
        self.last=s;self.last.t=t
    elseif not l.t then self.last=s;self.last.t=t end
end
-- Watchdog: wait for neutralised LUT, free, continue in classic mode.
function D:recover()
    local b=self.backend;self.state="recovering";self:emit()
    local started=now()
    local function poll()
        local state=b.recoveryState and b:recoveryState()or 1
        if state==0 and now()-started<3 then self.ui:scheduleIn(0.025,poll);return end
        local freed,err=true,nil
        if state==1 then freed,err=b:free()else freed,err=false,"Restore not confirmed after the engine stopped. Restart the reader."end
        self.backend=nil
        self:fail(freed==false and err or "Fluid engine stopped by its safety watchdog: classic display for this session.")
        D.cache[self.device.model]={ok=false,reason="Engine watchdog triggered during this session"}
    end
    poll();return self.state
end
function D:abort(message)
    if not self.backend then return self:fail(message)end
    self:release(function()self:fail(message)end)
end

-- Asynchronous release: stop, reap, restore waveform/capture, then callback.
function D:release(callback,keep)
    local b=self.backend
    if not b or self.state=="releasing"then if callback then callback()end;return end
    self.resume_after=keep and self.state=="fluid"or nil
    self.state="releasing";self:emit()
    pcall(b.stop,b)
    local started=now()
    local function poll()
        if not b:done()then
            if now()-started>3 then pcall(b.kill,b)end
            self.ui:scheduleIn(0.025,poll);return
        end
        local ok,freed,err=pcall(b.free,b)
        self.backend=nil;self.state="classic"
        if not ok or freed==false then self.resume_after=nil;self:fail(not ok and tostring(freed)or err)end
        self:emit()
        if callback then callback()end
    end
    poll()
end
-- Synchronous bounded release, for Suspend/CloseWidget: the screensaver must
-- never be overwritten by a worker after this returns.
function D:releaseNow(keep)
    local b=self.backend
    if not b then return true end
    if self.state=="releasing"then keep=keep or self.resume_after end
    self.resume_after=keep and(self.state=="fluid"or self.state=="releasing")or nil
    pcall(b.pause,b,true)
    for _=1,50 do if b:pauseAck()or b:done()then break end;usleep(2000)end
    pcall(b.stop,b)
    for _=1,100 do if b:done()then break end;usleep(2000)end
    if not b:done()then pcall(b.kill,b);for _=1,100 do if b:done()then break end;usleep(2000)end end
    self.backend=nil;self.state="classic"
    if not b:done()then
        -- Could not reap in time: free later, never with a live worker.
        local function reap()if b:done()then pcall(b.free,b)else self.ui:scheduleIn(0.05,reap)end end
        self.ui:scheduleIn(0.05,reap);self.resume_after=nil
        self.notice="Fluid engine stopped in an emergency.";return false
    end
    local ok,freed,err=pcall(b.free,b)
    if not ok or freed==false then self.resume_after=nil;self.notice=not ok and tostring(freed)or err;return false end
    return true
end
function D:resume()
    if self.closed or self.suspended or not self.resume_after then return false end
    self.resume_after=nil;self:select()
    return self:launch()
end
function D:suspend()
    if self.probe then pcall(self.probe.cancel,self.probe);self.probe=nil;self.state="classic"end
    self.suspended=true;return self:releaseNow(true)
end
function D:wake()
    self.suspended=false
    return self:resume()
end
function D:clean()if self.backend and self.state=="fluid"then pcall(self.backend.clean,self.backend);return true end end
function D:close(callback)
    self.closed=true
    if self.probe_action then self.ui:unschedule(self.probe_action)end
    if self.probe then pcall(self.probe.cancel,self.probe);self.probe=nil end
    if self.backend then self:release(callback)elseif callback then callback()end
end
function D:info()
    local p=self.profile or {}
    return {state=self.state,label=p.label or "Classic KOReader",detail=self.notice or p.detail,
        fps=p.fps,rates=self.rates,phase=p.phase,model=self.device.model}
end
function D.resetCache()D.cache={}end
return D
