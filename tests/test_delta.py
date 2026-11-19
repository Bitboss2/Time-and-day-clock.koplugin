"""Pixel-exact BB8 changes, conservative fallback and bounded EPDC windows.
These are display correctness tests, not a measurement of energy on a Kobo.
"""
from runtime import Runtime
from PIL import ImageChops
import random,unittest

class DeltaTests(unittest.TestCase):
    def setUp(self):
        self.r=Runtime();self.lua=self.r.lua
        self.delta=self.r.load('render/delta')
        self.lua.execute('''
            local ffi=require('ffi');Delta=load_module('render/delta')
            function tile(w,h,stride)
                return {stride=stride or w,data=ffi.new('uint8_t[?]',(stride or w)*h),
                    getType=function()return require('ffi/blitbuffer').TYPE_BB8 end,
                    getRotation=function()return 0 end,getInverse=function()return 0 end,
                    getWidth=function()return w end,getHeight=function()return h end}
            end
            function put(tile,index,value)tile.data[index]=value end
        ''')
    def tearDown(self):self.r.close()
    def test_01_unchanged_bytes_need_no_refresh(self):
        self.lua.execute('local a,b=tile(30,50),tile(30,50);local r,n=Delta.scan(a,b);assert(#r==0 and n==1500)')
    def test_02_first_last_pixels_and_unequal_padded_strides(self):
        self.lua.execute('''
            local a,b=tile(13,19,32),tile(13,19,40)
            b.data[0]=1;b.data[18*40+12]=255
            local r=Delta.scan(a,b);assert(#r==2)
            assert(r[1].x==0 and r[1].y==0 and r[1].w==1 and r[1].h==1)
            assert(r[2].x==12 and r[2].y==18 and r[2].w==1 and r[2].h==1)
            b.data[0]=0;b.data[18*40+12]=0;b.data[13]=128
            assert(#Delta.scan(a,b)==0,'row padding must not be displayed')
        ''')
    def test_03_incompatible_layouts_are_rejected(self):
        self.lua.execute('''
            local a,b=tile(9,12),tile(9,13);assert(Delta.scan(a,b)==nil)
            b=tile(9,12);b.getRotation=function()return 1 end;assert(Delta.scan(a,b)==nil)
            b=tile(9,12);b.getInverse=function()return 1 end;assert(Delta.scan(a,b)==nil)
            b=tile(9,12);b.getType=function()return 3 end;assert(Delta.scan(a,b)==nil)
            b=tile(9,12);b.stride=8;assert(Delta.scan(a,b)==nil)
            b=tile(9,12);b.data=require('ffi').cast('uint8_t*',nil);assert(Delta.scan(a,b)==nil)
            b=tile(9,12);b.getRotation=nil;assert(Delta.scan(a,b)==nil)
        ''')
    def test_04_random_changes_all_covered_without_out_of_bounds(self):
        random.seed(31)
        for _ in range(60):
            w,h=random.randint(1,50),random.randint(1,70)
            a=self.lua.globals().tile(w,h,w+3);b=self.lua.globals().tile(w,h,w+7)
            changed=set()
            for __ in range(70):
                x,y=random.randrange(w),random.randrange(h)
                self.lua.globals().put(b,y*(w+7)+x,random.randint(1,255));changed.add((x,y))
            bands,_=self.delta.scan(a,b);plan=self.delta.plan(bands,4)
            self.assertLessEqual(len(plan),4)
            for box in plan.values():
                self.assertTrue(0<=box.x<box.x+box.w<=w)
                self.assertTrue(0<=box.y<box.y+box.h<=h)
            for x,y in changed:
                self.assertTrue(any(v.x<=x<v.x+v.w and v.y<=y<v.y+v.h for v in plan.values()))
    def test_05_disconnected_changes_stay_small_and_commands_are_bounded(self):
        self.lua.execute('''
            local boxes={}
            for i=0,7 do boxes[#boxes+1]={x=(i%2)*300,y=i*30,w=4,h=4}end
            local r=Delta.plan(boxes,4);assert(#r<=4 and Delta.area(r)<304*214/3)
            for i=1,#r do for j=i+1,#r do
                local a,b=r[i],r[j]
                assert(a.x>b.x+b.w or b.x>a.x+a.w or a.y>b.y+b.h or b.y>a.y+a.h)
            end end
        ''')
    def test_06_grayscale_erasure_and_unchanged_key_output(self):
        self.lua.execute('''
            local a,b=tile(25,25),tile(25,25)
            a.data[12*25+3]=96;b.data[12*25+4]=192
            local r=Delta.scan(a,b);assert(#r==1 and r[1].x==3 and r[1].w==2)
        ''')
    def test_07_real_faces_keep_exact_pixels_and_reduce_requested_area(self):
        app=self.r.app();scene=self.r.load('render/scene');total=coarse=0
        for face in app.faces.values():
            for w,h in [(758,1024),(1024,758)]:
                s=scene.new(app,face,app.settings.data,w,h)
                # Last minute of hour/day/month catches changing titles/dates.
                for epoch in [1793270040,1793318340,1796083140]:
                    s.render(s,epoch);before=s.frame.img.copy();s.render(s,epoch+60)
                    diff=ImageChops.difference(before,s.frame.img)
                    self.assertLessEqual(len(s.regions),4)
                    total+=self.delta.area(s.regions);coarse+=self.delta.area(s.coarse_regions)
                    for box in s.regions.values():
                        diff.paste(0,(int(box.x),int(box.y),int(box.x+box.w),int(box.y+box.h)))
                    self.assertIsNone(diff.getbbox(),face.id)
                    self.assertEqual(s.delta_fallbacks,0,face.id)
                s.free(s)
        self.assertLess(total,coarse*.8)
    def test_08_scan_failure_keeps_conservative_windows(self):
        self.lua.execute('''
            app=load_module('app').new(plugin_root,load_module)
            local scene=load_module('render/scene').new(app,app:face(),app.settings.data,758,1024)
            scene:render(1793270040)
            local scan=Delta.scan;Delta.scan=function()error('unknown future buffer')end
            scene:render(1793270100);Delta.scan=scan
            assert(scene.delta_fallbacks>0 and #scene.regions>0)
            assert(Delta.area(scene.regions)==Delta.area(scene.coarse_regions));scene:free()
        ''')
    def test_09_interpreter_does_not_run_a_large_pixel_loop(self):
        self.lua.execute('''
            local a,b=tile(25,25),tile(25,25);require('jit').off()
            assert(Delta.scan(a,b)==nil);require('jit').on()
        ''')
    def test_10_incomplete_ink_hint_cannot_override_changed_pixel_evidence(self):
        self.lua.execute('''
            app=load_module('app').new(plugin_root,load_module)
            local scene=load_module('render/scene').new(app,app:face(),app.settings.data,40,40)
            scene:render(1793270040)
            scene:tile('probe',{0,0,1,1},'a',function(bb)
                bb:paintRect(1,1,1,1,0);return {x=0,y=0,w=3,h=3}
            end)
            scene.regions={};scene.coarse_regions={}
            scene:tile('probe',{0,0,1,1},'b',function(bb)
                bb:paintRect(38,38,1,1,0);return {x=0,y=0,w=3,h=3}
            end)
            local safe=scene.coarse_regions[1]
            assert(safe.x==0 and safe.y==0 and safe.w==40 and safe.h==40)
            local covered=false
            for _,r in ipairs(scene.regions)do if r.x<=38 and r.y<=38 and r.x+r.w>38 and r.y+r.h>38 then covered=true end end
            assert(covered);scene:free()
        ''')
    def test_11_low_benefit_scan_is_suspended_then_probed_again(self):
        self.lua.execute('''
            app=load_module('app').new(plugin_root,load_module)
            local scene=load_module('render/scene').new(app,app:face(),app.settings.data,40,40)
            scene:render(1793270040)
            local function update(n)
                scene.regions={};scene.coarse_regions={};scene.delta_skipped=0;scene.delta_scanned_pixels=0
                scene:tile('probe',{0,0,1,1},tostring(n),function(bb)bb:fill(n%2*255)end)
            end
            for n=0,3 do update(n)end
            assert(scene.tiles.probe.delta_policy.cooldown==7)
            for n=4,10 do update(n);assert(scene.delta_skipped==1 and scene.delta_scanned_pixels==0)end
            update(11);assert(scene.delta_skipped==0 and scene.delta_scanned_pixels==1600)
            scene:free()
        ''')
    def test_12_sparse_scan_stays_enabled(self):
        self.lua.execute('''
            app=load_module('app').new(plugin_root,load_module)
            local scene=load_module('render/scene').new(app,app:face(),app.settings.data,40,40)
            scene:render(1793270040)
            for n=0,12 do
                scene.regions={};scene.coarse_regions={};scene.delta_skipped=0
                scene:tile('probe',{0,0,1,1},tostring(n),function(bb)
                    bb:fill(255);bb:paintRect(n,20,1,1,0)
                end)
                assert(scene.delta_skipped==0 and scene.tiles.probe.delta_policy.cooldown==0)
            end
            scene:free()
        ''')

if __name__=='__main__':unittest.main(verbosity=2)
