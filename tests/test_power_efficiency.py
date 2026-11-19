"""Minute power regressions with actual native suspend/resume code and FTS units.
The mem syscall and EPDC latency are simulated. This is not an energy reading.
"""
from runtime import Runtime,ROOT
from pathlib import Path
import json,unittest

NATIVE_POWER=r'''
local T=require('ui/time')
local real_time=os.time
clock_s=1800000000
sim_suspend_s=0
os.time=function(arg)if arg then return real_time(arg)end;return math.floor(clock_s)end
T.boottime_or_realtime=function()return T.s(clock_s)end
T.boottime_or_realtime_coarse=T.boottime_or_realtime
T.boottime=T.boottime_or_realtime
T.monotonic=function()return T.s(clock_s-sim_suspend_s)end
local U=load_module('core/util');local original_read=U.read
flag=0;flag_unreadable=false
U.read=function(path,limit)
 if path=='/sys/power/state-extended'then return not flag_unreadable and tostring(flag)..'\n'or nil end
 return original_read(path,limit)
end
ui=require('ui/uimanager');d=require('device');ui.tasks={}
function ui:scheduleIn(delay,fn,...)
 self.tasks[#self.tasks+1]={delay=delay,due=clock_s+delay,fn=fn,args={...}}
end
function ui:runNext()
 if #self.tasks==0 then return end
 local index=1;for i=2,#self.tasks do if self.tasks[i].due<self.tasks[index].due then index=i end end
 local task=table.remove(self.tasks,index);clock_s=math.max(clock_s,task.due);task.fn(unpack(task.args));return task
end
screen_latency=.12;screen_finished=false
function ui:forceRePaint()screen_finished=false end
function ui:waitForVSync()
 clock_s=clock_s+screen_latency;screen_finished=true
 if simulate_pmic then pmic_ready_at=clock_s-(pmic_timer_pauses and sim_suspend_s or 0)+7 end
end
mem_calls=0;sync_calls=0;flag_writes=0;fail_mem=false;mem_times={}
faults_per_cycle=0;fault_cycle=-1;fault_attempts=0;fault_return_success=false
local ffiUtil={}
function ffiUtil.writeToSysfs(value,path)
 if path=='/sys/power/state-extended'then flag=tonumber(value);flag_writes=flag_writes+1;return true end
 if simulate_pmic and path=='/sys/power/state'and value=='standby'then
  assert(flag==0,'bridge must not bypass the deep-suspend flag')
  standby_calls=standby_calls+1
  if fail_standby then clock_s=clock_s+.1;return nil end
  if early_standby_sleep then
   sim_suspend_s=sim_suspend_s+early_standby_sleep;clock_s=clock_s+early_standby_sleep;return true
  end
  local epoch=d.wakeup_mgr.rtc.epoch;assert(epoch and epoch>clock_s,'bridge alarm not armed')
  if interrupt_standby then
   clock_s=clock_s+.1
   ui:scheduleIn(0,function()d:resume();app:resume()end);return true
  end
  local interval=epoch-clock_s;sim_suspend_s=sim_suspend_s+interval;clock_s=epoch;return true
 end
 assert(path=='/sys/power/state'and value=='mem','unexpected kernel access')
 mem_calls=mem_calls+1;mem_times[#mem_times+1]=clock_s
 if simulate_pmic and clock_s-(pmic_timer_pauses and sim_suspend_s or 0)<(pmic_ready_at or 0)then
  kernel_log=kernel_log..'fp9928_suspend():waiting for VEE stable ,please retry suspend later !!!\n'
  clock_s=clock_s+.2;return nil
 end
 if fail_after_bridge and standby_calls>0 then clock_s=clock_s+.2;return nil end
 if fail_mem then clock_s=clock_s+.05;return nil end
 if faults_per_cycle>0 and app and app.scheduler.stats.cycles>0 then
  if fault_cycle~=app.scheduler.stats.cycles then fault_cycle=app.scheduler.stats.cycles;fault_attempts=0 end
  if fault_attempts<faults_per_cycle then
   fault_attempts=fault_attempts+1;clock_s=clock_s+(fault_return_duration or .462)
   if fault_return_success then sim_suspend_s=sim_suspend_s+.1;return true end
   return nil
  end
 end
 local epoch=d.wakeup_mgr.rtc.epoch
 assert(epoch and epoch>clock_s,'alarm expired before suspend')
 sim_suspend_s=sim_suspend_s+epoch-clock_s;clock_s=epoch;return true
end
function ffiUtil.usleep(us)clock_s=clock_s+us/1000000 end
os.execute=function(command)assert(command=='sync');sync_calls=sync_calls+1;clock_s=clock_s+.015;return 0 end
package.preload['ui/event']=function()return {new=function(_,name)return {name=name}end}end
function ui:broadcastEvent(event)if event.name=='UnexpectedWakeupLimit'then app:stop('native failure limit');failure_limited=true end end
local src=U.read(upstream..'/device.lua')
local begin=assert(src:find('function Kobo:rescheduleSuspend',1,true))
local finish=assert(src:find('function Kobo:usbPlugOut',begin,true))
local make=assert(loadstring("local ffiUtil,time=...;local Kobo={};local UIManager=require('ui/uimanager');local logger=require('logger');"..src:sub(begin,finish-1)..';return Kobo'))
local native=make(ffiUtil,T)
for _,name in ipairs({'rescheduleSuspend','scheduleUnexpectedWakeupGuard','checkUnexpectedWakeup','suspend','_doSuspend','resume'})do d[name]=native[name]end
-- Loaded only by the FP9928 tests. Other scenarios keep standby unavailable.
test_native_standby=native.standby
function d:isMTK()return false end
function d:hasReliableMxcWaitFor()return true end
function d:setupChargingLED()end
d.total_suspend_time=0;d.unexpected_wakeup_count=0
'''

START=r'''
app=load_module('app').new(plugin_root,load_module)
app.settings.data.fast_rtc=true;app.settings.data.interval=60
local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
function step_cycle()
 local target=app.scheduler.stats.cycles+1
 for _=1,20 do
  assert(ui:runNext(),'lost UI task')
  if app.scheduler.stats.cycles>=target then return end
 end
 error('cycle did not finish')
end
'''

class EfficiencyTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua;self.lua.execute(NATIVE_POWER+START);self.app=self.lua.globals().app
    def tearDown(self):self.r.close()
    def test_01_photo_duration_is_microseconds_not_seconds(self):
        self.lua.execute('''
            local M=load_module('power/measure')
            assert(math.abs(M.seconds(2787663)-2.787663)<.000001)
            assert(M.seconds(nil)==nil and M.seconds(0/0)==nil)
        ''')
    def test_02_short_sleep_in_real_units_does_not_reset_failure_budget(self):
        self.lua.execute('''
            d.last_suspend_time=require('ui/time').s(.05);d.total_suspend_time=d.last_suspend_time
            d.unexpected_wakeup_count=12;flag=1
            app.kobo:sleep(app.scheduler.generation,true)
            assert(d.unexpected_wakeup_count==12 and not app.kobo.direct_pending)
        ''')
    def test_03_first_suspend_still_uses_native_preparation(self):
        self.lua.execute('''
            local at=clock_s;d:suspend();assert(flag==1 and #ui.tasks==1)
            assert(ui.tasks[1].fn==d._doSuspend and ui.tasks[1].delay==2)
            ui:runNext();assert(mem_times[1]>=at+2 and sync_calls==1)
        ''')
    def test_04_owned_wakeup_reuses_preparation_after_screen_completion(self):
        self.lua.execute('''
            d:suspend();step_cycle()
            assert(screen_finished and app.kobo.direct_pending)
            assert(#ui.tasks==1 and ui.tasks[1].fn==d._doSuspend)
            ui:runNext()
            assert(app.kobo.direct_used==1 and flag_writes==1 and mem_calls==2 and sync_calls==2)
            local data=app.kobo.measure:update()
            assert(math.abs(data.wake_to_suspend_s-.62)<.001)
            assert(data.last_path=='reuse'and data.samples_count==2)
        ''')
    def test_05_disabling_reuse_preserves_two_second_native_preparation(self):
        self.lua.execute('''
            app.settings.data.reuse_suspend=false;d:suspend();step_cycle()
            assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
            ui:runNext();ui:runNext()
            local data=app.kobo.measure:update()
            assert(flag_writes==2 and mem_calls==2 and sync_calls==2)
            assert(math.abs(data.wake_to_suspend_s-2.62)<.001 and data.last_path=='native')
        ''')
    def test_06_unreadable_or_cleared_flag_uses_native_path(self):
        self.lua.execute('''
            flag_unreadable=true;d:suspend();step_cycle()
            assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
        ''')
    def test_07_flag_revalidated_at_execution_not_only_scheduling(self):
        self.lua.execute('''
            d:suspend();step_cycle();assert(app.kobo.direct_pending)
            flag=0;ui:runNext()
            assert(mem_calls==1 and app.kobo.direct_disabled and app.kobo.direct_fallbacks==1)
            assert(ui.tasks[1].fn==d.suspend)
        ''')
    def test_08_user_resume_cancels_pending_native_callback(self):
        self.lua.execute('''
            d:suspend();step_cycle();assert(app.kobo.direct_pending)
            d:resume();app:resume()
            assert(flag==0 and not app.kobo.direct_pending and not app.scheduler.active)
            for _,task in ipairs(ui.tasks)do assert(task.fn~=d._doSuspend and task.fn~=d.suspend)end
            assert(mem_calls==1)
        ''')
    def test_09_failed_reused_sleep_disables_reuse_for_session(self):
        self.lua.execute('''
            d:suspend();step_cycle();fail_mem=true;ui:runNext()
            assert(flag==0 and app.kobo.direct_disabled and app.kobo.direct_fallbacks==1)
            assert(app.kobo.measure.data.short_sleeps==1)
            assert(d.unexpected_wakeup_count==1,'failed sleep was counted as a healthy cycle')
            fail_mem=false;ui:runNext()
            assert(not app.kobo.direct_pending)
        ''')
    def test_10_unreliable_epdc_wait_forces_native_preparation(self):
        self.lua.execute('''
            function d:hasReliableMxcWaitFor()return false end
            d:suspend();step_cycle();assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
        ''')
    def test_11_missing_screen_completion_api_forces_native_preparation(self):
        self.lua.execute('''
            ui.waitForVSync=nil;d:suspend();step_cycle()
            assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
        ''')
    def test_12_does_not_replace_another_plugin_native_suspend_hook(self):
        self.lua.execute('''
            local original=d._doSuspend;d._doSuspend=function(...)return original(...)end
            d:suspend();step_cycle();assert(not app.kobo.direct_pending)
        ''')
    def test_13_no_30_second_awake_wait_for_a_future_foreign_alarm(self):
        self.lua.execute('''
            d:suspend();ui:runNext()
            local count=0
            d.wakeup_mgr:addTask(29,function()count=count+1 end)
            ui:runNext();ui:runNext()
            assert(app.kobo.direct_pending and #ui.tasks==1 and ui.tasks[1].fn==d._doSuspend)
            assert(d.wakeup_mgr._task_queue[1].callback~=app.scheduler.callback)
            ui:runNext();assert(mem_calls==2)
            ui:runNext();assert(count==1,'foreign callback not serviced by native code')
        ''')
    def test_14_very_close_foreign_alarm_keeps_its_processing_window(self):
        self.lua.execute('''
            d:suspend();ui:runNext();local count=0
            d.wakeup_mgr:addTask(1,function()count=count+1 end)
            ui:runNext();ui:runNext();assert(not app.kobo.direct_pending)
            ui:runNext();assert(count==1)
        ''')
    def test_15_measurement_reports_real_units_sleep_ratio_and_freezes_on_exit(self):
        self.lua.execute('''
            d:suspend();for _=1,5 do step_cycle()end
            local data=app.kobo.measure:update()
            assert(data.native_last_sleep_s>50 and data.native_last_sleep_s<61)
            assert(data.sleep_percent>90 and data.sleep_percent<100)
            assert(data.sleep_s>250 and data.sleep_s<301)
            app:stop();local elapsed=data.elapsed_s;clock_s=clock_s+3600
            assert(app.kobo.measure:update().elapsed_s==elapsed)
        ''')
    def test_16_measurements_do_not_recount_stale_native_values(self):
        self.lua.execute('''
            d:suspend();step_cycle();local data=app.kobo.measure.data
            local count=data.samples_count;local seconds=data.sleep_s
            app.kobo.measure:wake();app.kobo.measure:wake()
            assert(data.samples_count==count and data.sleep_s==seconds)
        ''')
    def test_17_json_diagnostic_contains_seconds_and_power_evidence(self):
        self.lua.execute('''
            d:suspend();step_cycle();d.last_suspend_time=2787663
            local st=load_module('ui/studio'):new{app=app};st:exportDiagnostic();st:onCloseWidget()
        ''')
        data=json.loads(Path(self.app.data_dir,'diagnostic.json').read_text())
        self.assertAlmostEqual(data['last_suspend_time_s'],2.787663,places=6)
        self.assertEqual(data['power']['timing']['unit'],'seconds')
        self.assertNotIn('last_suspend_time',data)
    def test_18_minute_refresh_does_not_consume_reader_page_refresh_counter(self):
        self.lua.execute('''
            d:suspend();step_cycle()
            local partial=false;local regions=0
            for _,entry in ipairs(ui.dirty)do
                if entry.rect then regions=regions+1;assert(entry.kind=='ui')end
            end
            assert(regions>0)
        ''')
    def test_19_native_failure_limit_remains_effective_after_fts_fix(self):
        self.lua.execute('''
            d:suspend();step_cycle();fail_mem=true
            for _=1,100 do
                if failure_limited then break end
                assert(ui:runNext())
            end
            assert(failure_limited and not app.scheduler.active)
            assert(d.unexpected_wakeup_count>20)
        ''')
    def test_21_screen_wait_error_keeps_native_fallback(self):
        self.lua.execute('''
            function ui:waitForVSync()error('EPDC wait failed')end
            d:suspend();step_cycle()
            assert(app.kobo.direct_disabled and not app.kobo.direct_pending)
            assert(ui.tasks[1].fn==d.suspend)
            assert(app.scheduler.stats.events[#app.scheduler.stats.events].kind=='screen_wait_error')
        ''')
    def test_22_known_failed_kernel_flag_prevents_budget_reset(self):
        self.lua.execute('''
            d.last_suspend_time=require('ui/time').s(5);d.total_suspend_time=d.last_suspend_time
            d.unexpected_wakeup_count=12;flag=0
            app.kobo:sleep(app.scheduler.generation,true)
            assert(d.unexpected_wakeup_count==12 and not app.kobo.direct_pending)
        ''')
    def test_26_wifi_on_uses_native_prepare_that_handles_network(self):
        self.lua.execute('''
            d:suspend();ui:runNext()
            local N=require('ui/network/manager');function N:isWifiOn()return true end
            ui:runNext();ui:runNext()
            assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
        ''')
    def test_27_charging_uses_full_native_prepare(self):
        self.lua.execute('''
            d:suspend();ui:runNext();d:getPowerDevice().charging=true
            ui:runNext();ui:runNext()
            assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
        ''')
    def test_28_network_revalidated_before_reused_mem_call(self):
        self.lua.execute('''
            d:suspend();step_cycle();assert(app.kobo.direct_pending)
            local N=require('ui/network/manager');function N:isWifiOn()return true end
            ui:runNext()
            assert(app.kobo.direct_disabled and mem_calls==1 and ui.tasks[1].fn==d.suspend)
        ''')
    def test_25_new_full_suspend_request_supersedes_pending_reuse(self):
        self.lua.execute('''
            d:suspend();step_cycle();assert(app.kobo.direct_pending)
            d:suspend();assert(not app.kobo.direct_pending)
            assert(#ui.tasks==1 and ui.tasks[1].fn==d._doSuspend and ui.tasks[1].delay==2)
            ui:runNext();assert(app.kobo.direct_used==0 and flag_writes==2)
            assert(app.kobo.measure.data.last_path=='native')
        ''')
    def test_24_explicit_driver_wait_bypass_disables_reuse(self):
        self.lua.execute('''
            G_reader_settings:saveSetting('mxcfb_bypass_wait_for',true)
            d:suspend();step_cycle();assert(not app.kobo.direct_pending and ui.tasks[1].fn==d.suspend)
        ''')
    def test_23_new_session_reenables_after_fallback_without_losing_settings(self):
        self.lua.execute('''
            app.kobo.direct_disabled=true;app:stop()
            app.session={started=os.time(),user_resumed=false};app.kobo:beginSession()
            assert(not app.kobo.direct_disabled and app.kobo.direct_used==0)
            assert(app.settings.data.interval==60 and app.settings.data.full_refresh==60)
        ''')

    def test_20_one_hundred_eighty_cycles_keep_one_owned_alarm(self):
        self.lua.execute('''
            d:suspend()
            for i=1,180 do
                step_cycle();assert(app.scheduler.active)
                assert(#d.wakeup_mgr._task_queue==1)
                assert(d.wakeup_mgr._task_queue[1].callback==app.scheduler.callback)
            end
            assert(app.kobo.direct_used==179 and flag_writes==1)
            assert(#app.kobo.measure.data.samples==120)
        ''')

if __name__=='__main__':unittest.main(verbosity=2)
