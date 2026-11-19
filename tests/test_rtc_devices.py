"""RTC wake-up on every Fluid Ink compatible reader.

Kobo models use the real upstream WakeupMgr with the harness RTC. Kindle
models use the real upstream device/kindle/mockrtc.lua and the real
KindlePowerD wake functions (getPowerdState … initWakeupMgr) extracted from
the pinned KOReader commit. Nothing here proves a physical wake-up: it checks
that our scheduling, recovery and cleanup follow each device class's contract.
"""
from runtime import Runtime
import unittest

KOBO=['Kobo_star','Kobo_star_r2','Kobo_snow','Kobo_snow_r2','Kobo_alyssum','Kobo_daylight','Kobo_nova']
KINDLE=['KindlePaperWhite2','KindlePaperWhite3','KindleVoyage']

KINDLE_SETUP=r'''
print=function()end -- mockrtc logs with print()
package.preload['device/kindle/mockrtc']=function()return dofile(upstream..'/kindle_mockrtc.lua')end
local src=load_module('core/util').read(upstream..'/kindle_powerd.lua')
local first=src:find('function KindlePowerD:setRtcWakeup',1,true)
local last=src:find('-- Ask powerd to reset',first,true)
local chunk=src:sub(first,last-1):gsub('function KindlePowerD:setRtcWakeup.-\nend\n','',1)
KindlePowerD=assert(loadstring("local KindlePowerD={};local UIManager=require('ui/uimanager');local logger=require('logger');"..
  "local WakeupMgr=dofile(upstream..'/wakeupmgr.lua');"..chunk..";return KindlePowerD"))()
local d=require('device')
d.model=model;d.wakeup_mgr=nil
function d:isKobo()return false end
function d:isKindle()return true end
function d:supportsScreensaver()return screensaver_support end
d.rescheduleSuspend=nil
powerd=setmetatable({device=d,lipc_handle={get_string_property=function()return powerd_state end},rtc_calls={}}, {__index=KindlePowerD})
function powerd:setRtcWakeup(n)self.rtc_calls[#self.rtc_calls+1]=n end
powerd_state='screenSaver'
powerd:initWakeupMgr()
'''

class RtcDeviceTests(unittest.TestCase):
    def runtime(self):
        r=Runtime();self.addCleanup(r.close);return r

    def test_01_every_kobo_arms_cycles_and_cleans_its_alarm(self):
        for model in KOBO:
            with self.subTest(model=model):
                r=self.runtime();r.lua.globals().model=model
                r.lua.execute("local d=require('device');d.model=model;function d:isKindle()return false end")
                app=r.app();r.lua.globals().app=app
                r.lua.execute(r'''
                    local caps=load_module('power/capabilities').detect(app.device)
                    assert(caps.kind=='kobo' and caps.available and caps.native_suspend)
                    assert(not app.kindle.active)
                    assert(app.kobo.supported==(model=='Kobo_star' or model=='Kobo_star_r2'))
                    assert(app.kobo.reuse_supported==(model=='Kobo_star'))
                    local d=app.device;local mgr=d.wakeup_mgr;local ui=app.ui
                    local reschedules=0
                    d.rescheduleSuspend=function(_,n)reschedules=reschedules+1 end
                    d.suspend=function()end
                    local real=os.time;now=real();os.time=function(t)if t then return real(t)end;return now end
                    local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
                    local p=app.scheduler
                    assert(p.active and p.stats.next and mgr.rtc:getWakeupAlarmEpoch()==p.stats.next,'alarm not armed')
                    for cycle=1,3 do
                        now=p.stats.next;d.screen_saver_mode=true
                        assert(mgr:wakeupAction(30),'callback not dispatched')
                        local task=ui:runNext();assert(task and task.delay==0,'deferred render missing')
                        assert(p.stats.cycles==cycle and p.stats.next>now,'no re-arm after cycle')
                        assert(mgr.rtc:getWakeupAlarmEpoch()==p.stats.next)
                        ui.tasks={}
                    end
                    assert(reschedules==3,'native suspend not requested after each cycle')
                    app:stop('test')
                    assert(not mgr.rtc:isWakeupAlarmScheduled() and #mgr._task_queue==0,'alarm left behind')
                    os.time=real
                ''')

    def test_02_dodgy_rtc_long_quiet_pause_chain_is_cleaned(self):
        # i.MX5 pmic_rtc cannot program > 0xFFFF s; WakeupMgr chains dummy
        # alarms. A 22 h quiet pause must arm, then stop without leftovers.
        r=self.runtime();app=r.app();r.lua.globals().app=app
        r.lua.execute(r'''
            local mgr=app.device.wakeup_mgr;mgr.dodgy_rtc=true;mgr._task_queue={}
            local real=os.time;local now=os.time{year=2026,month=11,day=19,hour=0,min=30,sec=0}
            os.time=function(t)if t then return real(t)end;return now end
            local p=app.scheduler
            assert(p:start{interval=60,quiet=true,quiet_start=0,quiet_end=23})
            assert(p.stats.next-now>0xFFFF,'test needs a chained alarm')
            assert(#mgr._task_queue>1,'upstream chain expected')
            assert(mgr._task_queue[#mgr._task_queue].callback==p.callback)
            p:stop('test')
            assert(#mgr._task_queue==0 and not mgr.rtc:isWakeupAlarmScheduled(),'chain left behind')
            mgr.dodgy_rtc=false;os.time=real
        ''')

    def test_03_kindle_rtc_via_powerd_scheduled_awake_and_dropped(self):
        for model in KINDLE:
            with self.subTest(model=model):
                r=self.runtime();g=r.lua.globals();g.model=model;g.screensaver_support=True
                r.lua.execute(KINDLE_SETUP)
                app=r.app();g.app=app
                r.lua.execute(r'''
                    local d=app.device;local mgr=d.wakeup_mgr;local ui=app.ui;local p=app.scheduler
                    local caps=load_module('power/capabilities').detect(d)
                    assert(caps.kind=='kindle' and caps.available and not caps.native_suspend)
                    assert(app.kindle.active and not app.kobo.supported)
                    local real=os.time;now=real();os.time=function(t)if t then return real(t)end;return now end
                    local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
                    assert(p.active and p.stats.next,'not armed')
                    assert(mgr.rtc:getWakeupAlarmEpoch()==p.stats.next,'mockrtc not programmed')
                    local function find(fn)for _,t in ipairs(ui.tasks)do if t.fn==fn then return t end end end
                    assert(find(app.kindle.check),'awake guard missing')
                    -- 1. powerd suspends: KOReader hands the remaining seconds to lipc.
                    powerd:readyToSuspend(5)
                    assert(powerd.rtc_calls[#powerd.rtc_calls]==p.stats.next-now,'setRtcWakeup not called')
                    -- 2. scheduled wake: powerd checks 15 s later and runs wakeupAction(90).
                    ui.tasks={}
                    now=p.stats.next-10 -- Kindle may wake up to 10 s early
                    powerd:wakeupFromSuspend(0)
                    local check=ui.tasks[1];assert(check and check.delay==15)
                    ui.tasks={};now=now+15;powerd_state='screenSaver'
                    check.fn(unpack(check.args))
                    local deferred;for _,t in ipairs(ui.tasks)do if t.delay==0 then deferred=t end end
                    assert(deferred,'scheduled wake did not dispatch our callback')
                    ui.tasks={};deferred.fn()
                    assert(p.stats.cycles==1 and p.stats.next>now,'no re-arm after Kindle wake')
                    assert(find(app.kindle.check),'guard not renewed')
                    -- 3. still awake when the minute arrives: the UI guard renders.
                    local before=p.stats.cycles;now=p.stats.next+2
                    local guard=find(app.kindle.check);ui.tasks={};guard.fn()
                    for _,t in ipairs(ui.tasks)do if t.delay==0 then t.fn()end end
                    assert(p.stats.cycles==before+1 and p.stats.next>now,'awake minute missed')
                    assert(app.kindle.recoveries==1)
                    -- 4. readyToSuspend dropped a past task: the guard repairs it.
                    now=p.stats.next+1;powerd:readyToSuspend(5)
                    assert(#mgr._task_queue==0,'upstream should drop the past task')
                    before=p.stats.cycles;guard=find(app.kindle.check);ui.tasks={};now=now+1;guard.fn()
                    for _,t in ipairs(ui.tasks)do if t.delay==0 then t.fn()end end
                    assert(p.stats.cycles==before+1 and #mgr._task_queue==1,'dropped alarm not repaired')
                    -- 5. stop: no guard, no alarm.
                    app:stop('test')
                    assert(not find(app.kindle.check) and not mgr.rtc:isWakeupAlarmScheduled())
                    os.time=real
                ''')

    def test_04_kindle_without_koreader_screensaver_is_static_and_says_so(self):
        r=self.runtime();g=r.lua.globals();g.model='KindleVoyage';g.screensaver_support=False
        r.lua.execute(KINDLE_SETUP)
        app=r.app();g.app=app
        r.lua.execute(r'''
            assert(app.device.wakeup_mgr==nil)
            local caps=load_module('power/capabilities').detect(app.device)
            assert(caps.kind=='none' and not caps.available)
            local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
            assert(not app.scheduler.active and app.paused_warning=='RTC INDISPONIBLE / HEURE FIGÉE')
            app:stop()
        ''')

if __name__=='__main__':unittest.main()
