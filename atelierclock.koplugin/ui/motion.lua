-- Motion toolkit: easing, tweens, springs and an inertial scroller.
-- Pure Lua, time in ordinary seconds. Inspired by Fluid Ink's engine.lua
-- (filtered velocity, exponential decay, deadline skipping, never queueing
-- stale frames) and extended with rubber-band edges and snapping.
local M={}
local exp,abs,min,max,floor=math.exp,math.abs,math.min,math.max,math.floor

M.ease={
    linear=function(t)return t end,
    outCubic=function(t)t=1-t;return 1-t*t*t end,
    inOutCubic=function(t)if t<.5 then return 4*t*t*t end;t=-2*t+2;return 1-t*t*t/2 end,
    outQuint=function(t)t=1-t;return 1-t*t*t*t*t end,
    outBack=function(t)local c1,c3=1.70158,2.70158;t=t-1;return 1+c3*t*t*t+c1*t*t end,
}
function M.clamp(v,a,b)return v<a and a or v>b and b or v end
function M.lerp(a,b,t)return a+(b-a)*t end

-- Time-based tween; value(now) never overshoots duration.
local Tween={};Tween.__index=Tween
function M.tween(from,to,duration,ease,start)
    return setmetatable({from=from,to=to,duration=max(1e-3,duration),ease=M.ease[ease or "outCubic"]or ease,start=start or 0},Tween)
end
function Tween:progress(now)return M.clamp((now-self.start)/self.duration,0,1)end
function Tween:value(now)return M.lerp(self.from,self.to,self.ease(self:progress(now)))end
function Tween:done(now)return now-self.start>=self.duration end

-- Damped spring. zeta=1 critical, <1 playful overshoot.
local Spring={};Spring.__index=Spring
function M.spring(value,o)
    o=o or {}
    return setmetatable({x=value,v=0,target=value,omega=o.omega or 18,zeta=o.zeta or 1,eps=o.eps or .5},Spring)
end
function Spring:set(target)self.target=target end
function Spring:jump(value)self.x=value;self.v=0;self.target=value end
function Spring:step(dt)
    dt=min(.05,max(0,dt))
    -- Two substeps keep the semi-implicit integrator stable at 30 Hz.
    for _=1,2 do
        local h=dt/2;local a=-2*self.zeta*self.omega*self.v-self.omega*self.omega*(self.x-self.target)
        self.v=self.v+a*h;self.x=self.x+self.v*h
    end
    if self:settled()then self.x=self.target;self.v=0 end
    return self.x
end
function Spring:settled()return abs(self.x-self.target)<self.eps and abs(self.v)<self.eps*10 end

-- 1-D inertial scroller with rubber band, flings and optional snapping.
local Scroller={};Scroller.__index=Scroller
function M.scroller(o)
    o=o or {}
    local s=setmetatable({offset=o.offset or 0,min=o.min or 0,max=o.max or 0,velocity=0,dragging=false,
        snap=o.snap,decay=o.decay or 4.0,resist=o.resist or .42,maxv=o.maxv or 4200},Scroller)
    s.spring=M.spring(s.offset,{omega=o.omega or 16,zeta=o.zeta or .92,eps=.4});s.settling=false
    return s
end
function Scroller:setBounds(a,b)self.min=a;self.max=max(a,b)
    if not self.dragging and(self.offset<self.min or self.offset>self.max)then self:settle()end end
-- Rubber band: finger travel beyond an edge is mapped with resistance.
function Scroller:map(raw)
    if raw<self.min then return self.min-(self.min-raw)*self.resist end
    if raw>self.max then return self.max+(raw-self.max)*self.resist end
    return raw
end
function Scroller:unmap(offset)
    if offset<self.min then return self.min-(self.min-offset)/self.resist end
    if offset>self.max then return self.max+(offset-self.max)/self.resist end
    return offset
end
function Scroller:touch(pos,t)
    self.dragging=true;self.velocity=0;self.settling=false;self.last=pos;self.last_t=t;self.origin=pos;self.moved=0
    self.raw=self:unmap(self.offset)
end
-- pos increases downwards/rightwards; content moves with the finger.
function Scroller:drag(pos,t)
    if not self.dragging then self:touch(pos,t);return end
    local d=self.last-pos;local dt=max(.004,t-(self.last_t or t))
    self.raw=(self.raw or self.offset)+d
    self.offset=self:map(self.raw)
    local v=M.clamp(d/dt,-self.maxv,self.maxv)
    self.velocity=self.velocity*.3+v*.7
    self.moved=self.moved+abs(d);self.last=pos;self.last_t=t
end
function Scroller:release(t,fling)
    if not self.dragging and not fling then return end
    self.dragging=false
    if fling then self.velocity=M.clamp(fling,-self.maxv,self.maxv)
    elseif t-(self.last_t or t)>.12 then self.velocity=0 end
    if self.snap then self:settle()end
end
function Scroller:fling(v)self.dragging=false;self.velocity=M.clamp(v,-self.maxv,self.maxv);if self.snap then self:settle()end end
-- Choose a resting point (projected momentum for snapping) and spring to it.
function Scroller:settle(target)
    if not target then
        local projected=self.offset+self.velocity/self.decay
        if self.snap then target=self.snap(projected,self.velocity,self.offset)else target=M.clamp(self.offset,self.min,self.max)end
    end
    self.spring.x=self.offset;self.spring.v=self.snap and self.velocity*.4 or 0
    self.spring:set(M.clamp(target,self.min,self.max));self.settling=true;self.velocity=0
end
function Scroller:scrollTo(target,animated)
    if animated then self:settle(target)else self.offset=M.clamp(target,self.min,self.max);self.velocity=0;self.settling=false end
end
function Scroller:step(dt)
    if self.dragging then return true end
    dt=min(.1,max(0,dt))
    if self.settling then
        self.offset=self.spring:step(dt)
        if self.spring:settled()then self.settling=false;self.offset=self.spring.target end
        return self.settling
    end
    if abs(self.velocity)>8 then
        local decay=exp(-self.decay*dt)
        self.offset=self.offset+self.velocity*(1-decay)/self.decay
        self.velocity=self.velocity*decay
        if self.offset<self.min-40 or self.offset>self.max+40 then self.velocity=self.velocity*.5 end
        if self.offset<self.min or self.offset>self.max then
            if abs(self.velocity)<300 then self:settle()end
        end
        return true
    end
    self.velocity=0
    if self.offset<self.min or self.offset>self.max then self:settle();return true end
    return false
end
function Scroller:moving()return self.dragging or self.settling or abs(self.velocity)>8 end
function Scroller:value()return floor(self.offset+.5)end

-- Deadline helper copied in spirit from Fluid Ink: skip late frames.
function M.deadline(previous,now,period)
    local next_at=previous+period;local skipped=0
    if next_at<=now then skipped=floor((now-next_at)/period)+1;next_at=next_at+skipped*period end
    return next_at,skipped
end
-- Seconds from a KOReader gesture timestamp, or the current monotonic time.
function M.now()
    local ok,time=pcall(require,"ui/time")
    if ok and time and time.now then return time.to_s(time.now())end
    return os.clock()
end
function M.gestime(ges)
    if ges and ges.time then
        local ok,time=pcall(require,"ui/time")
        if ok and time and time.to_s then return time.to_s(ges.time)end
    end
    return M.now()
end
return M
