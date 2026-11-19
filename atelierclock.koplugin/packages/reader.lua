local load=...
local U=load("core/util")
local ZIP=load("packages/zip")
local R={}
local allowed={text=true,image=true,hands=true,progress=true,rule=true,words=true,stack=true,dual=true}
local sources={time=true,date=true,battery=true,wifi=true,memory=true,world=true,ampm=true,label=true}
local function finite(n,a,b) return type(n)=="number" and n==n and n>=a and n<=b end
local function depth(s)
    local n,quoted,escape=0,false,false
    for i=1,#s do local c=s:sub(i,i)
        if escape then escape=false elseif quoted and c=="\\" then escape=true elseif c=='"' then quoted=not quoted
        elseif not quoted then
            if c=="{" or c=="[" then n=n+1;assert(n<=24,"JSON trop profond")
            elseif c=="}" or c=="]" then n=n-1 end
        end
    end
end
function R.validate(m,entries)
    assert(type(m)=="table" and m.format=="atelier-clock" and (m.schema_version==1 or m.schema_version==2),"Format .clock inconnu")
    if m.engine_min~=nil then
        assert(type(m.engine_min)=="string","Version du moteur invalide")
        local major,minor,patch=m.engine_min:match("^(%d+)%.(%d+)%.(%d+)$")
        assert(major and tonumber(major)==0 and tonumber(minor)<=2 and (tonumber(minor)<2 or tonumber(patch)==0),"Moteur du plugin trop ancien")
    end
    assert(type(m.id)=="string" and #m.id<=64 and m.id:match("^[a-z][a-z0-9_-]+$"),"Identifiant invalide")
    assert(type(m.name)=="string" and #m.name>0 and #m.name<100,"Nom invalide")
    assert(m.order==nil or finite(m.order,0,10000),"Ordre invalide")
    assert(m.subtitle==nil or type(m.subtitle)=="string" and #m.subtitle<150,"Sous-titre invalide")
    assert(type(m.author)=="string" and type(m.license)=="string","Auteur/licence absents")
    assert(type(m.canvas)=="table" and finite(m.canvas.width,100,3000) and finite(m.canvas.height,100,3000),"Dimensions invalides")
    if m.schema_version==2 then return load("packages/v2").validate(m,entries) end
    assert(type(m.layers)=="table" and #m.layers>0 and #m.layers<=48,"Calques invalides")
    assert(type(m.assets)=="table" and type(m.preview)=="string" and entries[m.preview],"Ressources absentes")
    for id,path in pairs(m.assets) do assert(type(id)=="string" and type(path)=="string" and entries[path] and path:match("%.png$"),"Texture absente") end
    local ids={}
    for _,l in ipairs(m.layers) do
        assert(type(l)=="table" and allowed[l.type],"Type de calque inconnu")
        assert(type(l.id)=="string" and not ids[l.id],"Identifiant de calque dupliqué");ids[l.id]=true
        if l.type=="image" then assert(m.assets[l.asset],"Texture inconnue") end
        if l.source then assert(sources[l.source],"Source inconnue") end
        for _,key in ipairs({"x","y","w","h","size","z","width","radius"}) do
            if l[key]~=nil then assert(finite(l[key],-3000,3000),"Coordonnée invalide") end
        end
        assert(l.text==nil or type(l.text)=="string" and #l.text<=256,"Texte invalide")
        assert(l.align==nil or l.align=="left" or l.align=="center" or l.align=="right","Alignement invalide")
        assert(l.grey==nil or finite(l.grey,0,255),"Couleur invalide")
        assert(l.bold==nil or type(l.bold)=="boolean","Graisse invalide")
        for _,key in ipairs({"w","h","radius","size"}) do if l[key]~=nil then assert(l[key]>0,"Taille de calque négative ou nulle") end end
        assert(l.w==nil or l.w<=1,"Largeur de calque hors écran")
        assert(l.h==nil or l.h<=1,"Hauteur de calque hors écran")
        assert(l.radius==nil or l.radius<=0.5,"Rayon trop grand")
        assert(l.size==nil or l.size<=300,"Taille de police du paquet trop grande")
        if l.type=="image" then
            local x,y,w,h=l.x or 0,l.y or 0,l.w or 1,l.h or 1
            assert(x>=0 and y>=0 and x+w<=1 and y+h<=1,"Texture hors limites du viewport")
        end
        assert(l.font==nil or l.font=="cfont" or l.font=="tfont" or l.font=="ffont","Police de paquet inconnue")
    end
    return m
end
local function pngPixels(b)
    assert(b:sub(1,8)=="\137PNG\13\10\26\10" and b:sub(13,16)=="IHDR","PNG invalide")
    local function be(i)local a,c,d,e=b:byte(i,i+3);assert(e,"PNG tronqué");return ((a*256+c)*256+d)*256+e end
    local w,h=be(17),be(21)
    assert(w>0 and h>0 and w*h<=4000000,"Texture trop grande")
    return w*h
end
function R.open(path,cache_root)
    local bytes=assert(U.read(path,16*1024*1024),"Paquet absent ou trop volumineux")
    local entries=ZIP.inspect(bytes)
    local Archive=require("ffi/archiver")
    local a=Archive.Reader:new()
    assert(a:open(path),"Impossible d'ouvrir le ZIP")
    local ok,result=pcall(function()
        local seen={}
        for entry in a:iterate() do
            assert(entries[entry.path] and entry.mode=="file" and tonumber(entry.size)==entries[entry.path].size,"Entrée ZIP non conforme")
            assert(not seen[entry.path],"Entrée ZIP dupliquée");seen[entry.path]=true
        end
        assert(not a.err,"Lecture ZIP interrompue")
        for name in pairs(entries) do assert(seen[name],"Entrée ZIP manquante") end
        local data=assert(a:extractToMemory("manifest.json"),"Manifeste illisible")
        depth(data);local m=R.validate(require("json").decode(data),entries)
        local payload={};local total=0
        for name,entry in pairs(entries) do
            if name:match("%.png$") then
                local b=assert(a:extractToMemory(name),"Texture illisible")
                assert(#b==entry.size,"Texture tronquée");total=total+pngPixels(b)
                assert(total<=12000000,"Budget de pixels dépassé");payload[name]=b
            elseif name~="manifest.json" and not name:match("%.txt$") then error("Ressource non autorisée : "..name) end
        end
        assert(payload[m.preview],"Aperçu PNG absent")
        -- Cache identity is an implementation detail, never an authenticity claim.
        local hash=5381;for i=1,#bytes do hash=(hash*33+bytes:byte(i))%2147483647 end
        local dest=cache_root.."/"..m.id.."-"..hash
        assert(U.mkdir(dest))
        for name,b in pairs(payload) do
            local p=dest.."/"..name;local parent=p:match("^(.*)/[^/]+$");assert(U.mkdir(parent))
            assert(U.write(p..".tmp",b));assert(os.rename(p..".tmp",p))
        end
        m.dir=dest;m.path=path;return m
    end)
    a:close();if not ok then error(result) end
    return result
end
return R
