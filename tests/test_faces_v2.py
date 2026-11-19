"""Declarative v2 faces, actual pixel coverage, retained rendering and editor flows."""
from runtime import Runtime,ROOT,PLUGIN
from PIL import Image,ImageChops
from pathlib import Path
import copy,json,unittest,zipfile
OUT=ROOT/'tests/output'

class FacesV2Tests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua;self.app=self.r.app();self.lua.globals().app=self.app
    def tearDown(self):self.r.close()
    def scene(self,id='totem',w=758,h=1024):
        return self.r.load('render/scene').new(self.app,self.app.face(self.app,id),self.app.settings.data,w,h)
    def studio(self):
        cls=self.r.load('ui/studio');return cls.new(cls,self.r.to_lua({'app':self.app}))
    def canvas(self,w=758,h=1024):return self.lua.eval('require("ffi/blitbuffer")').new(w,h,1)
    def paint(self,studio,w=758,h=1024):
        canvas=self.canvas(w,h);studio.paintTo(studio,canvas);return canvas
    def test_01_ten_new_ids_and_distinct_layout_signatures(self):
        ids={f.id for f in self.app.faces.values()}
        self.assertEqual(ids,{'totem','duplex','index','halo','journal','lisiere','mosaique','octant','typo','signal'})
        signatures=[]
        for f in self.app.faces.values():
            self.assertEqual(f.schema_version,2)
            signatures.append(json.dumps(self.r.to_python(f.layouts.portrait),sort_keys=True))
        self.assertEqual(len(set(signatures)),10)
    def test_02_default_collection_and_independent_duplicates_roundtrip(self):
        self.lua.execute('''
            local C=load_module('core/collection');local s=app.settings.data
            assert(#s.collection==1 and C.current(s).face=='totem')
            local first=C.current(s);first.slots.date={provider='world',zone='Europe/Paris'}
            local second=C.add(s,app:face(),first);second.slots.date.zone='Asia/Tokyo';second.style='contour'
            assert(first.slots.date.zone=='Europe/Paris')
            assert(app.settings:save(s))
            local read=load_module('core/settings').new(app.settings.path).data
            assert(#read.collection==2 and C.current(read).style=='contour')
            assert(read.collection[1].slots.date.zone=='Europe/Paris')
            assert(read.collection[2].slots.date.zone=='Asia/Tokyo')
        ''')
    def test_03_reject_invalid_v2_manifests(self):
        f=self.app.faces[1]
        with zipfile.ZipFile(f.path)as z:base=json.loads(z.read('manifest.json'));entries=self.r.to_lua({n:True for n in z.namelist()})
        validator=self.r.load('packages/reader').validate
        mutations=[lambda m:m['layouts']['portrait']['blocks'][0].update(type='lua'),
                   lambda m:m['layouts']['landscape']['blocks'][0].update(box=[.9,.1,.3,.2]),
                   lambda m:m['layouts']['portrait']['slots'].update(unknown=[.1,.1,.2,.2]),
                   lambda m:m['slots'][0].update(default='weather'),
                   lambda m:m['slots'][0].update(allowed=['battery','battery']),
                   lambda m:m['layouts']['portrait']['blocks'][0].update(box=[0,0,.99,.99]),
                   lambda m:m.update(styles=['remote']),lambda m:m.update(engine_min='0.3.0'),
                   lambda m:m.update(texture_landscape='absent'),
                   lambda m:m.update(preset={'style':'plein','appearance':'paper','slots':{'date':{'provider':'world','zone':'Unknown'}}})]
        for mutate in mutations:
            m=copy.deepcopy(base);mutate(m)
            with self.assertRaises(Exception):validator(self.r.to_lua(m),entries)
    def test_04_legacy_v1_import_remains_functional(self):
        face=self.r.load('packages/reader').open(str(ROOT/'tests/fixtures/legacy.clock'),self.app.data_dir+'/cache')
        s=self.r.load('render/scene').new(self.app,face,self.app.settings.data,758,1024)
        s.render(s,1793270040);self.assertIsNotNone(s.frame.img.getbbox());s.free(s)
    def test_05_unchanged_tiles_not_rasterized_twice(self):
        for f in self.app.faces.values():
            s=self.scene(f.id);s.render(s,1793270040);count=s.draws
            self.assertIsNone(s.render(s,1793270040));self.assertEqual(s.draws,count)
            s.render(s,1793270100);self.assertGreater(s.draws,count)
            if f.id in ['totem','signal']:self.assertEqual(s.draws-count,1,f.id)
            if f.id=='duplex':self.assertEqual(s.draws-count,2) # minutes + world time
            s.free(s)
    def test_06_all_requested_regions_cover_all_changed_pixels(self):
        for f in self.app.faces.values():
            for w,h in [(758,1024),(1024,758)]:
                s=self.scene(f.id,w,h)
                for epoch in [1793270040,1793318340,1796083140]:
                    s.render(s,epoch);before=s.frame.img.copy();s.render(s,epoch+60)
                    diff=ImageChops.difference(before,s.frame.img)
                    for r in s.regions.values():
                        self.assertTrue(0<=r.x<r.x+r.w<=w);self.assertTrue(0<=r.y<r.y+r.h<=h)
                        diff.paste(0,(int(r.x),int(r.y),int(r.x+r.w),int(r.y+r.h)))
                    self.assertIsNone(diff.getbbox(),(f.id,w,h,epoch))
                s.free(s)
    def test_07_all_providers_families_and_unknown_battery(self):
        C=self.r.load('core/collection');S=self.r.load('core/settings');U=self.r.load('core/util')
        for f in self.app.faces.values():
            for provider in ['none','date','battery','day','week','world','book']:
                settings=U.copy(S.defaults);item=C.add(settings,f)
                for slot in f.slots.values():item.slots[slot.id]=self.r.to_lua({'provider':provider,'zone':'Europe/Paris'})
                s=self.r.load('render/scene').new(self.app,f,settings,379,512)
                s.render(s,1793270040);self.assertIsNone(s.render(s,1793270040));s.free(s)
        self.lua.execute('''
            local C=load_module('core/collection');local item=C.current(app.settings.data)
            item.slots.charge={provider='battery',zone='UTC'}
            app.device:getPowerDevice().capacity=nil
            local scene=load_module('render/scene').new(app,app:face(),app.settings.data,758,1024)
            scene:render();assert(scene.old.slot_charge.key=='—');scene:free()
        ''')
    def test_08_light_dark_and_styles_are_visible_changes(self):
        U=self.r.load('core/util');C=self.r.load('core/collection');sc=self.r.load('render/scene')
        for f in self.app.faces.values():
            images=[]
            for style in f.styles.values():
                settings=U.copy(self.app.settings.data);settings.collection=self.r.to_lua([]);item=C.add(settings,f)
                item.style=style;item.appearance='paper'
                s=sc.new(self.app,f,settings,379,512);s.render(s,1793270040);images.append(s.frame.img.copy());s.free(s)
            for i in range(len(images)):
                for j in range(i):self.assertIsNotNone(ImageChops.difference(images[i],images[j]).getbbox(),(f.id,i,j))
        s=self.scene();s.render(s,1793270040);light=s.frame.img.copy();s.free(s)
        C.current(self.app.settings.data).appearance='ink'
        s=self.scene();s.render(s,1793270040);dark=s.frame.img.copy();s.free(s)
        self.assertIsNotNone(ImageChops.difference(light,dark).getbbox())
    def test_09_complication_hit_targets_and_picker_selection(self):
        self.lua.execute('''
            local st=load_module('ui/studio'):new{app=app};st.tab='Composer'
            local function paint()st:paintTo(require('ffi/blitbuffer').new(758,1024,1))end
            paint();local target
            for _,r in ipairs(st.regions)do if r.slot_id=='charge'then target=r end end
            assert(target);st:onTap(nil,{pos={x=target.x+target.w/2,y=target.y+target.h/2}})
            assert(st.slot_picker=='charge');paint()
            local choice
            for _,r in ipairs(st.regions)do if r.provider=='day'then choice=r end end
            assert(choice);st:onTap(nil,{pos={x=choice.x+choice.w/2,y=choice.y+choice.h/2}})
            assert(not st.slot_picker and st.dirty)
            assert(load_module('core/collection').current(st.draft).slots.charge.provider=='day')
            assert(st:apply())
            assert(load_module('core/collection').current(app.settings.data).slots.charge.provider=='day')
            st:onCloseWidget()
        ''')
    def test_10_swipe_browse_never_changes_active_face(self):
        self.lua.execute('''
            local st=load_module('ui/studio'):new{app=app};st.catalog=true
            local current=st.draft.face
            for _=1,9 do st:onSwipe(nil,{direction='west'})end
            assert(st.browser_index==10 and st.draft.face==current and app.settings.data.face==current)
            st:addFace(app.faces[10]);assert(st.tab=='Composer'and st.draft.face==app.faces[10].id)
            assert(#st.draft.collection==2 and #app.settings.data.collection==1)
            st:onCloseWidget()
        ''')
    def test_11_complication_swipe_does_not_drag_layout(self):
        self.lua.execute('''
            local st=load_module('ui/studio'):new{app=app};st.tab='Composer'
            st:paintTo(require('ffi/blitbuffer').new(758,1024,1))
            local r=st.preview_box
            st:onPan(nil,{pos={x=r.x+r.w/2,y=r.y+r.h/2},relative={x=50,y=30}})
            assert(st.draft.time.x==0 and st.draft.time.y==0 and not st.canvas_drag)
            st:onCloseWidget()
        ''')
    def test_12_all_editor_modes_all_sizes_have_bounded_targets(self):
        screen=self.app.device.screen
        for w,h,dpi,scale in [(600,800,167,100),(758,1024,212,100),(1072,1448,300,100),(1024,758,212,100),(758,1024,212,140)]:
            screen.w=w;screen.h=h;screen.dpi=dpi;self.app.settings.data.ui_scale=scale
            st=self.studio();st.tab='Composer'
            for mode in ['complications','style','options','picker']:
                st.edit_mode=mode;st.slot_picker='charge'if mode=='picker'else None;st.refresh(st)
                im=self.paint(st,w,h);im.img.save(OUT/f'editor-v2-{mode}-{w}-{scale}.png')
                for r in st.regions.values():
                    self.assertGreaterEqual(r.x,-1);self.assertLessEqual(r.x+r.w,w+2)
                    self.assertGreaterEqual(r.y,-1);self.assertLessEqual(r.y+r.h,h+2)
                    if st.top<=r.y<st.h-134*st.k:self.assertLessEqual(r.y+r.h,st.bottom+2,(mode,w,h,scale))
            st.onCloseWidget(st)
    def test_13_actual_clock_export_and_import_preserves_preset(self):
        path=str(Path(self.r.tmp.name)/'export.clock');self.lua.globals().export_path=path
        self.lua.execute('''
            local item=load_module('core/collection').current(app.settings.data)
            item.style='contour';item.appearance='ink';item.slots.date={provider='world',zone='Asia/Tokyo'}
            local file,err=load_module('packages/export').write(app,app.settings.data,export_path)
            assert(file,err)
            local imported=assert(app:import(export_path));assert(imported.preset.style=='contour')
            local copy=load_module('core/collection').add(app.settings.data,imported)
            assert(copy.appearance=='ink'and copy.slots.date.zone=='Asia/Tokyo')
            assert(not load_module('packages/export').write(app,app.settings.data,export_path))
        ''')
        with zipfile.ZipFile(path)as z:
            self.assertIsNone(z.testzip());self.assertEqual(z.getinfo('manifest.json').compress_type,8)
            self.assertIn('preview.png',z.namelist())
        self.assertFalse(Path(path+'.tmp').exists());self.assertFalse(Path(path+'.preview.png').exists())
    def test_14_hour_rollover_calendar_midnight_and_am_pm(self):
        self.lua.execute('''
            local s=app.settings.data;s.format='12'
            local scene=load_module('render/scene').new(app,app:face(),s,758,1024)
            local t=os.time{year=2026,month=10,day=30,hour=11,min=59,sec=0}
            scene:render(t);scene:render(t+60);assert(scene.old.hours.key=='12PM'and scene.old.minutes.key=='00')
            scene:free()
            local f=app:face('journal');scene=load_module('render/scene').new(app,f,s,758,1024)
            t=os.time{year=2028,month=2,day=29,hour=23,min=59,sec=0}
            scene:render(t);scene:render(t+60);assert(scene.old.month.key=='2028-03-01');scene:free()
        ''')
    def test_15_battery_and_reading_snapshot_use_no_extra_wake_timers(self):
        self.lua.execute('''
            local n=0
            app.context={doc_settings={readSetting=function(_,key)n=n+1;if key=='doc_props'then return {title='Dune'}else return .42 end end}}
            local scene=load_module('render/scene').new(app,app:face('mosaique'),app.settings.data,758,1024)
            assert(n==2);local tasks=#app.ui.tasks
            for i=1,60 do app.cycle_capacity=80;scene:render(1793270040+i*60)end
            assert(n==2 and #app.ui.tasks==tasks)
            assert(scene.old.slot_wide.key=='42%Dune');scene:free()
        ''')
    def test_16_clock_update_submits_disjoint_regions_and_retains_full_cleanup(self):
        self.lua.execute('''
            local clock=app:content(true);clock.last_full=os.time();app.ui.dirty={}
            local real=os.time;local epoch=real();os.time=function(t)if t then return real(t)end;return epoch end
            epoch=epoch+60;clock:update();assert(#app.ui.dirty>=1)
            assert(app.metrics.refresh_percent<55)
            app.settings.data.full_refresh=1;clock.scene.s.full_refresh=1;clock.last_full=epoch-61
            epoch=epoch+60;app.ui.dirty={};clock:update()
            assert(#app.ui.dirty==1 and app.ui.dirty[1].kind=='full')
            clock:onCloseWidget();os.time=real
        ''')
    def test_17_collection_bounds_and_rejected_records(self):
        self.lua.execute('''
            local C=load_module('core/collection');local s=app.settings.data
            for _=1,23 do assert(C.add(s,app:face()))end
            assert(not C.add(s,app:face())and #s.collection==24)
            s.collection[2].uid=s.collection[1].uid;s.collection[3].face='../bad'
            local valid=load_module('core/settings').validate(s);assert(#valid.collection==22)
        ''')
    def test_19_schema_matches_shipped_v1_and_v2_archives(self):
        import jsonschema
        schema=json.loads((PLUGIN/'docs/clock.schema.json').read_text())
        for path in list((PLUGIN/'clocks').glob('*.clock'))+[ROOT/'tests/fixtures/legacy.clock']:
            with zipfile.ZipFile(path)as z:jsonschema.validate(json.loads(z.read('manifest.json')),schema)

    def test_18_retained_buffers_released_on_close(self):
        self.lua.execute('''
            local scene=load_module('render/scene').new(app,app:face('halo'),app.settings.data,758,1024)
            scene:render();assert(scene.statics.dial and scene.tiles.dial)
            scene:free();assert(not scene.frame and not scene.base and next(scene.tiles)==nil and next(scene.statics)==nil)
            scene:free()
        ''')
if __name__=='__main__':unittest.main(verbosity=2)
