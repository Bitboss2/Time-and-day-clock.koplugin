from runtime import Runtime, ROOT, PLUGIN
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops
import io, json, os, struct, time, unittest, zipfile

OUTPUT=ROOT/'tests'/'output'
OUTPUT.mkdir(parents=True,exist_ok=True)

class AtelierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rt=Runtime();cls.lua=cls.rt.lua;cls.app=cls.rt.app();cls.lua.globals().app=cls.app
    @classmethod
    def tearDownClass(cls):cls.rt.close()
    def test_01_syntax(self):
        compile=self.lua.eval('function(p)local f,e=loadfile(p);return f~=nil,e end')
        for f in PLUGIN.rglob('*.lua'):self.assertEqual(compile(str(f)),(True,None),str(f))
    def test_02_ten_real_archives(self):
        self.assertEqual(len(self.app.faces),10)
        self.assertEqual(len(self.app.errors),0)
        for f in self.app.faces.values():
            with zipfile.ZipFile(f.path) as z:
                self.assertIsNone(z.testzip());m=json.loads(z.read('manifest.json'))
                self.assertEqual(m['id'],f.id)
                self.assertIn('textures/background.png',z.namelist())
                self.assertIn('preview.png',z.namelist())
    def test_03_settings_roundtrip_validation(self):
        self.lua.execute('''
            local S=load_module('core/settings');local U=load_module('core/util')
            local s=S.new(test_data..'/test-settings.json')
            local data=U.copy(S.defaults);data.scale=123;data.time.x=8
            assert(s:save(data));local other=S.new(s.path)
            assert(other.data.scale==123 and other.data.time.x==8)
            data.scale=0/0;data.interval=42;data.night='bad';data.time.size=999999
            local valid=S.validate(data)
            assert(valid.scale==100 and valid.interval==60 and valid.night=='follow' and valid.time.size==260)
            assert(not pcall(S.validate,{schema_version=99}))
        ''')
    def test_04_zip_path_traversal_symlink_encryption(self):
        validate=self.rt.load('packages/zip').inspect
        # Keep binary strings inside Lua to avoid Python UTF-8 conversions.
        def valid_archive(member,attr=0o100644<<16):
            stream=io.BytesIO()
            with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
                i=zipfile.ZipInfo(member);i.external_attr=attr;i.compress_type=8;z.writestr(i,b'{}')
            return stream.getvalue()
        invalid=[valid_archive('../manifest.json'),valid_archive('/manifest.json'),
                 valid_archive('x//manifest.json'),valid_archive('manifest.json',0o120777<<16),
                 b'not a zip',valid_archive('manifest.json')[:-4]]
        for i,data in enumerate(invalid):
            path=Path(self.rt.tmp.name)/f'bad-{i}.zip';path.write_bytes(data)
            self.lua.globals().bad_path=str(path)
            self.assertFalse(self.lua.eval('pcall(function()return load_module("packages/zip").inspect(load_module("core/util").read(bad_path))end)')[0])
        original=Path(self.app.faces[1].path).read_bytes()
        d=bytearray(original);d[6]|=1
        ix=d.find(b'PK\x01\x02');d[ix+8]|=1
        path=Path(self.rt.tmp.name)/'encrypted.clock';path.write_bytes(d)
        self.lua.globals().bad_path=str(path)
        self.assertFalse(self.lua.eval('pcall(function()return load_module("packages/reader").open(bad_path,app.data_dir.."/cache")end)')[0])
    def test_05_reject_malicious_manifest_and_large_image(self):
        source=ROOT/"tests/fixtures/legacy.clock"
        with zipfile.ZipFile(source) as z:base={n:z.read(n) for n in z.namelist()}
        mutations=[lambda m:m.update(schema_version=99),lambda m:m.update(id='../escape'),
                   lambda m:m['layers'].append({'id':'exec','type':'lua','text':'os.execute()'}),
                   lambda m:m['layers'][-1].update(grey='black'),lambda m:m.update(order=True),
                   lambda m:m['layers'][0].update(w=3000)]
        for i,mut in enumerate(mutations):
            m=json.loads(base['manifest.json']);mut(m);p=Path(self.rt.tmp.name)/f'manifest-{i}.clock'
            with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED) as z:
                for n,b in base.items():z.writestr(n,json.dumps(m).encode() if n=='manifest.json' else b)
            self.lua.globals().bad_path=str(p)
            self.assertFalse(self.lua.eval('pcall(function()return load_module("packages/reader").open(bad_path,app.data_dir.."/cache")end)')[0])
        # Valid envelope, deliberately oversized IHDR. Reject before decoding.
        b=bytearray(base['textures/background.png']);b[16:24]=struct.pack('>II',20000,20000)
        p=Path(self.rt.tmp.name)/'huge.clock'
        with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED) as z:
            for n,blob in base.items():z.writestr(n,b if n=='textures/background.png' else blob)
        self.lua.globals().bad_path=str(p)
        self.assertFalse(self.lua.eval('pcall(function()return load_module("packages/reader").open(bad_path,app.data_dir.."/cache")end)')[0])
    def test_06_time_boundaries(self):
        self.lua.execute('''
            local T=load_module('core/time');local s={interval=60,quiet=false}
            assert(T.next(120,s)==180 and T.next(179,s)==180)
            s.interval=300;assert(T.next(301,s)==600)
            s.interval=900;assert(T.next(1799,s)==1800)
            s.interval=0;assert(T.next(100,s)==nil)
            local x=os.time{year=2028,month=2,day=29,hour=23,min=59,sec=59}
            s.interval=60;assert(os.date('%Y-%m-%d',T.next(x,s))=='2028-03-01')
            s.quiet=true;s.quiet_start=23;s.quiet_end=7
            x=os.time{year=2026,month=12,day=31,hour=23,min=20,sec=0}
            assert(os.date('%Y-%m-%d %H:%M',T.next(x,s))=='2027-01-01 07:00')
        ''')
    def test_07_timezone_dst(self):
        self.lua.execute('''
            local winter=os.time{year=2026,month=1,day=15,hour=12,min=0,sec=0}
            -- Use known UTC epochs, independent of host timezone.
            local w=app.world
            assert(w:format(1768478400,'America/New_York')=='07:00')
            assert(w:format(1784116800,'America/New_York')=='08:00')
            assert(w:format(1784116800,'Asia/Tokyo')=='21:00')
            assert(w:format(1784116800,'unknown')=='--:--')
        ''')
    def test_08_legacy_parser_does_not_execute(self):
        self.lua.execute('''
            local L=load_module('core/legacy')
            local t=L.parse([[-- old file
              return {clock_format='24', night_mode='night', time_widget={font_size=140},
                png_overlay={enabled=true,mode='cycle',cycle_minutes=30},
                rotation={follow_koreader=false,custom_rotation=3}, analog_infos={'battery','worldclock_nyc'}}]])
            local v,report=L.convert(t,load_module('core/settings').defaults)
            assert(v.format=='24' and v.night=='dark' and v.time.size==140 and v.image_interval==30)
            assert(v.rotation=='3' and v.show_world==true and #report>0)
            assert(not pcall(L.parse,"return {x=os.execute('evil')}"))
            assert(not pcall(L.parse,'return {}; os.exit()'))
            assert(not pcall(L.parse,'return { x = function() end }'))
        ''')
    def test_09_scheduler_real_upstream_queue_10080_cycles(self):
        self.lua.execute('''
            local manager=require('device').wakeup_mgr
            manager._task_queue={}
            local ui=require('ui/uimanager');ui.tasks={}
            local real_time=os.time;local now=1800000000
            os.time=function(t)if t then return real_time(t)end;return now end
            local count=0;local slept=0
            local p=load_module('power/scheduler').new{ui=ui,mgr=manager,
                refresh=function()count=count+1 end,sleep=function()slept=slept+1 end,failed=function(e)error(e)end}
            local foreign=function()error('foreign callback must not run here')end
            manager:addTask(9999999,foreign)
            assert(p:start{interval=60,quiet=false})
            for i=1,10080 do
                assert(#manager._task_queue==2)
                now=p.stats.next
                assert(manager:wakeupAction(3))
                -- Foreign task survives the callback's post-return removal.
                assert(#manager._task_queue==1 and manager._task_queue[1].callback==foreign)
                ui:tick();assert(p.active and p.scheduled)
            end
            assert(count==10080 and slept==10080 and p.stats.errors==0)
            p:stop();assert(#manager._task_queue==1 and manager._task_queue[1].callback==foreign)
            manager:removeTasks(nil,foreign);ui.tasks={};os.time=real_time
        ''')
    def test_10_user_resume_cancels_pending_callback(self):
        self.lua.execute('''
            local ui=app.ui;ui.tasks={};local mgr=app.device.wakeup_mgr;mgr._task_queue={}
            local count=0
            local p=load_module('power/scheduler').new{ui=ui,mgr=mgr,refresh=function()count=count+1 end,sleep=function()error('slept after stop')end,failed=function()end}
            p:start{interval=60,quiet=false};mgr._task_queue[1].epoch=os.time();assert(mgr:wakeupAction(3));p:stop();ui:tick()
            assert(count==0 and #mgr._task_queue==0)
        ''')
    def test_11_native_menu_rebuild_idempotent(self):
        self.lua.execute('''
            local function items()local t={};for i=1,6 do t[i]={radio=true,callback=function()end,checked_func=function()return false end}end
                return {screensaver={sub_item_table={{sub_item_table=t}}}}end
            for i=1,50 do
                local menu=items();assert(app.integration:menu(menu));assert(app.integration:menu(menu))
                assert(#menu.screensaver.sub_item_table[1].sub_item_table==7)
            end
            G_reader_settings:saveSetting('screensaver_type','cover');app.integration:select()
            assert(G_reader_settings:readSetting('screensaver_type')=='atelierclock')
            app.integration:disable();assert(G_reader_settings:readSetting('screensaver_type')=='cover')
        ''')
    def test_12_ss_rotation_resume_cleanup(self):
        self.lua.execute('''
            app.device.wakeup_mgr._task_queue={};app.ui.tasks={}
            app.settings.data.rotation='1';app.device.screen:setRotationMode(0)
            app.integration:select();local ss=require('ui/screensaver');ss.screensaver_type='atelierclock';ss.ui={};ss.prefix=''
            ss:show();assert(app.session and app.clock and app.host and app.scheduler.active)
            assert(app.device.screen:getRotationMode()==1)
            app:resume();assert(not app.scheduler.active and not app.session)
            assert(app.device.screen:getRotationMode()==0)
            app.ui:close(app.host);assert(app.clock.closed)
            app.settings.data.rotation='follow';app.integration:disable();app.ui.tasks={}
            ss.screensaver_type='cover';ss:show();assert(ss.fallback)
        ''')
    def test_13_fast_guard_only_own_alarm(self):
        self.lua.execute('''
            app.ui.tasks={};app.device.wakeup_mgr._task_queue={};app.settings.data.fast_rtc=true
            app.session={rotation=0,started=os.time()};app.device.screen_saver_mode=true
            app.scheduler:start{interval=60,quiet=false}
            local q=app.device.wakeup_mgr._task_queue;q[1].epoch=os.time()
            app.device:scheduleUnexpectedWakeupGuard()
            assert(#app.ui.tasks==1 and app.ui.tasks[1].delay==0.2)
            app.ui.tasks={};q[1].callback=function()end
            app.device:scheduleUnexpectedWakeupGuard()
            assert(#app.ui.tasks==1 and app.ui.tasks[1].delay==15)
            q[1].callback=app.scheduler.callback;app:stop()
            app.settings.data.fast_rtc=false;app.ui.tasks={}
        ''')
    def test_14_manual_does_not_block_autosuspend(self):
        self.lua.execute('''
            app.device.screen:setRotationMode(0);local power=app.device:getPowerDevice();power:setIntensity(7)
            app.settings.data.rotation='1';app.settings.data.brightness=40
            app:launch();local clock=app.manual_clock
            assert(power.fl_intensity==40 and app.device.screen:getRotationMode()==1)
            clock:onSuspend();assert(clock.closed)
            assert(power.fl_intensity==7 and app.device.screen:getRotationMode()==0)
            app.settings.data.rotation='follow';app.settings.data.brightness=-1;app.ui.tasks={}
        ''')
    def test_15_render_all_faces_and_ui(self):
        sceneclass=self.rt.load('render/scene');U=self.rt.load('core/util')
        epoch=1793270040 # repeatable demonstration time, no time-dependent snapshots
        previews=[]
        for face in self.app.faces.values():
            for orientation,(w,h) in [('portrait',(758,1024)),('landscape',(1024,758))]:
                for dark in (False,True):
                    settings=U.copy(self.rt.load('core/settings').defaults);settings.night='dark' if dark else 'light'
                    scene=sceneclass.new(self.app,face,settings,w,h);scene.render(scene,epoch)
                    im=scene.frame.img
                    self.assertIsNotNone(im.getbbox())
                    self.assertGreater(im.getextrema()[1]-im.getextrema()[0],100)
                    dest=OUTPUT/f'{face.id}-{orientation}-{"dark" if dark else "light"}.png';im.save(dest)
                    if orientation=='portrait' and not dark:
                        previews.append((face,im.copy()))
                    # Same timestamp should have no dirty regions for stable inputs.
                    dirty=scene.render(scene,epoch)
                    self.assertIsNone(dirty,face.id)
                    # Changed minute must repaint an area.
                    dirty=scene.render(scene,epoch+60)
                    self.assertIsNotNone(dirty,face.id)
                    scene.free(scene)
        # Generate packaged previews from actual Lua scene execution.
        for face,im in previews:
            stream=io.BytesIO();im.save(stream,format='PNG',optimize=True)
            path=Path(face.path)
            with zipfile.ZipFile(path) as z:contents={n:z.read(n) for n in z.namelist()}
            contents['preview.png']=stream.getvalue()
            with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
                for n,b in contents.items():
                    zi=zipfile.ZipInfo(n,(2026,10,29,0,0,0));zi.compress_type=8;zi.external_attr=0o100644<<16;z.writestr(zi,b)
        sheet=Image.new('L',(5*270,2*405),244);draw=ImageDraw.Draw(sheet)
        for i,(face,im) in enumerate(previews):
            x=(i%5)*270;y=(i//5)*405
            sheet.paste(im.resize((246,332)),(x+12,y+10));draw.text((x+14,y+355),face.name,fill=15,font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',18))
        sheet.save(OUTPUT/'collection.png')
        self.app.scan(self.app)
        studio_class=self.rt.load('ui/studio')
        studio=studio_class.new(studio_class,self.rt.to_lua({'app':self.app}))
        BB=self.lua.eval('require("ffi/blitbuffer")')
        for tab in ['Galerie','Composer','Veille','Diagnostic']:
            studio.tab=tab;studio.refresh(studio)
            canvas=BB.new(758,1024,1);studio.paintTo(studio,canvas,0,0)
            canvas.img.save(OUTPUT/f'ui-{tab.lower()}.png')
            self.assertGreater(len(studio.regions),4)
        # Every section/page and every element must paint without errors.
        studio.tab='Composer'
        for element in ['time','date','battery','wifi','memory','world']:
            studio.element=element
            for section in ['Disposition','Typographie','Habillage','Informations','Images']:
                studio.section=section
                for page in range(1,5):
                    studio.page=page;studio.refresh(studio);studio.paintTo(studio,BB.new(758,1024,1),0,0)
        studio.onCloseWidget(studio)
    def test_16_dirty_area_covers_actual_changed_pixels(self):
        U=self.rt.load('core/util');sceneclass=self.rt.load('render/scene')
        for face in self.app.faces.values():
            scene=sceneclass.new(self.app,face,U.copy(self.rt.load('core/settings').defaults),758,1024)
            scene.render(scene,1793270040);before=scene.frame.img.copy()
            rect=scene.render(scene,1793270100);after=scene.frame.img
            bbox=ImageChops.difference(before,after).getbbox()
            self.assertIsNotNone(bbox)
            x,y,w,h=rect.x,rect.y,rect.w,rect.h
            self.assertLessEqual(x,bbox[0]);self.assertLessEqual(y,bbox[1]);self.assertGreaterEqual(x+w,bbox[2]);self.assertGreaterEqual(y+h,bbox[3])
            scene.free(scene)
    def test_17_sidecar_and_background_image(self):
        file=Path(self.rt.tmp.name)/'image.png';Image.new('L',(758,1024),230).save(file)
        Path(str(file)+'.json').write_text(json.dumps({'scale':110,'time':{'size':90,'x':4},'interval':0}))
        self.lua.globals().image_path=str(file)
        self.lua.globals().legacy_path=str(ROOT/"tests/fixtures/legacy.clock")
        self.lua.execute('''
            local s=load_module('core/util').copy(load_module('core/settings').defaults)
            s.image_enabled=true;s.image_portrait=image_path;s.per_image=true
            local legacy=load_module("packages/reader").open(legacy_path,app.data_dir.."/cache")
            local scene=load_module('render/scene').new(app,legacy,s,758,1024)
            scene:render(1793270040)
            assert(scene.s.scale==110 and scene.s.time.x==4 and scene.s.interval==60)
            scene:free()
        ''')
    def test_18_failed_refresh_is_bounded(self):
        self.lua.execute('''
            local ui=app.ui;ui.tasks={};local mgr=app.device.wakeup_mgr;mgr._task_queue={}
            local failures=0
            local p=load_module('power/scheduler').new{ui=ui,mgr=mgr,refresh=function()error('test')end,sleep=function()end,
                failed=function()failures=failures+1 end}
            p:start{interval=60,quiet=false}
            for i=1,3 do mgr._task_queue[1].epoch=os.time();assert(mgr:wakeupAction(3));ui:tick()end
            assert(not p.active and p.stats.errors==3 and failures==1)
            p:stop();mgr._task_queue={};ui.tasks={}
        ''')
    def test_19_real_upstream_screensaver_menu(self):
        self.lua.execute('''
            package.preload['apps/reader/readerui']=function()return {instance={statistics={}}}end
            package.preload['apps/filemanager/filemanager']=function()return {}end
            package.preload['gettext']=function()return setmetatable({ngettext=function(s,p,n)return n==1 and s or p end}, {__call=function(_,s)return s end})end
            package.preload['ffi/util']=function()return {template=function(s,...)return s end}end
            local table=dofile(upstream..'/screensaver_menu.lua')
            local items={screensaver={sub_item_table=table}}
            assert(app.integration:menu(items));assert(table[1].sub_item_table[1].atelierclock_option)
            assert(app.integration:menu(items))
            assert(not table[1].sub_item_table[2].atelierclock_option)
        ''')
    def test_20_widgets_repeated_ss_does_not_leak(self):
        self.lua.execute('''
            local ss=require('ui/screensaver');app.ui.tasks={};app.ui.shown={};app.device.wakeup_mgr._task_queue={}
            ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock'
            ss:show();local first=app.clock;local host=app.host
            ss:show();assert(first.closed and host.app_closed)
            assert(#app.ui.shown==1 and #app.device.wakeup_mgr._task_queue==1)
            app:stop();app.ui:close(app.host);app.ui.tasks={}
        ''')
    def test_21_cancel_last_physical_alarm(self):
        self.lua.execute('''
            local mgr=app.device.wakeup_mgr;mgr._task_queue={}
            local p=load_module('power/scheduler').new{ui=app.ui,mgr=mgr,refresh=function()end,sleep=function()end,failed=function()end}
            p:start{interval=60,quiet=false};assert(mgr.rtc:isWakeupAlarmScheduled())
            p:stop();assert(not mgr.rtc:isWakeupAlarmScheduled() and #mgr._task_queue==0)
        ''')
    def test_22_ui_touch_sliders_choices_and_cancel(self):
        self.lua.execute('''
            local bb=require('ffi/blitbuffer').new(758,1024,1)
            local studio=load_module('ui/studio'):new{app=app};studio.tab='Veille';studio.power_detail=true
            studio:paintTo(bb,0,0)
            local found
            for _,r in ipairs(studio.regions)do if r.slider then found=r;break end end
            assert(found);studio:onTap(nil,{pos={x=found.x+found.w,y=found.y+1}})
            assert(studio.draft.wake_margin==5 and studio.dirty)
            assert(studio:apply());assert(app.settings.data.wake_margin==5)
            studio:change('scale',85);assert(studio.draft.scale==85)
            studio:onCloseWidget()
            app.settings.data.wake_margin=0.3
        ''')
    def test_23_main_plugin_two_contexts_share_one_service(self):
        self.lua.execute('''
            package.loaded['atelierclock.service']=app
            local P=assert(loadfile(plugin_root..'/main.lua'))()
            local function context()return {menu={registerToMainMenu=function(self,w)self.widget=w end}}end
            local reader=context();local files=context();local one=P:new{ui=reader};local two=P:new{ui=files}
            assert(one.app==two.app and one.app==app)
            assert(reader.menu.widget==one and files.menu.widget==two)
            local menu={};one:addToMainMenu(menu);assert(menu.atelierclock.callback)
        ''')
    def test_24_native_kobo_guard_and_resuspend_coordination(self):
        self.lua.execute('''
            local source=assert(load_module('core/util').read(upstream..'/device.lua'))
            local first=assert(source:find('function Kobo:rescheduleSuspend',1,true))
            local last=assert(source:find('function Kobo:standby',first,true))
            local native=assert(loadstring("local Kobo={}; local UIManager=require('ui/uimanager');local logger=require('logger');"..source:sub(first,last-1)..'; return Kobo'))()
            local d=app.device;local ui=app.ui;ui.tasks={};ui.shown={};d.wakeup_mgr._task_queue={}
            local old={guard=app.kobo.original,check=d.checkUnexpectedWakeup,reschedule=d.rescheduleSuspend,suspend=d.suspend}
            app.kobo.original=native.scheduleUnexpectedWakeupGuard
            d.checkUnexpectedWakeup=native.checkUnexpectedWakeup;d.rescheduleSuspend=native.rescheduleSuspend
            d.unexpected_wakeup_count=0;d.suspend=function(self)self.test_slept=true end
            app.settings.data.fast_rtc=true;app.settings.data.interval=60
            local ss=require('ui/screensaver');ss.ui={};ss.prefix='';ss.screensaver_type='atelierclock';ss:show()
            local real_time=os.time;local now=app.scheduler.stats.next
            os.time=function(t)if t then return real_time(t)end;return now end
            d:scheduleUnexpectedWakeupGuard();assert(#ui.tasks==1 and ui.tasks[1].delay==0.2)
            local guard=table.remove(ui.tasks,1);guard.fn(unpack(guard.args))
            assert(#ui.tasks==2) -- deferred clock render + native 30s grace timer
            local next_tick=table.remove(ui.tasks,1);assert(next_tick.delay==0);next_tick.fn(unpack(next_tick.args))
            assert(#ui.tasks==1 and ui.tasks[1].fn==d.suspend and ui.tasks[1].delay==app.settings.data.wake_margin)
            assert(#d.wakeup_mgr._task_queue==1 and d.wakeup_mgr._task_queue[1].callback==app.scheduler.callback)
            assert(ui.waited)
            app:stop();app.ui:close(app.host);ui.tasks={};os.time=real_time
            app.kobo.original=old.guard;d.checkUnexpectedWakeup=old.check;d.rescheduleSuspend=old.reschedule;d.suspend=old.suspend
            app.settings.data.fast_rtc=false
            local power=d:getPowerDevice();local capacity=power.capacity;power.capacity=nil
            assert(app:capacity()==nil);power.capacity=capacity
        ''')

if __name__=='__main__':unittest.main(verbosity=2)
