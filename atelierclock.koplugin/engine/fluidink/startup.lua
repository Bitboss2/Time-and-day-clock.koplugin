-- SPDX-License-Identifier: GPL-3.0-or-later
-- Exercise native loading/FFI in a disposable child before main-process use.
-- The probe uses private RAM, fd=-1, and NEVER touches the physical display.
local ffi=require("ffi")
local util=require("ffi/util")
local time=require("ui/time")
local DIR=debug.getinfo(1,"S").source:match("^@(.*/)")
local Startup={};Startup.__index=Startup
local function now()return time.to_s(time.now())end
local function note(path,msg)
    local f=io.open(path,"a");if f then f:write(msg,"\n");f:flush();f:close()end
end
local function probe(path,screen,platform)
    note(path,"probe: load native declarations")
    local Native=dofile(DIR.."native.lua")
    local w,h=screen:getWidth(),screen:getHeight()
    local old=screen.bb;local pw,ph=tonumber(old.w),tonumber(old.h)
    local stride=tonumber(old.stride);local kind=old:getType()
    local data=ffi.new("uint8_t[?]",stride*ph)
    local bb={w=pw,h=ph,stride=stride,data=data,getType=function()return kind end,
        getRotation=function()return old:getRotation()end,getInverse=function()return old:getInverse()end}
    local fake={bb=bb,fd=-1,update_data=ffi.new("uint8_t[68]"),
        getWidth=function()return w end,getHeight=function()return h end}
    note(path,"probe: dlopen / ABI / allocation (private RAM)")
    local b=Native.new(fake,platform)
    local source=ffi.new("uint8_t[?]",w*h)
    local canvas={data=source,stride=w}
    note(path,"probe: native worker start")
    b:start()
    local ok,err=pcall(function()
        local state={wave="a2",dither="bayer",gamma=false,window=4}
        for i=1,8 do
            ffi.fill(source,w*h,i%2==0 and 255 or 64)
            state.dither=({"bayer","blue","cluster","threshold"})[(i-1)%4+1]
            state.gamma=i%2==0
            assert(b:publish(canvas,state)>=0,"probe publish failed")
            ffi.C.usleep(10000)
        end
        note(path,"probe: native stats and quality command")
        b:clean()
        local good=false
        for _=1,100 do
            local s=b:stats()
            if s.errors>0 then error("probe native errno "..s.last_errno)end
            if s.requests>0 and s.clean_done>0 then good=true;break end
            if b:done()then error("probe worker exited before completion")end
            ffi.C.usleep(10000)
        end
        assert(good,"probe worker timeout")
    end)
    b:stop()
    local stopped=false
    for _=1,100 do if b:done()then stopped=true;break end;ffi.C.usleep(10000)end
    if not stopped then b:kill();error("probe worker could not stop")end
    b:free()
    if not ok then error(err)end
    note(path,"probe: PASS")
end
function Startup.new(screen,platform)
    assert(type(util.runInSubProcess)=="function" and type(util.getNonBlockingReadSize)=="function",
        "InkMotion : fonctions de sous-processus indisponibles dans KOReader")
    local path=DIR.."inkmotion-startup.log"
    local f=io.open(path,"w");if f then f:write("InkMotion 6.5.0 startup; RAM-only native probe\n");f:close()end
    local pid,fd=util.runInSubProcess(function(_,pipefd)
        local ok,err=pcall(probe,path,screen,platform)
        local result=ok and "OK" or ("FAIL "..tostring(err))
        note(path,result)
        util.writeToFD(pipefd,result,true)
    end,true,false)
    assert(pid,fd)
    return setmetatable({pid=pid,fd=fd,path=path,started=now()},Startup)
end
function Startup:poll()
    if not util.isSubProcessDone(self.pid,false)then
        if now()-self.started>5 then
            util.terminateSubProcess(self.pid)
            self.timed_out=true
        end
        return nil
    end
    -- Read only bytes known to be present; descendants might have inherited
    -- the writer, so read-until-EOF would risk blocking the UI.
    local result=""
    local n=util.getNonBlockingReadSize(self.fd)or 0
    if n>0 then
        n=math.min(n,4096);local buf=ffi.new("char[?]",n)
        local got=tonumber(ffi.C.read(self.fd,buf,n))
        if got>0 then result=ffi.string(buf,got)end
    end
    ffi.C.close(self.fd);self.fd=nil
    if self.cancelled then return false,"Annulé"end
    if result=="OK" and not self.timed_out then return true end
    note(self.path,"parent: probe failed; native library NOT loaded in KOReader")
    return false,(self.timed_out and "Délai de vérification dépassé." or
        result~="" and result or "Le test natif s’est arrêté brutalement.")..
        "\nJoindre inkmotion-startup.log et crash.log."
end
function Startup:cancel()self.cancelled=true;util.terminateSubProcess(self.pid)end
return Startup
