"""A short mem return after each clock tick used to add a 15s awake guard.
Execute native KOReader checks and failure budgets; no physical energy model.
"""
from runtime import Runtime
from test_power_efficiency import NATIVE_POWER,START
import unittest

class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua;self.lua.execute(NATIVE_POWER+START)
    def tearDown(self):self.r.close()
    def test_long_reported_refusal_uses_native_flag_instead_of_one_second_threshold(self):
        self.lua.execute('''
            faults_per_cycle=1;fault_return_duration=4.46;d:suspend();step_cycle();ui:runNext()
            assert(flag==0 and app.kobo.last_guard.delay_s==1)
            assert(app.kobo.last_short_return.native_rejected and app.kobo.short_returns==1)
            assert(app.kobo.last_short_return.duration_s>4)
        ''')
    def test_01_short_return_retries_native_check_after_one_second(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle();ui:runNext()
            assert(app.kobo.direct_disabled and app.kobo.direct_fallbacks==1)
            assert(app.kobo.retry_count==1 and app.kobo.last_guard.delay_s==1)
            assert(d.unexpected_wakeup_count==1,'failure must not be hidden')
            assert(#ui.tasks==1 and ui.tasks[1].fn==d.checkUnexpectedWakeup and ui.tasks[1].delay==1)
            ui:runNext();assert(ui.tasks[1].fn==d._doSuspend and ui.tasks[1].delay==2)
            assert(not app.kobo.direct_pending,'retry must retain full native preparation')
            ui:runNext();assert(mem_calls==3 and sync_calls==3)
        ''')
    def test_02_two_short_retries_then_native_guard_without_budget_reset(self):
        self.lua.execute('''
            faults_per_cycle=100;d:suspend();step_cycle()
            ui:runNext();assert(app.kobo.last_guard.delay_s==1)
            ui:runNext();ui:runNext();assert(app.kobo.last_guard.delay_s==2)
            ui:runNext();ui:runNext()
            assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==2)
            assert(d.unexpected_wakeup_count==3 and #ui.tasks==1)
            assert(ui.tasks[1].fn==d.checkUnexpectedWakeup)
        ''')
    def test_03_successful_but_short_hardware_sleep_uses_same_bounded_recovery(self):
        self.lua.execute('''
            faults_per_cycle=1;fault_return_success=true;d:suspend();step_cycle();ui:runNext()
            assert(flag==1 and app.kobo.retry_count==1)
            assert(math.abs(app.kobo.last_short_return.duration_s-.462)<.001)
            assert(math.abs(app.kobo.last_short_return.kernel_sleep_s-.1)<.001)
        ''')
    def test_04_user_resume_cancels_short_guard_and_stops_session(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle();ui:runNext()
            assert(app.kobo.retry_count==1);local calls=mem_calls
            d:resume();app:resume()
            assert(not app.scheduler.active and not app.kobo.return_cycle)
            for _,task in ipairs(ui.tasks)do assert(task.fn~=d.checkUnexpectedWakeup and task.fn~=d._doSuspend)end
            assert(mem_calls==calls)
        ''')
    def test_05_foreign_alarm_and_grace_keep_native_wait(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle()
            app.session.foreign_grace_until=os.time()+30
            ui:runNext();assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==0)
        ''')
    def test_06_foreign_request_revokes_retry_window(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle();assert(app.kobo.return_cycle)
            d:rescheduleSuspend(.3);assert(not app.kobo.return_cycle)
            ui:runNext();ui:runNext()
            assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==0)
        ''')
    def test_07_first_suspend_failure_is_not_accelerated(self):
        self.lua.execute('''
            fail_mem=true;d:suspend();ui:runNext()
            assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==0)
        ''')
    def test_08_missing_idle_evidence_keeps_native_guard(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle()
            local device=require('device');function device:getPowerDevice()return nil end
            for i=1,3 do ui:runNext()end
            assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==0)
        ''')
    def test_09_failed_mem_time_is_not_counted_as_verified_sleep(self):
        self.lua.execute('''
            fail_mem=true;d:suspend();ui:runNext()
            local data=app.kobo.measure:update()
            assert(data.sleep_s>.049 and data.sleep_s<.051,'native write includes failure latency')
            assert(data.verified_complete and data.verified_sleep_s<.001)
            assert(data.verified_sleep_percent==0)
        ''')
    def test_10_no_clock_pair_never_invents_verified_sleep(self):
        self.lua.execute('''
            require('ui/time').boottime=function()return 0 end
            d:suspend();step_cycle();local data=app.kobo.measure:update()
            assert(not data.verified_complete and data.verified_sleep_percent==nil)
        ''')
    def test_11_repeated_failures_still_reach_native_stop_limit(self):
        self.lua.execute('''
            faults_per_cycle=100;d:suspend();step_cycle()
            for i=1,100 do if failure_limited then break end;assert(ui:runNext())end
            assert(failure_limited and not app.scheduler.active)
            assert(d.unexpected_wakeup_count>20)
            assert(app.kobo.retry_count<=2*app.scheduler.stats.cycles)
        ''')
    def test_12_controlled_recurrent_failure_matches_low_sleep_ratio(self):
        results=[]
        for enabled in [False,True]:
            r=Runtime()
            try:
                r.lua.execute(NATIVE_POWER+START)
                if not enabled:r.lua.execute('app.kobo.retryEligible=function()return false end')
                r.lua.execute('''
                    faults_per_cycle=1;d:suspend()
                    for i=1,90 do step_cycle()end
                    data=app.kobo.measure:update()
                    assert(app.kobo.direct_used==1 and app.kobo.direct_fallbacks==1)
                    assert(app.scheduler.active and #d.wakeup_mgr._task_queue==1)
                    assert(#data.attempt_samples==120 and data.verified_complete)
                ''')
                data=r.lua.globals().data
                results.append((data.sleep_percent,data.verified_sleep_percent,r.lua.globals().app.kobo.retry_count))
            finally:r.close()
        self.assertTrue(65<results[0][0]<69,results)
        self.assertTrue(89<results[1][0]<93,results)
        self.assertGreater(results[1][1]-results[0][1],20,results)
        self.assertEqual(results[1][2],89)
    def test_13_expired_window_does_not_accelerate_an_unrelated_late_return(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle();clock_s=clock_s+20
            ui:runNext();assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==0)
        ''')
    def test_14_foreign_earliest_task_keeps_native_processing(self):
        self.lua.execute('''
            faults_per_cycle=1;d:suspend();step_cycle()
            d.wakeup_mgr:addTask(5,function()foreign_called=true end)
            ui:runNext();assert(app.kobo.last_guard.delay_s==15 and app.kobo.retry_count==0)
        ''')

if __name__=='__main__':unittest.main(verbosity=2)
