"""LuaJIT execution harness. Real upstream archiver + libarchive; simulated UI.
The simulated framebuffer uses Pillow and substitutes fonts for visual review.
It cannot validate actual Kobo suspension, input drivers or battery drain.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
from lupa.luajit21 import LuaRuntime
import json, os, tempfile
from functools import lru_cache

@lru_cache(maxsize=256)
def cached_font(size,bold):return ImageFont.truetype(BOLD if bold else FONT,max(7,int(size)))

ROOT=Path(__file__).resolve().parents[1]
PLUGIN=ROOT/'atelierclock.koplugin'
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

class Runtime:
    def __init__(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.tmp=tempfile.TemporaryDirectory(prefix='atelier-test-',dir=ROOT/'tests')
        self.g=self.lua.globals()
        self.g.py_new=lambda w,h: Image.new('L',(int(w),int(h)),255)
        self.g.py_copy=lambda im:im.copy()
        self.g.py_bytes=lambda im:im.tobytes()
        self.g.py_png=lambda im,path:im.save(path,format="PNG") or True
        self.g.py_rect=self.rect
        self.g.py_paste=lambda dst,src,x,y,sx,sy,w,h:dst.paste(src.crop((int(sx),int(sy),int(sx+w),int(sy+h))),(int(x),int(y)))
        self.g.py_invert=lambda im:ImageOps.invert(im)
        self.g.py_invrect=self.invrect
        self.g.py_blend=self.blend
        self.g.py_resize=lambda im,w,h:im.resize((max(1,int(w)),max(1,int(h))),Image.Resampling.BILINEAR)
        self.g.py_text=self.text
        self.g.py_size=self.size
        self.g.py_image=self.image
        self.g.py_read_json=lambda s:self.to_lua(json.loads(s))
        self.g.py_json=lambda t:json.dumps(self.to_python(t),ensure_ascii=False,separators=(',',':'))
        self.g.py_mkdir=lambda p:os.mkdir(p) or True
        self.g.py_attr=self.attr
        self.g.py_ls=lambda p:self.to_lua(['.','..']+os.listdir(p))
        self.g.test_data=self.tmp.name
        self.g.plugin_root=str(PLUGIN)
        self.g.upstream=str(ROOT/'research-koreader')
        self.lua.execute(BOOTSTRAP)
        self.load=self.lua.eval('load_module')
    def to_lua(self,v):
        if isinstance(v,dict):return self.lua.table_from({k:self.to_lua(x) for k,x in v.items()})
        if isinstance(v,list):return self.lua.table_from([self.to_lua(x) for x in v])
        return v
    def to_python(self,v):
        if hasattr(v,'items'):
            d={k:self.to_python(x) for k,x in v.items()}
            if d and all(isinstance(k,int) for k in d) and sorted(d)==list(range(1,len(d)+1)):return [d[i] for i in range(1,len(d)+1)]
            return d
        return v
    def attr(self,path,key=None):
        p=Path(path)
        if not p.exists():return None
        d={'mode':'directory' if p.is_dir() else 'file','size':p.stat().st_size,'modification':p.stat().st_mtime}
        return d.get(key) if key else self.to_lua(d)
    @staticmethod
    def rect(im,x,y,w,h,c):
        if w>0 and h>0: ImageDraw.Draw(im).rectangle((int(x),int(y),int(x+w)-1,int(y+h)-1),fill=int(c))
    @staticmethod
    def invrect(im,x,y,w,h):
        box=(int(x),int(y),int(x+w),int(y+h));im.paste(ImageOps.invert(im.crop(box)),box)
    @staticmethod
    def blend(im,x,y,w,h,c,by):
        box=(max(0,int(x)),max(0,int(y)),min(im.width,int(x+w)),min(im.height,int(y+h)))
        if box[2]<=box[0] or box[3]<=box[1]:return
        part=im.crop(box);im.paste(Image.blend(part,Image.new('L',part.size,int(c)),max(0,min(1,float(by)))),box)
    def face(self,f,bold=False):return cached_font(int(f['size']),bold)
    def size(self,text,f,bold):
        font=self.face(f,bold);box=font.getbbox(str(text),anchor='ls')
        return self.to_lua({'x':font.getlength(str(text)),'y_top':-box[1],'y_bottom':max(0,box[3])})
    def text(self,im,x,y,f,text,bold,c):
        ImageDraw.Draw(im).text((int(x),int(y)),str(text),font=self.face(f,bold),fill=int(c),anchor='ls')
    @staticmethod
    def image(im,path,x,y,w,h):
        with Image.open(path) as src:
            src=src.convert('L').resize((max(1,int(w)),max(1,int(h))),Image.Resampling.LANCZOS)
            im.paste(src,(int(x),int(y)))
    def app(self):return self.load('app').new(str(PLUGIN),self.load)
    def close(self):self.tmp.cleanup()

BOOTSTRAP=r'''
local ffi=require('ffi')
ffi.libc='gnu'
ffi.loadlib=function(name,version) return ffi.load(name=="archive" and "libarchive.so.13" or name) end
package.preload['ffi/posix_h']=function() return dofile(upstream..'/posix_h.lua') end
package.preload['ffi/libarchive_h']=function() return dofile(upstream..'/libarchive_h.lua') end
package.preload['ui/time']=function()return dofile(upstream..'/time.lua')end
package.preload['ffi/archiver']=function() return dofile(upstream..'/archiver.lua') end
package.preload['json']=function() return {decode=py_read_json,encode=py_json} end
package.preload['logger']=function() return setmetatable({}, {__index=function()return function()end end}) end
package.preload['libs/libkoreader-lfs']=function()return {
    attributes=py_attr,mkdir=py_mkdir,
    dir=function(path)local a=py_ls(path);local i=0;return function()i=i+1;return a[i]end end,
}end
local BB={TYPE_BB8=1,Color8=function(n)return n end}
local methods={}
function BB.new(w,h)
    return setmetatable({img=py_new(w,h),w=w,h=h,stride=w}, {__index=function(self,key)
        if key=='data'then
            -- Materialize Pillow's actual pixels into a native BB8 scan buffer.
            -- Production uses its existing BB8 data; no Python/image copies.
            self._scan_data=ffi.new('uint8_t[?]',self.w*self.h)
            ffi.copy(self._scan_data,py_bytes(self.img),self.w*self.h)
            return self._scan_data
        end
        return methods[key]
    end})
end
function methods:getType()return BB.TYPE_BB8 end
function methods:getRotation()return 0 end
function methods:getInverse()return 0 end
function methods:writePNG(path)return py_png(self.img,path)end
function methods:getWidth()return self.w end
function methods:getHeight()return self.h end
function methods:paintRect(x,y,w,h,c)py_rect(self.img,x,y,w,h,c)end
function methods:fill(c)py_rect(self.img,0,0,self.w,self.h,c)end
function methods:copy()local b=BB.new(self.w,self.h);b.img=py_copy(self.img);return b end
function methods:free()self.freed=true end
function methods:invertRect(x,y,w,h)py_invrect(self.img,x,y,w,h)end
function methods:darkenRect(x,y,w,h,by)py_blend(self.img,x,y,w,h,0,by or .5)end
function methods:lightenRect(x,y,w,h,by)py_blend(self.img,x,y,w,h,255,by or .5)end
function methods:invert()self.img=py_invert(self.img)end
function methods:blitFrom(src,x,y,sx,sy,w,h)py_paste(self.img,src.img,x,y,sx,sy,w,h)end
package.preload['ffi/blitbuffer']=function()return BB end
package.preload['ui/renderimage']=function()return {scaleBlitBuffer=function(_,bb,w,h)
    if bb.w==w and bb.h==h then return bb end
    local b=BB.new(w,h);b.img=py_resize(bb.img,w,h);return b end}end
package.preload['ui/font']=function()return {getFace=function(_,name,size)return {name=name,size=require('device').screen:scaleBySize(size)}end}end
package.preload['ui/rendertext']=function()return {
    sizeUtf8Text=function(_,x,w,face,text,kern,bold)return py_size(text,face,bold or false)end,
    renderUtf8Text=function(_,bb,x,y,face,text,kern,bold,c)py_text(bb.img,x,y,face,text,bold or false,c)end,
}end
local Object={}
function Object:extend(t)t=t or {};return setmetatable(t,{__index=self})end
function Object:new(t)
    t=t or {};setmetatable(t,{__index=self});t.ges_events={};t.key_events={}
    if t.init then t:init()end;return t
end
function Object:free()for _,v in ipairs(self)do if v.free then v:free()end end end
package.preload['ui/widget/container/inputcontainer']=function()return Object end
package.preload['ui/widget/container/widgetcontainer']=function()return Object end
package.preload['ui/geometry']=function()return Object end
package.preload['ui/gesturerange']=function()return Object end
package.preload['ui/widget/imagewidget']=function()
    local I=Object:extend{}
    function I:paintTo(bb,x,y)py_image(bb.img,self.file,x,y,self.width,self.height)end
    return I
end
local ui={tasks={},shown={},dirty={}}
function ui:scheduleIn(delay,fn,...)
    self.tasks[#self.tasks+1]={delay=delay,fn=fn,args={...}}
end
function ui:nextTick(fn,...)self:scheduleIn(0,fn,...)end
function ui:unschedule(fn)for i=#self.tasks,1,-1 do if self.tasks[i].fn==fn then table.remove(self.tasks,i)end end end
function ui:show(w)if w then self.shown[#self.shown+1]=w end end
function ui:close(w)
    if w and w.onCloseWidget then w:onCloseWidget()end
    if w and w.widget and w.widget.onCloseWidget then w.widget:onCloseWidget()end
    for i=#self.shown,1,-1 do if self.shown[i]==w then table.remove(self.shown,i)end end
end
function ui:setDirty(widget,kind,rect)self.dirty[#self.dirty+1]={widget=widget,kind=kind,rect=rect}end
function ui:forceRePaint()end
function ui:waitForVSync()self.waited=true end
function ui:setIgnoreTouchInput()end
function ui:tick()local t=self.tasks;self.tasks={};for _,v in ipairs(t)do v.fn(unpack(v.args))end end
function ui:runNext()
    if #self.tasks==0 then return nil end
    local index=1
    for i=2,#self.tasks do if self.tasks[i].delay<self.tasks[index].delay then index=i end end
    local task=table.remove(self.tasks,index);task.fn(unpack(task.args));return task
end
package.preload['ui/uimanager']=function()return ui end
local settings={screensaver_type='cover'}
G_reader_settings={readSetting=function(_,k,d)local v=settings[k];if v==nil then return d end;return v end,
    saveSetting=function(_,k,v)settings[k]=v end,isTrue=function(_,k)return settings[k]==true end}
local screen={rotation=0,w=758,h=1024,dpi=212}
function screen:getWidth()return self.w end
function screen:getHeight()return self.h end
function screen:getDPI()return self.dpi end
function screen:scaleByDPI(n)return math.ceil(n*self.dpi/160)end
function screen:scaleBySize(n)
    local scale=math.min(self.w,self.h)/600
    local density=self.dpi_override and self.dpi/160 or scale
    return math.ceil(n*(scale+density)/2)
end
function screen:getRotationMode()return self.rotation end
function screen:setRotationMode(n)
    self.rotation=n;if n%2==0 then self.w=758;self.h=1024 else self.w=1024;self.h=758 end
end
local rtc={}
function rtc:secondsFromNowToEpoch(n)return os.time()+n end
function rtc:setWakeupAlarm(t)self.epoch=t;return true end
function rtc:unsetWakeupAlarm()self.epoch=nil;return true end
function rtc:getWakeupAlarmEpoch()return self.epoch end
function rtc:isWakeupAlarmScheduled()return self.epoch~=nil end
function rtc:validateWakeupAlarmByProximity(task,proximity)return math.abs(os.time()-(task or self.epoch))<=(proximity or 30)end
package.preload['ffi/rtc']=function()return rtc end
local WakeupMgr=dofile(upstream..'/wakeupmgr.lua')
local device={model='Kobo_star',screen=screen,wakeup_mgr=WakeupMgr:new(),input={group={Any='Any'}}}
local power={fl_intensity=8,capacity=80}
function power:getCapacity()return self.capacity end
function power:isCharging()return self.charging==true end
function power:setIntensity(n)self.fl_intensity=n end
function power:isFrontlightOn()return self.fl_intensity>0 end
function power:turnOffFrontlight()self.fl_intensity=0 end
function device:getPowerDevice()return power end
function device:isKobo()return true end
function device:hasKeys()return false end
function device:isTouchDevice()return true end
function device:canReboot()return true end
function device:canPowerOff()return true end
function device:rescheduleSuspend(n)self.sleep_after=n end
function device:checkUnexpectedWakeup()end
function device:scheduleUnexpectedWakeupGuard()ui:scheduleIn(15,self.checkUnexpectedWakeup,self)end
package.preload['device']=function()return device end
package.preload['datastorage']=function()return {getSettingsDir=function()return test_data end}end
package.preload['dispatcher']=function()return {registerAction=function()end}end
local ss={show=function(self)self.fallback=true end,cleanup=function()end}
package.preload['ui/screensaver']=function()return ss end
package.preload['ui/widget/screensaverwidget']=function()
    local Host=Object:extend{}
    function Host:onCloseWidget()ss.screensaver_widget=nil;self.app_closed=true end
    return Host
end
package.preload['ui/widget/screensaverlockwidget']=function()return Object end
package.preload['ui/network/manager']=function()return {isWifiOn=function()return false end}end
package.preload['ui/widget/confirmbox']=function()return Object end
package.preload['ui/widget/inputdialog']=function()
    local Dialog=Object:extend{}
    function Dialog:onShowKeyboard()end
    function Dialog:getInputText()return self.input end
    return Dialog
end
local loaded={}
function load_module(name)
    if not loaded[name]then loaded[name]=assert(loadfile(plugin_root..'/'..name..'.lua'))(load_module)end
    return loaded[name]
end
'''
