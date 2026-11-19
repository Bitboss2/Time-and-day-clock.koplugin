"""Explicit scheduler ownership, read-only kernel evidence and one exit write.
No physical Kobo kernel, power supply or energy result is simulated here.
"""
from pathlib import Path
import json,unittest
from runtime import Runtime, ROOT
from test_power_efficiency import NATIVE_POWER,START

class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua;self.lua.execute(NATIVE_POWER+START)
    def tearDown(self):self.r.close()
    def test_owned_task_survives_early_clock_read(self):
        self.lua.execute('''
            d:suspend();step_cycle();app.settings.data.reuse_suspend=false
            app.kobo:sleep(app.scheduler.generation,true)
            local t=table.remove(ui.tasks,1);assert(t.fn==d.suspend)
            clock_s=t.due-.0005;t.fn(unpack(t.args))
            assert(app.kobo.return_cycle,'0.5ms clock discrepancy must not revoke ownership')
            assert(ui.tasks[1].fn==d._doSuspend)
        ''')
    def test_delayed_owned_task_preserves_window_and_native_signature(self):
        self.lua.execute('''
            d:suspend();step_cycle();app.settings.data.reuse_suspend=false
            local original=app.kobo.original_suspend
            app.kobo.original_suspend=function(device,...)
                assert(select('#',...)==0,'private marker must not reach native code')
                return original(device,...)
            end
            app.kobo:sleep(app.scheduler.generation,true)
            local t=table.remove(ui.tasks,1);clock_s=t.due+1.25;t.fn(unpack(t.args))
            assert(app.kobo.return_cycle)
        ''')
    def test_foreign_direct_suspend_revokes_owned_window(self):
        self.lua.execute('''
            d:suspend();step_cycle();assert(app.kobo.return_cycle)
            d:suspend();assert(not app.kobo.return_cycle)
        ''')
    def test_native_resume_still_cancels_owned_callback(self):
        self.lua.execute('''
            app.settings.data.reuse_suspend=false;d:suspend();step_cycle()
            assert(#ui.tasks==1 and ui.tasks[1].fn==d.suspend)
            d:resume();app:resume()
            for _,t in ipairs(ui.tasks)do assert(t.fn~=d.suspend and t.fn~=d._doSuspend)end
        ''')
    def test_kernel_capture_stops_after_three_failures_and_exit_persists(self):
        self.lua.execute('''
            local e=load_module('power/evidence');captures=0
            e.capture=function()captures=captures+1;return {available=true,text='failure '..captures}end
            faults_per_cycle=1;d:suspend();for i=1,5 do step_cycle()end
            assert(captures==3,'kernel capture must stop after the first three returns')
            assert(not load_module('core/util').read(app.data_dir..'/last-session.json'))
            assert(app.kobo.kernel_first.text=='failure 1')
            app:stop('test exit');assert(captures==3)
            -- A repeated stop must not write the same session again.
            local u=load_module('core/util');u.write=function()error('duplicate session write')end
            app:stop('again')
        ''')
        p=Path(self.lua.globals().app.data_dir,'last-session.json')
        data=json.loads(p.read_text())
        self.assertEqual(data['version'],(ROOT/'atelierclock.koplugin/core/version.lua').read_text().split('"')[1])
        self.assertEqual(data['session']['end_reason'],'test exit')
        self.assertEqual(data['power']['kernel_first_return']['text'],'failure 1')
        self.assertEqual(data['power']['last_short_return']['retry_reason'],'clock_owned')
        self.assertFalse(data['energy_target']['hardware_verified'])
    def test_report_write_failure_does_not_break_user_resume(self):
        self.lua.execute('''
            local u=load_module('core/util');u.write=function()return nil,'disk full'end
            d:resume();app:resume()
            assert(not app.session and not app.scheduler.active)
            assert(app.notice:find('disk full',1,true))
        ''')

class KernelEvidenceTests(unittest.TestCase):
    def setUp(self):self.r=Runtime();self.lua=self.r.lua
    def tearDown(self):self.r.close()
    def test_read_all_is_bounded_and_never_clears_ring(self):
        self.lua.execute('''
            local original=package.loaded.ffi;local count=0
            package.loaded.ffi={cdef=function()end,new=function(kind,size)assert(size==16384);return {}end,
                C={klogctl=function(action,buffer,size)assert(action==3 and size==16384);count=count+1;return 6 end},
                string=function(buffer,size)assert(size==6);return 'kernel'end}
            local e=load_module('power/evidence');local d={isKobo=function()return true end}
            local r=e.capture(d);assert(r.available and r.text=='kernel'and count==1)
            package.loaded.ffi=original
        ''')
    def test_missing_or_denied_kernel_api_is_not_fatal(self):
        self.lua.execute('''
            local original=package.loaded.ffi;local e=load_module('power/evidence')
            local d={isKobo=function()return true end}
            package.loaded.ffi={cdef=function()end,new=function()return {}end,
                C={klogctl=function()return -1 end},errno=function()return 1 end}
            local r=e.capture(d);assert(not r.available and r.errno==1)
            package.loaded.ffi={cdef=function()error('no libc symbol')end}
            r=e.capture(d);assert(not r.available and r.reason=='kernel_log_api_unavailable')
            package.loaded.ffi=original
        ''')
    def test_non_kobo_does_not_touch_kernel(self):
        self.lua.execute('''
            local e=load_module('power/evidence');local d={isKobo=function()return false end}
            assert(e.capture(d).reason=='not_kobo'and e.identity(d).reason=='not_kobo')
        ''')
    def test_ring_append_rollover_and_unverifiable_overlap(self):
        self.lua.execute('''
            local e=load_module('power/evidence')
            local function s(text)return {available=true,text=text}end
            local r=e.since(s('before'),s('beforeafter'))
            assert(r.delta_verified and r.text=='after')
            local a=string.rep('a',600)..string.rep('b',600)
            r=e.since(s(a),s(a:sub(501)..'new'))
            assert(r.delta_verified and r.text=='new')
            r=e.since(s(a),s('unrelated'..string.rep('b',512)..'new'))
            assert(not r.delta_verified,'a matching fragment alone is not verified overlap')
            assert(not e.since(s(a),{available=false,errno=1}).available)
        ''')
    def test_report_preserves_rename_errors(self):
        self.lua.execute(NATIVE_POWER+START+'''
            local rename=os.rename;os.rename=function()return nil,'rename denied'end
            local ok,err=load_module('power/report').write(app,'diagnostic.json',false)
            assert(not ok and err=='rename denied');os.rename=rename
        ''')

if __name__=='__main__':unittest.main(verbosity=2)
