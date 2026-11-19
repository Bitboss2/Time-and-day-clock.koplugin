"""Screenshots and animations of the 0.3.0 interface.

Every image comes from the real plugin code (Lua via LuaJIT) driving the
Atelier with a fake Fluid Ink backend and a deterministic 30 Hz clock: each
frame below is exactly a frame the plugin would publish to im_publish().
Fonts are DejaVu substitutes. The optional Bayer panel is a simulation of
the engine's 8×8 ordered dithering, not a photograph of the e-ink panel.

    PYTHONPATH=tests python tools/build_screenshots.py
"""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from runtime import Runtime
from test_fluid_ui import SETUP
from PIL import Image, ImageDraw, ImageFont

SHOTS=ROOT/'atelierclock.koplugin/docs'
MEDIA=ROOT/'docs/media';MEDIA.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

CAPTURE=r'''
captured={}
recording=false
local nf=native_factory
native_factory=function(screen,platform)
    local b=nf(screen,platform);local publish=b.publish
    function b:publish(bb,s)
        if recording then captured[#captured+1]=bb:copy()end
        return publish(self,bb,s)
    end
    return b
end
function find(attr,value)
    st:compose()
    for i=#st.regions,1,-1 do local r=st.regions[i];if r[attr]==value then return r end end
end
function tap(r)
    assert(r,'target missing')
    st:onTouch(nil,{pos={x=r.x+r.w/2,y=r.y+r.h/2}});run(.08)
    st:onTap(nil,{pos={x=r.x+r.w/2,y=r.y+r.h/2}})
end
function drag(x,y,dx,dy,steps,dt)
    st:onTouch(nil,{pos={x=x,y=y}});run(.05)
    for i=1,steps do
        local px,py=x+dx*i/steps,y+dy*i/steps
        st:onPan(nil,{pos={x=px,y=py},start_pos={x=x,y=y},relative={x=px-x,y=py-y}});run(dt)
    end
    st:onPanRelease(nil,{pos={x=x+dx,y=y+dy}})
end
function snapshot()st:compose();return st.frame:copy()end
'''

def frames(lua):
    t=lua.eval('captured');out=[t[i].img.copy() for i in range(1,len(t)+1)]
    lua.execute('captured={}');return out

def save_gif(name,images,scale=2/3,hold=18):
    if not images:return
    w,h=images[0].size;size=(int(w*scale),int(h*scale))
    seq=[im.resize(size,Image.Resampling.LANCZOS).convert('P',palette=Image.Palette.ADAPTIVE,colors=32) for im in images]
    seq+= [seq[-1]]*hold
    seq[0].save(MEDIA/name,save_all=True,append_images=seq[1:],duration=33,loop=0,optimize=True,disposal=1)
    print(name,len(images),'frames')

def bayer(im):
    """Ordered 8×8 dithering to pure black/white (simulation)."""
    m=[[0,32,8,40,2,34,10,42],[48,16,56,24,50,18,58,26],[12,44,4,36,14,46,6,38],[60,28,52,20,62,30,54,22],
       [3,35,11,43,1,33,9,41],[51,19,59,27,49,17,57,25],[15,47,7,39,13,45,5,37],[63,31,55,23,61,29,53,21]]
    src=im.load();out=Image.new('L',im.size,255);dst=out.load()
    for y in range(im.height):
        row=m[y%8]
        for x in range(im.width):dst[x,y]=0 if src[x,y]<(row[x%8]+.5)*4 else 255
    return out

def device(screen,label=None):
    """Hand-drawn reader silhouette around a screenshot."""
    sw,sh=screen.size;b=46;canvas=Image.new('L',(sw+2*b,sh+2*b+70),0)
    d=ImageDraw.Draw(canvas);d.rounded_rectangle((0,0,canvas.width-1,canvas.height-1),radius=48,fill=34,outline=12,width=3)
    d.rounded_rectangle((b-6,b-6,b+sw+5,b+sh+5),radius=10,fill=20)
    canvas.paste(screen,(b,b))
    if label:d.text((canvas.width//2,sh+2*b+20),label,font=ImageFont.truetype(FONT,26),fill=150,anchor='mm')
    return canvas

def main():
    r=Runtime();app=r.app();g=r.lua.globals();g.app=app
    lua=r.lua;lua.execute(SETUP);lua.execute(CAPTURE)
    # A richer collection for the pictures: three personal variants.
    lua.execute(r'''
        local C=load_module('core/collection');local s=app.settings.data
        for _,id in ipairs({'halo','journal','duplex'})do C.add(s,app:face(id))end
        C.select(s,s.collection[1]);app.settings:save(s)
        st=studio();run(.3)
    ''')
    shots={}
    # Gallery with neighbours peeking.
    lua.execute("st.browser_index=2;st:syncCarousel(false);st:refresh();run(.5)")
    shots['atelier-galerie.png']=lua.eval('snapshot()').img.copy()
    # Carousel animation: two flicks forward, one back.
    lua.execute("captured={};recording=true")
    lua.execute(r'''
        local b=st.carousel_box;local cx,cy=b.x+b.w*.7,b.y+b.h/2
        drag(cx,cy,-260,0,8,1/60);run(.7)
        drag(cx,cy,-300,0,7,1/60);run(.7)
        drag(cx-260,cy,320,0,8,1/60);run(.8)
        recording=false
    ''')
    save_gif('carrousel.gif',frames(lua))
    # Catalogue.
    lua.execute("tap(find('segment',2));run(.8)")
    shots['atelier-catalogue.png']=lua.eval('snapshot()').img.copy()
    lua.execute("tap(find('segment',1));run(.8)")
    # Tabs: slide + gliding pill + counters.
    lua.execute("captured={};recording=true")
    lua.execute(r'''
        tap(find('tab','Composer'));run(.6)
        tap(find('tab','Veille'));run(.6)
        tap(find('tab','Diagnostic'));run(1.3)
        tap(find('tab','Galerie'));run(.7)
        recording=false
    ''')
    save_gif('onglets.gif',frames(lua))
    # Modules: slot → sheet → choice → ghost flight → pulse.
    lua.execute("tap(find('tab','Composer'));run(.7)")
    shots['atelier-composer.png']=lua.eval('snapshot()').img.copy()
    lua.execute("captured={};recording=true")
    lua.execute(r'''
        local target;for _,r in ipairs((function()st:compose();return st.regions end)())do if r.slot_id then target=r end end
        tap(target);run(.5)
        recording=false;sheet_shot=snapshot();recording=true
        tap(find('provider','day'));run(1.8)
        recording=false
    ''')
    save_gif('modules.gif',frames(lua))
    shots['atelier-modules.png']=lua.eval('sheet_shot').img.copy()
    lua.execute("tap(find('mode','style'));run(.8)")
    shots['atelier-style.png']=lua.eval('snapshot()').img.copy()
    lua.execute("tap(find('mode','options'));run(.8)")
    shots['atelier-options.png']=lua.eval('snapshot()').img.copy()
    # Veille: gliding frequency, switch, draft bar, inertial scroll.
    lua.execute("tap(find('tab','Veille'));run(.8)")
    lua.execute("captured={};recording=true")
    lua.execute(r'''
        tap(find('interval',300));run(.6)
        tap(find('interval',60));run(.6)
        local v=st:viewport();drag(v.w/2,v.y+v.h*.8,0,-420,6,1/60);run(1.4)
        local row=find('key','reuse_suspend') or find('key','quiet');if row then tap(row);run(.6)end
        drag(v.w/2,v.y+v.h*.3,0,500,6,1/60);run(1.2)
        recording=false
    ''')
    save_gif('reglages.gif',frames(lua))
    lua.execute("st:cancelDraft();run(3);st.scroll:scrollTo(0,false);st:refresh();run(3)")
    shots['atelier-veille.png']=lua.eval('snapshot()').img.copy()
    lua.execute("tap(find('tab','Diagnostic'));run(1.5)")
    shots['atelier-diagnostic.png']=lua.eval('snapshot()').img.copy()
    # More sheet and confirmation.
    lua.execute("tap(find('tab','Galerie'));run(.7);tap(find('action','more'));run(.7)")
    shots['atelier-actions.png']=lua.eval('snapshot()').img.copy()
    lua.execute("st:closeSheet();run(.6)")
    # Portal: preview grows into the full-screen clock.
    lua.execute(r'''
        captured={};recording=true
        local play=find('action','play')
        local launched=false;local launch=app.launch;app.launch=function()launched=true end
        tap(play);run(1)
        recording=false;app.launch=launch
    ''')
    save_gif('afficher.gif',frames(lua))
    for name,im in shots.items():
        im.save(SHOTS/name);print(name)
    # Hero: three screens on hand-drawn readers, plus a Bayer panel view.
    trio=[device(shots['atelier-galerie.png'],'Cadrans'),device(shots['atelier-modules.png'],'Modules'),device(shots['atelier-veille.png'],'Veille')]
    tw=sum(t.width for t in trio)+80*4;th=trio[0].height+160
    hero=Image.new('L',(tw,th),244);x=80
    for t in trio:hero.paste(t,(x,80));x+=t.width+80
    hero=hero.resize((hero.width//2,hero.height//2),Image.Resampling.LANCZOS);hero.save(MEDIA/'hero.png');print('hero.png')
    dither=bayer(shots['atelier-galerie.png'])
    pair=Image.new('L',(758*2+60,1024+90),244)
    pair.paste(shots['atelier-galerie.png'],(0,0));pair.paste(dither,(758+60,0))
    d=ImageDraw.Draw(pair);f=ImageFont.truetype(FONT,26)
    d.text((379,1060),'Image composée (8 bits)',font=f,fill=60,anchor='mm')
    d.text((758+60+379,1060),'Tramage Bayer 8×8 simulé',font=f,fill=60,anchor='mm')
    pair.resize((pair.width//2,pair.height//2),Image.Resampling.LANCZOS).save(MEDIA/'tramage.png');print('tramage.png')
    lua.execute('st:onCloseWidget()');r.close()

if __name__=='__main__':main()
