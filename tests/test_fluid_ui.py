"""Fluid Ink integration and 30 Hz interface, with a fake native backend.

The fake replaces only libinkmotion (start/publish/stats/stop/free…); the
profile choice, the display lifecycle, the animation loop and every gesture
run the real plugin code against a deterministic clock. Optical cadence,
ghosting and pulse waveforms can only be measured on the reader itself.
"""
from runtime import Runtime, ROOT
from PIL import Image
import unittest

OUT=ROOT/'tests/output';OUT.mkdir(exist_ok=True)

SETUP=r'''
T=1000
Motion=load_module('ui/motion');Motion.now=function()return T end
local ui=app.ui
queue={}
function ui:scheduleIn(delay,fn,...)queue[#queue+1]={due=T+(delay or 0),fn=fn,args={...}}end
function ui:nextTick(fn,...)self:scheduleIn(0,fn,...)end
function ui:unschedule(fn)for i=#queue,1,-1 do if queue[i].fn==fn then table.remove(queue,i)end end end
function run(seconds)
    local stop=T+seconds
    for _=1,20000 do
        local idx
        for i,t in ipairs(queue)do if t.due<=stop and(not idx or t.due<queue[idx].due)then idx=i end end
        if not idx then T=stop;return end
        local t=table.remove(queue,idx);T=math.max(T,t.due);t.fn(unpack(t.args))
    end
    error('scheduler runaway')
end
backends={}
function native_factory(screen,platform)
    local b={published={},phase_calls={},stats_t={published=0,consumed=0,phase_scans=0,requests=0,errors=0,phase_errno=0,state=1},
        alive=true,platform=platform}
    function b:start()self.started=true end
    function b:setPhase(n,p)self.phase_calls[#self.phase_calls+1]={n,p}end
    function b:publish(bb,s)
        assert(bb.stride and bb.data,'frame must be a BB8 with data/stride')
        local c={};for k,v in pairs(s)do c[k]=v end;self.published[#self.published+1]=c
        self.stats_t.published=self.stats_t.published+1;return 0
    end
    function b:stats()return self.stats_t end
    function b:done()return not self.alive end
    function b:stop()self.stopped=true;self.alive=false end
    function b:kill()self.killed=true;self.alive=false end
    function b:free()self.freed=true;return true end
    function b:pause(p)self.paused=p end
    function b:pauseAck()return true end
    function b:watchdogTripped()return self.watchdog==true end
    function b:recoveryState()return 1 end
    function b:clean()self.cleaned=(self.cleaned or 0)+1 end
    backends[#backends+1]=b;return b
end
platform={id=0,name='Kobo NTX',wait=0x4004462f,custom=true}
function platform_factory()return platform end
startup_factory={new=function()return {poll=function()return true end,cancel=function()end}end}
function studio()
    local st=load_module('ui/studio'):new{app=app,native_factory=native_factory,platform_factory=platform_factory,startup_factory=startup_factory}
    st:paintTo(require('ffi/blitbuffer').new(758,1024,1));run(.3)
    assert(st.display:isFluid(),'fluid engine did not start')
    return st
end
function last(b)return b.published[#b.published]end
'''

class FluidProfileTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.app=self.r.app();self.r.lua.globals().app=self.app
    def tearDown(self):self.r.close()
    def test_01_profiles_per_reader(self):
        self.r.lua.execute(r'''
            local P=load_module('engine/profile')
            local s={display_engine='auto',display_fps=30}
            local a=P.select('Kobo_star',{custom=true,name='Kobo NTX'},s)
            assert(a.engine=='fluid' and a.name=='pulses' and a.drive_policy==12 and a.phase==2)
            assert(a.window==1 and a.dither=='bayer' and a.gamma==false and a.fps==30 and a.wave=='a2')
            for _,m in ipairs({'Kobo_star_r2','Kobo_snow','Kobo_snow_r2','Kobo_alyssum','Kobo_daylight','Kobo_nova','KindlePaperWhite2','KindlePaperWhite3','KindleVoyage'})do
                local f=P.select(m,{custom=false,name='Kobo Mk7'},s)
                assert(f.engine=='fluid' and f.name=='fallback' and f.phase==0 and f.drive_policy==2,m)
                assert(f.window==1 and f.dither=='bayer' and f.wave=='a2' and f.wave_still=='du',m)
            end
            local r=P.withoutPulses(a,95);assert(r.phase==0 and r.drive_policy==12 and r.name=='fallback')
            assert(P.select('Kobo_star',nil,s,'x').engine=='classic')
            s.display_engine='classic';assert(P.select('Kobo_star',{custom=true},s).engine=='classic')
            s.display_engine='auto';s.display_fps=60;assert(P.select('Kobo_star',{custom=true},s).fps==60)
        ''')
    def test_02_motion_models(self):
        self.r.lua.execute(r'''
            local M=load_module('ui/motion')
            local sp=M.spring(0,{omega=20,zeta=.8});sp:set(100)
            for _=1,90 do sp:step(1/30)end;assert(sp:settled()and sp.x==100)
            local s=M.scroller{min=0,max=1000}
            s:touch(500,0);for i=1,5 do s:drag(500-i*40,i*.016)end;s:release(.09)
            assert(s.velocity>500,'fling velocity '..s.velocity)
            for _=1,240 do s:step(1/30)end
            assert(not s:moving()and s.offset>200 and s.offset<=1000)
            s.offset=0;s:touch(0,1);s:drag(200,1.05);assert(s.offset<0 and s.offset>-200,'rubber band')
            s:release(1.3);for _=1,120 do s:step(1/30)end;assert(s.offset==0)
            local snap=M.scroller{min=0,max=900,snap=function(p)return math.floor(p/300+.5)*300 end}
            snap:touch(0,0);snap:drag(-170,.1);snap:release(.3);for _=1,120 do snap:step(1/30)end
            assert(snap.offset==300,'snap '..snap.offset)
            local n,sk=M.deadline(0,.1,1/30);assert(sk==3 and n>.1)
        ''')

class FluidStudioTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.app=self.r.app();g=self.r.lua.globals();g.app=self.app
        self.r.lua.execute(SETUP)
    def tearDown(self):self.r.close()
    def test_03_aura2_starts_with_pulses_debit_profile_and_never_uses_koreader_refresh(self):
        self.r.lua.execute(r'''
            app.ui.dirty={}
            local st=studio();local b=backends[1]
            assert(b.started and b.phase_calls[1][1]==2 and b.phase_calls[1][2]==12,'Impulsions 2 not requested')
            assert(st.toast_text and st.toast_text:find('Fluid engine on'),'no engine-on notice')
            run(3.5) -- the notice slides in and out, then the panel rests
            local s=last(b);assert(s.drive_policy==12 and s.phase==2 and s.window==1 and s.dither=='bayer' and s.gamma==false and s.capture)
            assert(s.paused==true,'final frame must be still')
            local dirty=#app.ui.dirty
            st:switchTab('Veille');run(.6)
            assert(not st.transition and st.tab_spring:settled()and st.tab_spring.x==3)
            local moving=0;for _,p in ipairs(b.published)do if p.dragging then moving=moving+1 end end
            assert(moving>=7,'transition frames: '..moving)
            assert(last(b).paused==true)
            assert(#app.ui.dirty==dirty,'KOReader refresh requested while Fluid Ink owns the panel')
            st:onCloseWidget()
            assert(b.stopped and b.freed,'worker not released on close')
        ''')
    def test_04_carousel_drag_snaps_and_sheet_flow(self):
        self.r.lua.execute(r'''
            local st=studio();st.catalog=true;st:refresh();run(.2)
            local box=st.carousel_box;assert(box,'no carousel')
            local cx,cy=box.x+box.w/2,box.y+box.h/2
            st:onTouch(nil,{pos={x=cx,y=cy}})
            for i=1,6 do T=T+.016;st:onPan(nil,{pos={x=cx-45*i,y=cy},start_pos={x=cx,y=cy},relative={x=-45*i,y=0}})end
            st:onPanRelease(nil,{pos={x=cx-270,y=cy}});run(1.2)
            assert(st.browser_index>=2,'carousel did not advance')
            assert(math.abs(st.carousel.offset-(st.browser_index-1)*st.spacing)<1,'carousel not snapped')
            st:onSwipe(nil,{direction='west',distance=300,pos={x=cx,y=cy}});run(1)
            local idx=st.browser_index
            -- complication sheet: open, choose, ghost flies, sheet closes
            st.catalog=false;st:switchTab('Composer');run(.6)
            st.slot_picker='charge';st:refresh();run(.8)
            assert(st.sheet and st.sheet.spring:settled(),'sheet not open')
            local choice;for _,r in ipairs(st.regions)do if r.provider=='week'then choice=r end end
            assert(choice,'provider target missing')
            st:onTap(nil,{pos={x=choice.x+choice.w/2,y=choice.y+choice.h/2}})
            assert(not st.slot_picker and st.dirty and st.fly)
            run(2);assert(not st.sheet and not st.fly,'sheet or ghost left behind')
            assert(load_module('core/collection').current(st.draft).slots.charge.provider=='week')
            st:onCloseWidget()
        ''')
    def test_05_text_entry_hands_the_panel_back_then_resumes(self):
        self.r.lua.execute(r'''
            local st=studio();local b=backends[1];local got
            app.ui.shown={}
            st:input('Nom','A',function(v)got=v end);run(.2)
            assert(b.stopped and b.freed and st.display.state=='classic','not released before dialog')
            local dialog=app.ui.shown[#app.ui.shown];assert(dialog and dialog.buttons,'dialog not shown')
            dialog.buttons[1][2].callback();assert(got=='A')
            run(.6);assert(st.display:isFluid()and #backends==2 and backends[2].started,'not resumed')
            st:onCloseWidget()
        ''')
    def test_06_suspend_resume_pulses_refused_watchdog(self):
        self.r.lua.execute(r'''
            local st=studio();local b=backends[1]
            st:onSuspend();assert(b.paused and b.stopped and b.freed and st.display.state=='classic','suspend barrier')
            st:onResume();run(2);assert(st.display:isFluid()and #backends==2)
            local b2=backends[2];b2.stats_t.phase_errno=95
            st.display:check();assert(st.display.profile.name=='fallback' and st.display.profile.phase==0)
            assert(b2.phase_calls[#b2.phase_calls][1]==0,'pulses not disabled')
            st:switchTab('Diagnostic');run(.6)
            assert(last(b2).phase==0)
            b2.watchdog=true;b2.alive=false;st.display:check();run(.2)
            assert(st.display.state=='classic' and b2.freed and st.display.notice,'watchdog recovery')
            assert(load_module('engine/display').cache[app.device.model].ok==false)
            load_module('engine/display').resetCache()
            st:onCloseWidget()
        ''')
    def test_07_reduced_motion_and_switch_animation(self):
        self.r.lua.execute(r'''
            app.settings.data.motion='full'
            local st=studio();local b=backends[1]
            st:switchTab('Diagnostic');run(1.5)
            st.scroll:scrollTo(500,false);st:compose()
            local row;for _,r in ipairs(st.regions)do if r.key=='display_rest'then row=r end end
            assert(row,'switch row missing')
            local before=#b.published
            st:onTap(nil,{pos={x=row.x+row.w-20,y=row.y+row.h/2}})
            assert(st.knobs and st.knobs.display_rest,'knob animation missing');run(.5)
            assert(not st.knobs.display_rest and st.draft.display_rest==false and #b.published>before+3)
            st.draft.motion='reduced';assert(not st:animated())
            st:switchTab('Veille');assert(not st.transition,'reduced motion must not slide')
            st:onCloseWidget()
        ''')
    def test_09_no_koreader_refresh_while_a_worker_exists(self):
        self.r.lua.execute(r'''
            local st=studio();run(3.5)
            -- Every setDirty must happen while no worker exists.
            local setDirty=app.ui.setDirty;local violations=0
            app.ui.setDirty=function(ui,w,...)if st.display.backend then violations=violations+1 end;return setDirty(ui,w,...)end
            local flushed_before_start=nil
            local nf=native_factory
            native_factory=function(...)flushed_before_start=app.ui.repainted;return nf(...)end
            local fr=app.ui.forceRePaint;function app.ui:forceRePaint()self.repainted=(self.repainted or 0)+1;return fr(self)end
            st.display.native_factory=native_factory
            -- Change an engine setting and apply: release, KOReader repaint, relaunch.
            st:change('display_fps',45);assert(st:apply());run(1)
            assert(st.display:isFluid()and #backends==2,'engine not relaunched after apply')
            assert(flushed_before_start and flushed_before_start>=1,'KOReader was not flushed before the worker started')
            st:switchTab('Veille');run(1);st:refresh();run(1)
            st:input('Name','A',function()end);run(.2)
            local dialog=app.ui.shown[#app.ui.shown];dialog.buttons[1][1].callback();run(1)
            assert(st.display:isFluid(),'not resumed after text entry')
            assert(violations==0,'KOReader refresh requested while a worker existed: '..violations)
            app.ui.setDirty=setDirty;st:onCloseWidget()
        ''')
    def test_10_errors_release_the_worker_and_close_the_studio(self):
        self.r.lua.execute(r'''
            local st=studio();local b=backends[1]
            app.ui.shown={st}
            st.compose=function()error('boom in compose')end
            st:switchTab('Veille');run(.5)
            assert(b.stopped and b.freed,'worker survived an error')
            assert(st.closed,'studio not closed after a fatal error')
            assert(st.display.state=='classic' and not st.display.backend)
            -- a gesture handler error is contained too
            local st2=studio();local b2=backends[#backends]
            st2.hitRegion=function()error('boom in tap')end
            assert(st2:onTap(nil,{pos={x=10,y=10}})==true)
            run(.2);assert(b2.freed and st2.closed)
        ''')
    def test_08_fluid_frames_screenshots(self):
        lua=self.r.lua
        lua.execute(r'''
            st=studio();st.catalog=true;st:refresh();run(.2)
            frames={}
            local box=st.carousel_box;local cx,cy=box.x+box.w/2,box.y+box.h/2
            st:onTouch(nil,{pos={x=cx,y=cy}})
            for i=1,4 do T=T+.03;st:onPan(nil,{pos={x=cx-55*i,y=cy},start_pos={x=cx,y=cy},relative={x=-55*i,y=0}});st:compose()end
            frames[1]=st.frame:copy()
            st:onPanRelease(nil,{pos={x=cx-220,y=cy}});run(1)
            st.slot_picker='charge';st.catalog=false;st:switchTab('Composer');run(.6);st.slot_picker='charge';st:refresh();T=T+.06;st:tick()
            frames[2]=st.frame:copy();run(1)
            st:closeSheet();run(1)
        ''')
        frames=lua.eval('frames')
        frames[1].img.save(OUT/'fluid-carousel-drag.png');frames[2].img.save(OUT/'fluid-sheet-opening.png')
        a=frames[1].img;self.assertEqual(a.size,(758,1024))
        lua.execute('st:onCloseWidget()')

if __name__=='__main__':unittest.main()
