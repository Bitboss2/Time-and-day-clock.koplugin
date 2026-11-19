"""Native minute standby, including the timer behavior missed by beta 8.
Clock/RTC/driver stubs are not an electrical or booted-kernel model.
"""
import json,unittest
from runtime import Runtime,ROOT
from test_power_efficiency import NATIVE_POWER,START

SETUP=r'''
simulate_pmic=true;pmic_timer_pauses=true;standby_calls=0;pmic_ready_at=0;kernel_log='boot\n'
d.standby=test_native_standby;d.standby_state='standby'
d.total_standby_time=0;d.last_standby_time=0
function d:canStandby()return true end
function d:performanceCPUGovernor()governor='performance'end
function d:defaultCPUGovernor()governor='interactive'end
function ui:tickAfterNext(fn,...)self:scheduleIn(.01,fn,...)end
local e=load_module('power/evidence')
e.identity=function()return {kernel='Linux version 3.0.35+ test kernel'}end
e.capture=function()return {available=true,text=kernel_log}end
'''

class SettleTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua;self.lua.execute(NATIVE_POWER+SETUP+START)
    def tearDown(self):self.r.close()
    def test_fresh_fp_evidence_sleeps_until_regular_minute_without_mem_handoff(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext()
            assert(app.kobo.settle.confirmed and app.kobo.last_guard.kind=='standby_minute')
            assert(flag==0);local calls=mem_calls;step_cycle()
            assert(standby_calls==1 and mem_calls==calls)
            assert(app.kobo.settle.data.cycles==1 and app.kobo.settle.data.samples[1].kernel_sleep_s>50)
            assert(#d.wakeup_mgr._task_queue==1 and app.kobo.settle.data.auxiliary_alarms==0)
            assert(not app.kobo.settle.disabled)
        ''')
    def test_many_minutes_without_more_deep_failures_and_foreign_tasks_preserved(self):
        self.lua.execute('''
            d.wakeup_mgr:addTask(3600,function()foreign_called=true end)
            d:suspend();for i=1,8 do step_cycle()end
            assert(standby_calls==7 and mem_calls==2 and app.kobo.short_returns==1)
            assert(not foreign_called and #d.wakeup_mgr._task_queue==2)
            assert(d.unexpected_wakeup_count<=1 and governor=='interactive')
        ''')
    def test_failed_standby_disables_new_mode_and_preserves_native_fallback(self):
        self.lua.execute('''
            fail_standby=true;d:suspend();for i=1,4 do step_cycle()end
            assert(standby_calls==1 and app.kobo.settle.disabled and app.scheduler.active)
            assert(app.kobo.settle.data.failures==1)
            assert(app.kobo.settle.data.kernel_failure.available)
        ''')
    def test_user_resume_during_standby_cancels_followup(self):
        self.lua.execute('''
            interrupt_standby=true;d:suspend();step_cycle();ui:runNext();ui:runNext()
            local calls=mem_calls;ui:runNext()
            assert(not app.session and not app.scheduler.active and mem_calls==calls)
            assert(flag==0 and #d.wakeup_mgr._task_queue==0)
            for _,t in ipairs(ui.tasks)do assert(t.fn~=d.checkUnexpectedWakeup and t.fn~=d._doSuspend)end
        ''')
    def test_user_resume_before_scheduled_standby_cancels_it(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext();assert(app.kobo.settle.pending)
            d:resume();app:resume();assert(not app.kobo.settle.pending and standby_calls==0)
        ''')
    def test_foreign_suspend_request_revokes_standby_lease(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext();d:rescheduleSuspend(.1);ui:runNext()
            assert(not app.kobo.return_cycle and standby_calls==0)
        ''')
    def test_foreign_earlier_alarm_uses_native_path(self):
        self.lua.execute('''
            d:suspend();step_cycle();d.wakeup_mgr:addTask(5,function()end);ui:runNext()
            assert(not app.kobo.settle.pending and standby_calls==0)
        ''')
    def test_charge_change_revalidated_before_hardware_entry(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext();d:getPowerDevice().charging=true;ui:runNext()
            assert(standby_calls==0 and app.kobo.settle.data.cancelled==1)
        ''')
    def test_unavailable_standby_retains_native_recovery(self):
        self.lua.execute('''
            function d:canStandby()return false end
            d:suspend();step_cycle();ui:runNext()
            assert(not app.kobo.settle.pending and app.kobo.last_guard.delay_s==1)
        ''')
    def test_wrong_kernel_does_not_enable_mode(self):
        self.lua.execute('''
            app.kobo.kernel_identity.kernel='Linux version 4.1.15'
            d:suspend();step_cycle();ui:runNext();assert(not app.kobo.settle.confirmed)
        ''')
    def test_old_unverified_kernel_text_cannot_enable_mode(self):
        self.lua.execute('''
            load_module('power/evidence').since=function()return {available=true,delta_verified=false,
                text='fp9928_suspend():waiting for VEE stable'}end
            d:suspend();step_cycle();ui:runNext();assert(not app.kobo.settle.confirmed)
        ''')
    def test_native_standby_exception_restores_governor_and_native_guard(self):
        self.lua.execute('''
            function d:standby()self:performanceCPUGovernor();error('native standby failed')end
            d:suspend();step_cycle();ui:runNext();ui:runNext()
            assert(app.kobo.settle.disabled and #d.wakeup_mgr._task_queue==1)
            ui:runNext();assert(governor=='interactive')
        ''')
    def test_sleep_is_counted_once_and_frozen_on_exit(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext();ui:runNext()
            local data=app.kobo.measure:update();local count=data.verified_sleep_s
            assert(data.standby_verified_sleep_s>50)
            app.kobo.measure:update();assert(data.verified_sleep_s==count)
            assert(math.abs(data.awake_s-data.verified_awake_s)<.001)
            app:stop();local elapsed=data.elapsed_s;clock_s=clock_s+1000
            assert(app.kobo.measure:update().elapsed_s==elapsed)
        ''')
    def test_short_successful_sleep_has_bounded_reentries_then_fallback(self):
        self.lua.execute('''
            early_standby_sleep=.6;d:suspend();step_cycle();ui:runNext()
            for i=1,8 do if app.kobo.settle.disabled then break end;ui:runNext()end
            assert(standby_calls==3 and app.kobo.settle.disabled and app.kobo.settle.data.early_wakes==2)
            assert(d.unexpected_wakeup_count>=3)
        ''')
    def test_missing_boot_mono_pair_prevents_new_mode(self):
        self.lua.execute('''
            require('ui/time').boottime=function()return 0 end
            d:suspend();step_cycle();ui:runNext()
            assert(app.kobo.settle.confirmed and not app.kobo.settle.pending)
        ''')
    def test_standby_uses_existing_alarm_without_extra_rtc_writes(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext()
            local count=0;local original=d.wakeup_mgr.setWakeupAlarm
            d.wakeup_mgr.setWakeupAlarm=function(self,...)count=count+1;return original(self,...)end
            ui:runNext();assert(standby_calls==1 and count==0)
            assert(#d.wakeup_mgr._task_queue==1)
        ''')
    def test_native_failure_limit_survives_fallback(self):
        self.lua.execute('''
            fail_standby=true;d:suspend();step_cycle();ui:runNext();ui:runNext();fail_mem=true
            for i=1,120 do if failure_limited then break end;assert(ui:runNext())end
            assert(failure_limited and not app.scheduler.active and d.unexpected_wakeup_count>20)
        ''')
    def test_fresh_session_resets_metrics_rtc_and_mode_counts(self):
        self.lua.execute('''
            d:suspend();for i=1,5 do step_cycle()end
            assert(app.scheduler.stats.cycles==5 and app.kobo.settle.data.cycles==4)
            app.metrics.refreshes=999;d:resume();app:resume()
            local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
            assert(app.scheduler.stats.cycles==0 and app.scheduler.stats.dispatches==0)
            assert(app.kobo.accelerations==0 and app.kobo.settle.data.cycles==0)
            assert(not app.metrics.refreshes or app.metrics.refreshes<=1)
        ''')
    def test_deep_timer_does_not_advance_while_standby_sleeps(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext()
            local remaining=pmic_ready_at-(clock_s-sim_suspend_s)
            ui:runNext();local after=pmic_ready_at-(clock_s-sim_suspend_s)
            assert(remaining-after<1 and sim_suspend_s>100)
            assert(app.kobo.settle.data.cycles==1 and not app.kobo.settle.disabled)
        ''')
    def test_mode_does_not_depend_on_whether_driver_clock_advances(self):
        self.lua.execute('''
            pmic_timer_pauses=false;d:suspend();for i=1,8 do step_cycle()end
            assert(mem_calls==2 and standby_calls==7 and not app.kobo.settle.disabled)
        ''')
    def test_export_after_stop_keeps_actual_session_interval(self):
        self.lua.execute('''
            d:suspend();step_cycle();local start=app.session.started
            app:stop('test stop');local ended=app.last_session.ended;clock_s=clock_s+120
            local report=load_module('power/report').make(app,false)
            assert(report.session.started==start and report.session.ended==ended)
            assert(report.session.end_reason=='test stop')
        ''')
    def test_output_settling_does_not_depend_on_boottime_deadlines(self):
        self.lua.execute('''
            d:suspend();step_cycle();ui:runNext();step_cycle()
            assert(app.kobo.settle.pending and app.kobo.settle:delay()==1)
            require('ui/time').boottime_or_realtime=function()return require('ui/time').s(clock_s+4.294967296)end
            assert(app.kobo.settle:delay()==1)
            app.settings.data.wake_margin=2;assert(app.kobo.settle:delay()==2)
        ''')
    def test_native_hook_resume_cannot_schedule_a_sleep_after_return(self):
        self.lua.execute('''
            local original=d.standby
            d.standby=function(self)original(self);self:resume();app:resume()end
            d:suspend();step_cycle();ui:runNext();ui:runNext()
            assert(not app.session and not app.scheduler.active)
            for _,task in ipairs(ui.tasks)do assert(task.fn~=d.checkUnexpectedWakeup and task.fn~=d.suspend)end
        ''')
    def test_foreign_request_during_native_hook_keeps_its_schedule(self):
        self.lua.execute('''
            local original=d.standby
            d.standby=function(self)original(self);self:rescheduleSuspend(.5)end
            d:suspend();step_cycle();ui:runNext();ui:runNext()
            local found=false
            for _,task in ipairs(ui.tasks)do
                assert(task.fn~=d.checkUnexpectedWakeup)
                if task.fn==d.suspend and task.delay==.5 then found=true end
            end
            assert(found and app.kobo.settle.data.cancelled==1)
        ''')

class AlarmTests(unittest.TestCase):
    def test_single_programming_and_refusal_detection(self):
        r=Runtime()
        try:r.lua.execute('''
            local a=load_module('power/alarm');local mgr=require('device').wakeup_mgr
            local original=mgr.setWakeupAlarm;local count=0
            mgr.setWakeupAlarm=function(self,...)count=count+1;return original(self,...)end
            local cb=function()end;assert(a.add(mgr,60,cb));assert(count==1);mgr:removeTasks(nil,cb)
            local hook=function()return false end;mgr.setWakeupAlarm=hook
            assert(not a.add(mgr,60,cb));assert(mgr.setWakeupAlarm==hook)
        ''')
        finally:r.close()
    def test_alarm_exception_restores_existing_hook(self):
        r=Runtime()
        try:r.lua.execute('''
            local a=load_module('power/alarm');local mgr=require('device').wakeup_mgr
            local hook=function()error('ioctl failed')end;mgr.setWakeupAlarm=hook
            assert(not a.add(mgr,60,function()end));assert(mgr.setWakeupAlarm==hook)
        ''')
        finally:r.close()

def compare_pmic(cycles=240):
    rows=[]
    for enabled in [False,True]:
        r=Runtime()
        try:
            r.lua.execute(NATIVE_POWER+SETUP+START)
            if not enabled:r.lua.execute('app.kobo.settle.learn=function()end')
            r.lua.execute('''
                screen_latency=.6085;app.settings.data.wake_margin=.1
                app.clock.update=function()clock_s=clock_s+.007 end
                os.execute=function(command)assert(command=='sync');sync_calls=sync_calls+1;clock_s=clock_s+.1;return 0 end
                d:suspend()
            ''')
            r.lua.execute(f'for i=1,{cycles} do step_cycle()end;results=app.kobo.measure:update()')
            g=r.lua.globals();d=r.to_python(g.results)
            rows.append({'minute_standby':enabled,'elapsed_s':d['elapsed_s'],'kernel_clock_sleep_percent':d['verified_sleep_percent'],
                'awake_s':d['verified_awake_s'],'mem_calls':g.mem_calls,'short_returns':g.app.kobo.short_returns,
                'standby_calls':g.standby_calls,'sync_calls':g.sync_calls})
            assert g.app.scheduler.active and len(g.d.wakeup_mgr._task_queue)==1
            assert len(g.app.kobo.measure.data.attempt_samples)<=120 and len(g.app.kobo.settle.data.samples)<=12
        finally:r.close()
    return {'cycles':cycles,'rows':rows,'hardware_measured':False,'energy_validated':False,
        'assumptions':{'driver_clock':'active time; paused in system standby','epdc_and_vee_s':7,
            'screen_wait_s':.6085,'wake_margin_s':.1,'render_s':.007,'sync_s':.1,'refusal_s':.2,
            'successful_kernel_active_cost_s':0,'native_standby_pre_delay_s':.09},
        'warning':'Native KOReader functions, simulated peripherals and clock domains; no electrical model.'}

class ComparisonTests(unittest.TestCase):
    def test_archived_beta8_replays_observed_one_bridge_then_fallback(self):
        fixture=json.loads((ROOT/'tests/fixtures/beta8_power.json').read_text())
        r=Runtime()
        try:
            r.g.reference_modules=r.to_lua(fixture['modules'])
            r.lua.execute('''
                local base=load_module;local cache={}
                function load_module(name)
                    if reference_modules[name]then
                        if not cache[name]then cache[name]=assert(loadstring(reference_modules[name]))(load_module)end
                        return cache[name]
                    end
                    return base(name)
                end
            ''')
            r.lua.execute(NATIVE_POWER+SETUP+START)
            r.lua.execute('d:suspend();for i=1,60 do step_cycle()end')
            g=r.lua.globals();s=r.to_python(g.app.kobo.settle.data)
            self.assertEqual(g.standby_calls,1)
            self.assertTrue(g.app.kobo.settle.disabled)
            self.assertEqual(s['reason'],'Veille profonde refusée après décharge')
            (ROOT/'atelierclock.koplugin/docs/BETA8_REPLAY.json').write_text(json.dumps({
                'reference_version':fixture['version'],'reference_archive_sha256':fixture['archive_sha256'],
                'controlled_minutes':60,'standby_calls':g.standby_calls,'disabled':True,'reason':s['reason'],
                'driver_timer':'active time, stopped in system standby','hardware_measured':False,
                'matches_observed_symptom':'one bridge then same deep-suspend refusal fallback'},indent=2)+'\n')
        finally:r.close()
    def test_240_minutes_with_frozen_driver_timer_avoids_deep_retry_loop(self):
        report=compare_pmic();old,new=report['rows']
        self.assertEqual(new['standby_calls'],239)
        self.assertEqual(new['mem_calls'],2)
        self.assertLess(new['awake_s'],old['awake_s']*.25)
        self.assertGreater(new['kernel_clock_sleep_percent'],95)
        (ROOT/'atelierclock.koplugin/docs/RTC_STANDBY_SIMULATION.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':unittest.main(verbosity=2)
