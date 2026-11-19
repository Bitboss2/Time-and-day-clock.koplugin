"""Build ten original, declarative .clock v2 faces. No Apple artwork or fonts.
The preview PNGs are subsequently rendered by the real Lua renderer in tests.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import io, json, math, zipfile
ROOT=Path(__file__).resolve().parents[1]
PLUGIN=ROOT/'atelierclock.koplugin'
W,H=758,1024
PROVIDERS=['none','date','battery','day','week','world','book']
def block(id,type,box,**kw):return dict(id=id,type=type,box=box,**kw)
def slot(id,label,family,default):return dict(id=id,label=label,family=family,default=default,allowed=PROVIDERS)
def layout(blocks,**slots):return dict(blocks=blocks,slots=slots)
def png(im):
    s=io.BytesIO();im.save(s,format='PNG',optimize=True);return s.getvalue()
def designs():
    B=block;S=slot;L=layout
    return [
    ('totem','Totem','Deux étages, chiffres monumentaux','Typographique',
     [S('date','Bas gauche','inline','date'),S('charge','Bas droite','circle','battery')],
     L([B('hours','digits',[.08,.07,.84,.34],part='hour'),B('minutes','digits',[.08,.43,.84,.34],part='minute')],date=[.06,.83,.58,.09],charge=[.73,.79,.21,.15]),
     L([B('hours','digits',[.06,.08,.40,.57],part='hour'),B('minutes','digits',[.54,.08,.40,.57],part='minute')],date=[.08,.77,.56,.13],charge=[.76,.72,.17,.22])),
    ('duplex','Duplex','Deux panneaux, deux informations','StandBy',
     [S('left','Panneau gauche','rect','date'),S('right','Panneau droite','rect','world')],
     L([B('hours','digits',[.05,.13,.43,.44],part='hour',invert=True),B('minutes','digits',[.52,.13,.43,.44],part='minute')],left=[.05,.66,.43,.26],right=[.52,.66,.43,.26]),
     L([B('hours','digits',[.04,.08,.43,.51],part='hour',invert=True),B('minutes','digits',[.53,.08,.43,.51],part='minute')],left=[.04,.65,.43,.27],right=[.53,.65,.43,.27])),
    ('index','Index','Une règle de 24 heures, le temps en marge','Instrument',
     [S('left','Sous l’heure à gauche','rect','battery'),S('right','Sous l’heure à droite','rect','week')],
     L([B('rail','timeline',[.04,.10,.15,.78]),B('time','digits',[.24,.21,.70,.24],part='time'),B('label','label',[.24,.09,.70,.055],text='LE FIL DU JOUR')],left=[.24,.60,.32,.26],right=[.62,.60,.32,.26]),
     L([B('rail','timeline',[.05,.74,.90,.14]),B('time','digits',[.05,.12,.54,.42],part='time')],left=[.66,.10,.29,.26],right=[.66,.41,.29,.26])),
    ('halo','Halo','Aiguilles fines, deux anneaux utiles','Analogique',
     [S('left','Anneau gauche','circle','battery'),S('right','Anneau droite','circle','day')],
     L([B('dial','analog',[.05,.07,.90,.66],design='baton')],left=[.13,.77,.28,.18],right=[.59,.77,.28,.18]),
     L([B('dial','analog',[.03,.05,.61,.86],design='baton')],left=[.70,.10,.23,.32],right=[.70,.53,.23,.32])),
    ('journal','Journal','L’heure et tout le mois en un regard','Calendrier',
     [S('footer','Sous le calendrier','inline','date'),S('charge','Petit cartouche','rect','battery')],
     L([B('time','digits',[.08,.04,.84,.21],part='time'),B('month','calendar',[.08,.31,.84,.45])],footer=[.08,.83,.53,.10],charge=[.66,.80,.26,.14]),
     L([B('time','digits',[.04,.07,.43,.29],part='time'),B('month','calendar',[.52,.08,.44,.79])],footer=[.04,.44,.43,.13],charge=[.04,.65,.43,.24])),
    ('lisiere','Lisière','Relief à l’encre, lecture au calme','Paysage',
     [S('date','Ligne sous l’heure','inline','date'),S('charge','Sceau dans le paysage','circle','battery')],
     L([B('time','digits',[.08,.13,.84,.21],part='time')],date=[.08,.39,.84,.09],charge=[.68,.74,.24,.18]),
     L([B('time','digits',[.04,.11,.55,.31],part='time')],date=[.04,.48,.55,.11],charge=[.72,.65,.22,.27])),
    ('mosaique','Mosaïque','Trois modules autour d’une grande heure','Modulaire',
     [S('wide','Grand module','large','book'),S('left','Module gauche','rect','date'),S('right','Module droite','rect','battery')],
     L([B('time','digits',[.06,.06,.88,.22],part='time')],wide=[.06,.36,.88,.25],left=[.06,.67,.41,.26],right=[.53,.67,.41,.26]),
     L([B('time','digits',[.04,.06,.48,.34],part='time')],wide=[.57,.06,.39,.82],left=[.04,.50,.22,.38],right=[.30,.50,.22,.38])),
    ('octant','Octant','Heure en médaillon, minutes en arc','Radial',
     [S('top','Au-dessus du cadran','inline','date'),S('bottom','Sous le cadran','inline','world')],
     L([B('dial','analog',[.04,.22,.92,.53],design='sector')],top=[.08,.07,.84,.09],bottom=[.08,.84,.84,.09]),
     L([B('dial','analog',[.04,.07,.60,.83],design='sector')],top=[.69,.18,.27,.20],bottom=[.69,.57,.27,.20])),
    ('typo','Typo','Le temps comme une phrase, composé en deux lignes','Littéraire',
     [S('date','Signature','inline','date'),S('charge','Pied de page','inline','battery')],
     L([B('words','words',[.08,.22,.84,.42])],date=[.08,.74,.84,.09],charge=[.08,.86,.84,.07]),
     L([B('words','words',[.05,.14,.61,.67])],date=[.73,.17,.22,.25],charge=[.73,.57,.22,.20])),
    ('signal','Signal','Segments francs, précision sans animation','Numérique',
     [S('left','Ligne d’état gauche','inline','date'),S('right','Ligne d’état droite','inline','battery')],
     L([B('hours','segments',[.12,.08,.76,.33],part='hour'),B('minutes','segments',[.12,.45,.76,.33],part='minute')],left=[.05,.85,.57,.08],right=[.65,.85,.30,.08]),
     L([B('time','segments',[.06,.17,.88,.48],part='time')],left=[.06,.77,.56,.12],right=[.67,.77,.27,.12])),
    ]
def texture(id):
    im=Image.new('L',(W,H),255);d=ImageDraw.Draw(im)
    if id=='lisiere':
        for n in range(7):
            points=[(x,610+n*46+math.sin(x/135+n*.7)*42+math.sin(x/47+n)*12)for x in range(0,W+4,4)]
            d.line(points,fill=0,width=2 if n%2==0 else 1)
        d.ellipse((112,571,188,647),outline=0,width=3)
        d.rectangle((int(W*.66),int(H*.71),int(W*.94),int(H*.94)),fill=255)
    elif id=='typo':
        d.rectangle((34,161,39,656),fill=0);d.line((61,704,697,704),fill=0,width=2)
    elif id=='duplex':
        for x in (int(W*.05),int(W*.52)):d.line((x,100,x+int(W*.43),100),fill=0,width=5)
    elif id=='index':d.line((int(W*.22),80,int(W*.22),931),fill=0,width=2)
    elif id=='journal':d.line((60,289,698,289),fill=0,width=4)
    elif id=='octant':
        for x,y in [(30,210),(728,210),(30,800),(728,800)]:d.rectangle((x-3,y-3,x+3,y+3),fill=0)
    return im

def landscape_texture(id):
    w,h=1024,758;im=Image.new('L',(w,h),255);d=ImageDraw.Draw(im)
    if id=='lisiere':
        for n in range(6):
            pts=[(x,520+n*37+math.sin(x/175+n*.7)*30+math.sin(x/69+n)*9)for x in range(0,w+4,4)]
            d.line(pts,fill=0,width=2 if n%2==0 else 1)
        d.ellipse((590,430,650,490),outline=0,width=3)
        d.rectangle((int(w*.70),int(h*.62),int(w*.96),int(h*.94)),fill=255)
    elif id=='typo':d.rectangle((26,100,31,650),fill=0)
    elif id=='duplex':
        for x in (int(w*.04),int(w*.53)):d.line((x,40,x+int(w*.43),40),fill=0,width=4)
    elif id=='index':d.line((50,520,974,520),fill=0,width=2)
    elif id=='journal':d.line((40,310,480,310),fill=0,width=3)
    return im

def build():
    folder=PLUGIN/'clocks';folder.mkdir(exist_ok=True)
    for p in folder.glob('*.clock'):p.unlink()
    for n,(id,name,subtitle,category,slots,portrait,landscape)in enumerate(designs(),1):
        m=dict(format='atelier-clock',schema_version=2,engine_min='0.2.0',id=id,name=name,subtitle=subtitle,category=category,
               author='Atelier Clock — création originale',license='CC0-1.0',version='2.0.0',order=n,
               canvas=dict(width=W,height=H),orientations=['portrait','landscape'],preview='preview.png',
               assets=dict(background='textures/background.png',landscape='textures/landscape.png'),texture='background',texture_landscape='landscape',styles=['plein','fin'] if id in ['halo','octant','signal']else ['plein','fin','contour'],
               slots=slots,layouts=dict(portrait=portrait,landscape=landscape))
        bg=png(texture(id))
        with zipfile.ZipFile(folder/f'{id}.clock','w',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
            for path,data in [('manifest.json',json.dumps(m,ensure_ascii=False,indent=2).encode()),('textures/background.png',bg),('textures/landscape.png',png(landscape_texture(id))),('preview.png',bg)]:
                info=zipfile.ZipInfo(path,(2026,10,30,0,0,0));info.compress_type=8;info.external_attr=0o100644<<16;z.writestr(info,data)
        print(id)
if __name__=='__main__':build()
