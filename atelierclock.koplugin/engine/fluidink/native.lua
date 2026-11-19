-- SPDX-License-Identifier: GPL-3.0-or-later
-- Parent never submits or waits for EPDC updates during animation.
local ffi=require("ffi")
local util=require("ffi/util")
local DIR=debug.getinfo(1,"S").source:match("^@(.*/)")
local function trace(stage)
    local f=io.open(DIR.."inkmotion-startup.log","a")
    if f then f:write("native: ",stage,"\n");f:flush();f:close()end
end
if not pcall(ffi.typeof,"im_config") then ffi.cdef[[
typedef struct im_context im_context;
typedef struct {
 int width,height,physical_width,physical_height,stride,bpp,rotation,inverse;
 int fd; uint32_t wait_ioctl,initial_marker; uint8_t *framebuffer;
 uint32_t transport,wake_epdc;
} im_config;
typedef struct {
 uint32_t published,consumed,overwritten,requests,completed,waits,errors;
 uint32_t changed,quant_us,copy_us,send_us,wait_us,max_send_us;
 uint32_t state,last_errno,submitted_seq,last_marker,cleans,clean_done,paused;
 uint32_t capture_active,effective_window;
 uint32_t phase_mode,phase_errno,phase_pending,phase_scans,phase_pulses,phase_restores;
 uint32_t plan_calls,plan_us,commit_us,max_plan_us,phase_cycles,phase_cycle_us,source_updates,max_source_age_us;
 uint32_t du_primes,du_prime_us,pipelined_plans,fused_calls,fused_us;
 uint32_t position_plans,position_pixels,position_cpu_us,worker_cpu_us;
 uint32_t fluid_refreshes,fluid_parked,source_copy_saved;
 uint32_t region_requests,region_rows;
} im_stats;
]]end
ffi.cdef[[
im_context *im_create(const im_config *, const uint8_t *);
int im_publish(im_context *,const uint8_t *,int,int,int,int,int);
void im_read_stats(im_context *,im_stats *);
void im_clean(im_context *); void im_pause(im_context *,int);
int im_pause_ack(im_context *); void im_stop(im_context *);
int im_run(im_context *); void im_destroy(im_context *); int im_version(void);
unsigned im_abi_size(unsigned which);
void im_set_capture(im_context *,int); int im_restore_capture(im_context *);
int im_collect_waveform(const char *);
int im_collect_ntx_waveform(const char *);
int im_configure_phase(im_context *,const char *,const char *);
void im_set_still(im_context *,int);
void im_set_presentation(im_context *,unsigned,unsigned,int);
int im_restore_phase(im_context *);
int im_phase_watchdog_tripped(im_context *);
int im_phase_recovery_state(im_context *);
]]
local Native={};Native.__index=Native
local names={"published","consumed","overwritten","requests","completed","waits","errors",
 "changed","quant_us","copy_us","send_us","wait_us","max_send_us","state","last_errno",
 "submitted_seq","last_marker","cleans","clean_done","paused","capture_active","effective_window","phase_mode","phase_errno","phase_pending","phase_scans","phase_pulses","phase_restores","plan_calls","plan_us","commit_us","max_plan_us","phase_cycles","phase_cycle_us","source_updates","max_source_age_us","du_primes","du_prime_us","pipelined_plans","fused_calls","fused_us","position_plans","position_pixels","position_cpu_us","worker_cpu_us","fluid_refreshes","fluid_parked","source_copy_saved","region_requests","region_rows"}
function Native.new(screen,platform)
    assert(ffi.os=="Linux","InkMotion v1 : Linux requis")
    assert(type(util.runInSubProcess)=="function" and type(util.isSubProcessDone)=="function",
        "InkMotion v1 : mettre à jour KOReader (sous-processus indisponibles)")
    assert(not screen.full_bb,"InkMotion v1 : désactiver le viewport de l’écran")
    local bb=screen.bb
    assert(bb and screen.fd and screen.update_data,"InkMotion v1 : framebuffer mxcfb requis")
    assert(bb:getType()==1 or bb:getType()==3,"InkMotion v1 : framebuffer 8/16 bits requis")
    if not platform then
        if screen.fd < 0 then platform={id=0,wait=0x4004462f,custom=true}
        else platform=dofile(DIR.."platform.lua")(screen.device,screen) end
    end
    local library=platform.id==3 and "libinkmotion-kindlepw2.so" or "libinkmotion-arm.so"
    local libpath=os.getenv("INKMOTION_NATIVE_LIBRARY") or DIR.."bin/"..library
    trace("dlopen")
    local lib=ffi.load(libpath)
    assert(lib.im_version()==6500,"InkMotion : binaire natif incompatible (remplacer le dossier entier)")
    assert(lib.im_abi_size(0)==ffi.sizeof("im_config") and lib.im_abi_size(1)==ffi.sizeof("im_stats"),
        "InkMotion : structures FFI incompatibles")
    trace("ABI checked")
    local f=assert(io.open(DIR.."noise64.bin","rb"));local noise=f:read("*all");f:close()
    assert(#noise==4096,"InkMotion : texture de tramage manquante")
    local cfg=ffi.new("im_config")
    cfg.width,cfg.height=screen:getWidth(),screen:getHeight()
    cfg.physical_width,cfg.physical_height=tonumber(bb.w),tonumber(bb.h)
    cfg.stride,cfg.bpp,cfg.rotation,cfg.inverse=bb.stride,bb:getType()==1 and 8 or 16,bb:getRotation(),bb:getInverse()
    cfg.fd=screen.fd;cfg.wait_ioctl=platform.wait;cfg.initial_marker=screen.marker or 0
    cfg.transport,cfg.wake_epdc=platform.id,platform.wake_epdc and 1 or 0
    cfg.framebuffer=ffi.cast("uint8_t *",bb.data)
    trace("create shared context")
    local ctx=lib.im_create(cfg,ffi.cast("const uint8_t *",noise))
    assert(ctx~=nil,"InkMotion : allocation partagée impossible, errno "..ffi.errno())
    if platform.custom and lib.im_configure_phase(ctx,DIR.."factory-reference.bin",DIR.."inkmotion-phase-status.txt")<0 then
        trace("phase reference unavailable: "..ffi.errno())
    end
    trace("context ready")
    return setmetatable({lib=lib,ctx=ctx,cfg=cfg,screen=screen,platform=platform,statbuf=ffi.new("im_stats")},Native)
end
function Native:start()
    assert(not self.pid)
    trace("fork worker")
    local ctx,lib=self.ctx,self.lib
    local pid,err=util.runInSubProcess(function()lib.im_run(ctx)end,false,false)
    assert(pid,err);self.pid=pid
    trace("worker started")
end
function Native:publish(bb,s)
    self.lib.im_set_capture(self.ctx,s.capture==false and 0 or 1)
    self.lib.im_set_still(self.ctx,s.paused and not s.dragging and 1 or 0)
    self.lib.im_set_presentation(self.ctx,s.drive_policy or 2,s.phase or 0,0)
    if not self.has_published then trace("first publish")end
    local result=self.lib.im_publish(self.ctx,ffi.cast("const uint8_t *",bb.data),bb.stride,
        s.wave=="du" and 1 or 0,({bayer=0,blue=1,cluster=2,threshold=3})[s.dither],s.gamma and 1 or 0,s.window)
    if not self.has_published then trace("first publish returned");self.has_published=true end
    return result
end
function Native:setPhase(n,policy)self.lib.im_set_presentation(self.ctx,policy,n,1)end
function Native:stats()
    self.lib.im_read_stats(self.ctx,self.statbuf)
    local s={};for _,k in ipairs(names)do s[k]=tonumber(self.statbuf[k])end;return s
end
function Native:watchdogTripped()return self.lib.im_phase_watchdog_tripped(self.ctx)~=0 end
function Native:recoveryState()return self.lib.im_phase_recovery_state(self.ctx)end
function Native:clean()self.lib.im_clean(self.ctx)end
function Native:pause(p)self.lib.im_pause(self.ctx,p and 1 or 0)end
function Native:pauseAck()return self.lib.im_pause_ack(self.ctx)~=0 end
function Native:stop()if self.ctx then self.lib.im_stop(self.ctx)end end
function Native:done()return not self.pid or util.isSubProcessDone(self.pid,false)end
function Native:kill()if self.pid then util.terminateSubProcess(self.pid)end end
function Native:collect(prefix)
    local lib=self.lib
    if not self.platform.custom and not self.platform.collect_ntx then return nil end
    local collect=self.platform.collect_ntx and lib.im_collect_ntx_waveform or lib.im_collect_waveform
    return util.runInSubProcess(function()collect(prefix)end,false,false)
end
function Native:free()
    assert(self:done(),"InkMotion : worker doit être arrêté avant libération")
    if self.ctx then
        if self.lib.im_restore_phase(self.ctx)<0 then
            trace("PHASE RESTORE FAILED: reboot required")
            return false,"Restauration LUT non confirmée. Redémarrer la liseuse avant de reprendre les essais."
        end
        local s=self:stats();if s.last_marker~=0 then self.screen.marker=s.last_marker end
        if self.lib.im_restore_capture(self.ctx)<0 then trace("warning: could not restore QUEUE_AND_MERGE")end
        trace("destroy context")
        self.lib.im_destroy(self.ctx);self.ctx=nil
        trace("context freed")
    end
    return true
end
return Native
