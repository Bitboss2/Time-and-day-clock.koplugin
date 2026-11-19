local load=...
local C=load("core/collection")
local V={}
local kinds={digits=true,analog=true,calendar=true,words=true,timeline=true,segments=true,label=true}
local function number(n,a,b)return type(n)=="number"and n==n and n>=a and n<=b end
local function id(s)return type(s)=="string"and #s>0 and #s<=40 and s:match("^[a-zA-Z0-9_-]+$")end
local function box(r)
    assert(type(r)=="table"and #r==4,"Rectangle absent")
    for i=1,4 do assert(number(r[i],0,1),"Rectangle invalide")end
    assert(r[3]>.02 and r[4]>.02 and r[1]+r[3]<=1.00001 and r[2]+r[4]<=1.00001,"Rectangle hors écran")
end
function V.validate(m,entries)
    assert(type(m.assets)=="table"and type(m.preview)=="string"and entries[m.preview],"Aperçu absent")
    local count=0
    for name,path in pairs(m.assets)do
        count=count+1;assert(count<=16 and id(name)and type(path)=="string"and path:match("%.png$")and entries[path],"Texture invalide")
    end
    assert(m.texture==nil or m.assets[m.texture],"Fond inconnu")
    assert(m.texture_landscape==nil or m.assets[m.texture_landscape],"Fond paysage inconnu")
    assert(type(m.styles)=="table"and #m.styles>=1 and #m.styles<=3,"Styles invalides")
    local seen={};for _,style in ipairs(m.styles)do assert((style=="plein"or style=="fin"or style=="contour")and not seen[style],"Style inconnu");seen[style]=true end
    assert(type(m.slots)=="table"and #m.slots<=6,"Complications invalides")
    local slots={}
    for _,slot in ipairs(m.slots)do
        assert(id(slot.id)and not slots[slot.id],"Emplacement dupliqué");slots[slot.id]=slot
        assert(type(slot.label)=="string"and #slot.label<80,"Nom de complication invalide")
        assert(slot.family=="inline"or slot.family=="circle"or slot.family=="rect"or slot.family=="large","Famille inconnue")
        assert(type(slot.allowed)=="table"and #slot.allowed>0 and #slot.allowed<=7,"Sources absentes")
        local providers={};for _,p in ipairs(C.providers)do providers[p]=true end
        local unique={};for _,p in ipairs(slot.allowed)do assert(providers[p]and not unique[p],"Source inconnue");unique[p]=true end
        assert(unique[slot.default],"Source par défaut invalide")
    end
    assert(type(m.layouts)=="table","Dispositions absentes")
    for _,orientation in ipairs({"portrait","landscape"})do
        local layout=m.layouts[orientation];assert(type(layout)=="table","Disposition absente : "..orientation)
        assert(type(layout.blocks)=="table"and #layout.blocks>0 and #layout.blocks<=24,"Blocs invalides")
        assert(type(layout.slots)=="table","Positions de complications absentes")
        local ids={}
        for _,b in ipairs(layout.blocks)do
            assert(id(b.id)and not ids[b.id]and kinds[b.type],"Bloc inconnu ou dupliqué");ids[b.id]=true;box(b.box)
            assert(b.part==nil or b.part=="hour"or b.part=="minute"or b.part=="time","Partie invalide")
            assert(b.design==nil or b.design=="baton"or b.design=="sector"or b.design=="cardinal","Dessin invalide")
            assert(b.text==nil or type(b.text)=="string"and #b.text<=120,"Texte invalide")
            assert(b.invert==nil or type(b.invert)=="boolean","Inversion invalide")
            assert(b.type~="label"or type(b.text)=="string","Texte absent")
        end
        for name,r in pairs(layout.slots)do assert(slots[name],"Emplacement non déclaré");box(r)end
        for name in pairs(slots)do assert(layout.slots[name],"Emplacement sans position")end
        -- Bounded, nonoverlapping editing targets guarantee legibility. Blocks
        -- are also disjoint, so retained tiles can be redrawn independently.
        local all={};for _,b in ipairs(layout.blocks)do all[#all+1]=b.box end
        for _,r in pairs(layout.slots)do all[#all+1]=r end
        for i,a in ipairs(all)do for j=i+1,#all do local b=all[j]
            assert(a[1]>=b[1]+b[3]-.00001 or b[1]>=a[1]+a[3]-.00001 or a[2]>=b[2]+b[4]-.00001 or b[2]>=a[2]+a[4]-.00001,"Éléments superposés")
        end end
    end
    if m.preset~=nil then
        local preset=m.preset;assert(type(preset)=="table","Préréglage invalide")
        assert(seen[preset.style],"Style du préréglage inconnu")
        assert(preset.appearance=="paper"or preset.appearance=="ink"or preset.appearance=="follow","Apparence inconnue")
        assert(type(preset.slots)=="table","Préréglages de complications absents")
        for name,config in pairs(preset.slots)do
            assert(slots[name]and type(config)=="table"and C.allowed(slots[name],config.provider),"Préréglage de complication invalide")
            local valid=false;for _,z in ipairs(C.zones)do if config.zone==z then valid=true end end
            assert(valid,"Fuseau inconnu")
        end
    end
    return m
end
return V
