"""Regressions from physical Aura 2 feedback: density, legibility, RTC stalls."""
from runtime import Runtime, ROOT, PLUGIN
from pathlib import Path
from PIL import Image, ImageChops
import unittest

OUT=ROOT/'tests/output'
OUT.mkdir(exist_ok=True)

NATIVE=r'''
local T=require("ui/time")
local src=load_module('core/util').read(upstream..'/device.lua')
local first=src:find('function Kobo:rescheduleSuspend',1,true)
local last=src:find('function Kobo:standby',first,true)
native=assert(loadstring("local Kobo={};local UIManager=require('ui/uimanager');local logger=require('logger');"..src:sub(first,last-1)..';return Kobo'))()
d=app.device;ui=app.ui
app.kobo.original=native.scheduleUnexpectedWakeupGuard
app.kobo.original_check=native.checkUnexpectedWakeup
d.checkUnexpectedWakeup=app.kobo.check_wrapper
d.rescheduleSuspend=native.rescheduleSuspend
d.suspend=function(self)self.test_slept=true end
d.unexpected_wakeup_count=0
app.settings.data.fast_rtc=true
local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
real_time=os.time
now=app.scheduler.stats.next
os.time=function(t)if t then return real_time(t)end;return now end
function cycle(lag)
 now=app.scheduler.stats.next+(lag or 0);d.last_suspend_time=require("ui/time").s(55);d.total_suspend_time=(d.total_suspend_time or 0)+T.s(55)
 d:scheduleUnexpectedWakeupGuard()
 local guard=ui:runNext();assert(guard and guard.fn==d.checkUnexpectedWakeup,'guard missing')
 local deferred=ui:runNext();assert(deferred and deferred.delay==0,'deferred missing')
 assert(app.scheduler.active and #ui.tasks==1 and ui.tasks[1].fn==d.suspend,'sleep lost')
 ui.tasks={}
end
'''

class RegressionTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua;self.app=self.r.app();self.lua.globals().app=self.app
    def tearDown(self):self.r.close()
    def test_01_native_90_minutes_with_alarm_collisions(self):
        self.lua.execute(NATIVE+r'''
            local foreign=0
            for i=1,90 do
                now=app.scheduler.stats.next
                if i%10==0 then d.wakeup_mgr:addTask(-1,function()foreign=foreign+1 end)end
                cycle(i==37 and 75 or 0)
                assert(d.unexpected_wakeup_count==0,'healthy RTC wakeups consumed failure budget')
                assert(#d.wakeup_mgr._task_queue==1,'duplicate tasks')
            end
            assert(app.scheduler.stats.cycles==90 and foreign==9)
            assert(app.scheduler.stats.recoveries==10)
            assert(#app.scheduler.stats.events<=24)
            os.time=real_time
        ''')
    def test_02_native_failed_suspend_protection_is_preserved(self):
        self.lua.execute(NATIVE+r'''
            package.preload['ui/event']=function()return {new=function(_,name)return {name=name}end}end
            local limited=false
            function ui:broadcastEvent(e)
                if e.name=='UnexpectedWakeupLimit'then limited=true;app:stop('native failure limit')end
            end
            now=app.scheduler.stats.next-60;d.last_suspend_time=T.s(.05)
            for i=1,21 do
                d:scheduleUnexpectedWakeupGuard();ui:runNext();ui.tasks={}
            end
            assert(limited and not app.scheduler.active)
            assert(d.unexpected_wakeup_count>=21,'failure protection was suppressed')
            os.time=real_time
        ''')
    def test_03_invalid_rtc_validation_repairs_only_owned_task(self):
        self.lua.execute(NATIVE+r'''
            local original=d.wakeup_mgr.rtc.validateWakeupAlarmByProximity
            d.wakeup_mgr.rtc.validateWakeupAlarmByProximity=function()return false end
            cycle()
            assert(app.scheduler.stats.cycles==1 and app.scheduler.stats.recoveries==1)
            assert(app.scheduler.stats.next>now)
            d.wakeup_mgr.rtc.validateWakeupAlarmByProximity=original
            cycle();assert(app.scheduler.stats.cycles==2)
            os.time=real_time
        ''')
    def test_04_transient_render_errors_are_not_accumulated_as_fatal(self):
        self.lua.execute(NATIVE+r'''
            local n=0
            app.scheduler.env.refresh=function()n=n+1;if n%7==0 then error('transient')end end
            for i=1,90 do cycle()end
            assert(app.scheduler.active and app.scheduler.stats.errors==12)
            assert(app.scheduler.stats.consecutive_errors==0)
            os.time=real_time
        ''')
    def test_05_recovery_cannot_execute_after_user_resume(self):
        self.lua.execute(NATIVE+r'''
            now=app.scheduler.stats.next+75;d.last_suspend_time=require("ui/time").s(55)
            d:scheduleUnexpectedWakeupGuard();ui:runNext()
            assert(app.scheduler.deferred)
            app:resume()
            assert(not app.scheduler.deferred and not app.scheduler.active)
            for _,t in ipairs(ui.tasks)do assert(t.fn~=app.scheduler.deferred)end
            os.time=real_time
        ''')
    def test_06_density_uses_real_dpi_not_only_resolution(self):
        self.lua.execute(r'''
            local M=load_module('ui/metrics');local s=app.device.screen
            s.dpi=167;local a=M.ui(s,758,1024,100)
            s.dpi=212;local b=M.ui(s,758,1024,100)
            s.dpi=300;local c=M.ui(s,758,1024,100)
            assert(a<b and b<c)
            assert(math.abs(b-212/160)<.001)
        ''')
    def test_07_ui_views_on_three_density_and_resolution_pairs(self):
        cls=self.r.load('ui/studio');BB=self.lua.eval('require("ffi/blitbuffer")')
        s=self.app.device.screen
        for w,h,dpi in [(600,800,167),(758,1024,212),(1072,1448,300)]:
            s.w=w;s.h=h;s.dpi=dpi
            studio=cls.new(cls,self.r.to_lua({'app':self.app}))
            for tab in ['Galerie','Composer','Veille','Diagnostic']:
                studio.tab=tab;studio.refresh(studio)
                canvas=BB.new(w,h,1);studio.paintTo(studio,canvas)
                canvas.img.save(OUT/f'ui-{tab.lower()}-{dpi}dpi.png')
                for region in studio.regions.values():
                    self.assertGreaterEqual(region.x,-1,(dpi,tab,'x'))
                    self.assertGreaterEqual(region.y,-1,(dpi,tab,'y'))
                    self.assertLessEqual(region.x+region.w,w+2,(dpi,tab,'right'))
                    self.assertLessEqual(region.y+region.h,h+2,(dpi,tab,'bottom'))
                self.assertGreaterEqual(21*studio.k,21*dpi/160-.1)
            studio.onCloseWidget(studio)
    def test_08_compact_landscape_and_enlarged_ui_reflow(self):
        cls=self.r.load('ui/studio');BB=self.lua.eval('require("ffi/blitbuffer")');s=self.app.device.screen
        for w,h,scale in [(1024,758,100),(758,1024,140)]:
            s.w=w;s.h=h;s.dpi=212;self.app.settings.data.ui_scale=scale
            studio=cls.new(cls,self.r.to_lua({'app':self.app}))
            for tab in ['Galerie','Composer','Veille','Diagnostic']:
                studio.tab=tab;studio.refresh(studio);canvas=BB.new(w,h,1);studio.paintTo(studio,canvas)
                canvas.img.save(OUT/f'ui-{tab.lower()}-{w}x{h}-scale{scale}.png')
                for r in studio.regions.values():
                    if studio.top<=r.y<studio.h-134*studio.k:
                        self.assertLessEqual(r.y+r.h,studio.bottom+2,(tab,w,h,scale,'overlaps footer'))
            studio.onCloseWidget(studio)
    def test_09_live_preview_drag_and_element_selection(self):
        self.lua.globals().legacy_path=str(ROOT/"tests/fixtures/legacy.clock")
        self.lua.execute(r'''
            local legacy=load_module("packages/reader").open(legacy_path,app.data_dir.."/cache")
            app.faces[#app.faces+1]=legacy;app.settings.data.face=legacy.id
            local studio=load_module('ui/studio'):new{app=app};studio.tab='Composer'
            local bb=require('ffi/blitbuffer').new(758,1024,1);studio:paintTo(bb)
            local r=studio.preview_box
            studio:onPan(nil,{pos={x=r.x+r.w/2,y=r.y+r.h/2},relative={x=20,y=15}})
            assert(studio.draft.time.x~=0 and studio.draft.time.y~=0)
            assert(studio.draft.auto_layout==false and studio.dirty)
            studio:onPanRelease(nil,{pos={x=r.x+r.w/2,y=r.y+r.h/2}})
            assert(not studio.canvas_drag);studio:onCloseWidget()
        ''')
    def test_10_main_clock_occupies_majority_of_width(self):
        self.lua.execute(r'''
            local scene=load_module('render/scene').new(app,app:face('totem'),app.settings.data,758,1024)
            scene:render(1793270040)
            local hour=scene.old.hours.rect
            assert(hour.w>=758*.65,'main time too small')
            assert(scene.old.slot_date.rect.h>=22,'date became microscopic')
            scene:free()
        ''')
    def test_11_save_ui_scale_and_preserve_older_settings(self):
        self.lua.execute(r'''
            local S=load_module('core/settings')
            local old=S.validate{face='orbite',fast_rtc=true,scale=110}
            assert(old.ui_scale==100 and old.fast_rtc and old.scale==110 and old.face=='orbite')
            old.ui_scale=130;local s=S.new(test_data..'/density.json');assert(s:save(old))
            assert(S.new(s.path).data.ui_scale==130)
        ''')
    def test_12_monochrome_ui_has_no_low_contrast_backgrounds(self):
        cls=self.r.load('ui/studio');BB=self.lua.eval('require("ffi/blitbuffer")')
        studio=cls.new(cls,self.r.to_lua({'app':self.app}));studio.tab='Veille'
        canvas=BB.new(758,1024,1);studio.paintTo(studio,canvas)
        # Font antialiasing may have intermediate tones. Since 0.3.0 fills use
        # paper, ink and three light design tokens (wash, shadow, hairline)
        # that Fluid Ink dithers cleanly; arbitrary mid-grey fills stay banned.
        hist=canvas.img.histogram();total=758*1024
        self.assertGreater((hist[0]+hist[255])/total,.86)
        tokens=hist[0]+hist[255]+hist[238]+hist[214]+hist[200]
        self.assertGreater(tokens/total,.96)
        self.assertLess(sum(hist[60:190])/total,.02)
        studio.onCloseWidget(studio)
    def test_13_rtc_ioctl_failure_cannot_be_hidden_by_cached_alarm(self):
        self.lua.execute(r'''
            local mgr=app.device.wakeup_mgr
            function mgr.rtc:setWakeupAlarm(epoch)
                self.epoch=epoch -- emulate upstream cached tm updated before ioctl
                return nil,-1,'driver refused'
            end
            local p=load_module('power/scheduler').new{ui=app.ui,mgr=mgr,refresh=function()end,sleep=function()end,failed=function()end}
            local ok,err=p:start{interval=60,quiet=false}
            assert(not ok and err and not p.active and #mgr._task_queue==0)
            assert(p.stats.events[#p.stats.events].kind=='arm_error')
        ''')
    def test_14_ui_scale_takes_effect_after_apply(self):
        self.lua.execute(r'''
            local studio=load_module('ui/studio'):new{app=app}
            local before=studio.k;studio:change('ui_scale',130)
            assert(studio:apply());assert(studio.k>before)
            studio:onCloseWidget()
        ''')
    def test_15_alarm_cannot_expire_during_suspend_preparation(self):
        self.lua.execute(r'''
            local real=os.time;local now=1800000059
            os.time=function(t)if t then return real(t)end;return now end
            local p=load_module('power/scheduler').new{ui=app.ui,mgr=app.device.wakeup_mgr,refresh=function()end,sleep=function()end,failed=function()end}
            p:start{interval=60,quiet=false,wake_margin=.3}
            assert(p.stats.next-now>=4 and p.stats.next-now<10)
            p:stop();os.time=real
        ''')
    def test_16_acceleration_never_dispatches_before_the_deadline(self):
        self.lua.execute(NATIVE+r'''
            now=app.scheduler.stats.next-1;d.last_suspend_time=require("ui/time").s(55)
            d:scheduleUnexpectedWakeupGuard()
            assert(#ui.tasks==1 and ui.tasks[1].delay==15)
            app:stop();os.time=real_time
        ''')
    def test_17_own_alarm_before_foreign_alarm_same_second(self):
        self.lua.execute(NATIVE+r'''
            local foreign=0
            for i=1,30 do
                now=app.scheduler.stats.next
                local q=d.wakeup_mgr._task_queue
                q[#q+1]={epoch=now,callback=function()foreign=foreign+1 end}
                cycle()
                assert(app.scheduler.stats.next>now+30)
            end
            assert(foreign==30 and app.scheduler.stats.cycles==30)
            os.time=real_time
        ''')
    def test_18_nearby_foreign_alarm_during_awake_grace_is_serviced(self):
        self.lua.execute(NATIVE+r'''
            now=app.scheduler.stats.next
            local foreign=0
            d.wakeup_mgr:addTask(29,function()foreign=foreign+1 end)
            d.last_suspend_time=require("ui/time").s(55);d:scheduleUnexpectedWakeupGuard();ui:runNext();ui:runNext()
            assert(app.scheduler.stats.cycles==1 and #ui.tasks==1 and ui.tasks[1].fn==d.suspend)
            ui.tasks={};now=now+29
            d:scheduleUnexpectedWakeupGuard();ui:runNext()
            assert(foreign==1 and app.scheduler.active)
            assert(app.scheduler.stats.next>=now+33,'clock alarm would fire before grace ended')
            os.time=real_time
        ''')
    def test_19_stale_suspend_duration_cannot_reset_failure_budget(self):
        self.lua.execute(NATIVE+r'''
            d.last_suspend_time=T.s(55);d.total_suspend_time=T.s(55);app.kobo.last_sleep_total=T.s(55)
            d.unexpected_wakeup_count=12
            app.kobo:sleep(app.scheduler.generation,true)
            assert(d.unexpected_wakeup_count==12,'stale sleep data masked a failure')
            d.total_suspend_time=T.s(110)
            app.kobo:sleep(app.scheduler.generation,true)
            assert(d.unexpected_wakeup_count==0,'new successful suspend was ignored')
            os.time=real_time
        ''')

if __name__=='__main__':unittest.main(verbosity=2)
