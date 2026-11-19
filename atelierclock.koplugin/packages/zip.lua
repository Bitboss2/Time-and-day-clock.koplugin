-- Small ZIP envelope validator. Decompression is delegated to libarchive.
-- Reject ZIP64, encryption, symlinks, extra payload and ambiguous member names.
local load=...
local U=load("core/util")
local Z={}
local function u16(s,i) local a,b=s:byte(i,i+1);assert(b,"ZIP tronqué");return a+b*256 end
local function u32(s,i) return u16(s,i)+u16(s,i+2)*65536 end
Z.u32=u32
function Z.inspect(s)
    assert(type(s)=="string" and #s<=16*1024*1024,"Archive trop volumineuse")
    assert(s:sub(1,4)=="PK\003\004","Un .clock doit être une archive ZIP")
    local e
    for i=#s-21,math.max(1,#s-65557),-1 do
        if s:sub(i,i+3)=="PK\005\006" and i+21+u16(s,i+20)==#s then e=i;break end
    end
    assert(e,"Fin ZIP absente")
    assert(u16(s,e+4)==0 and u16(s,e+6)==0,"ZIP multi-volume interdit")
    local count=u16(s,e+10);assert(count>0 and count<=128 and u16(s,e+8)==count,"Trop d'entrées")
    local start=u32(s,e+16)+1;local length=u32(s,e+12)
    assert(start+length==e,"Index ZIP invalide")
    local entries,total,p={},0,start
    local spans={}
    for _=1,count do
        assert(s:sub(p,p+3)=="PK\001\002","Entrée ZIP invalide")
        local flags,method=u16(s,p+8),u16(s,p+10)
        assert(flags%2==0 and math.floor(flags/64)%2==0,"Archive chiffrée interdite")
        assert(method==0 or method==8,"Compression non prise en charge")
        local comp,size=u32(s,p+20),u32(s,p+24)
        local nl,xl,cl=u16(s,p+28),u16(s,p+30),u16(s,p+32)
        local name=s:sub(p+46,p+45+nl)
        assert(#name==nl and U.safePath(name) and not entries[name],"Chemin ZIP invalide ou dupliqué")
        local mode=math.floor(u32(s,p+38)/65536)%65536
        local kind=math.floor(mode/4096)%16
        assert(kind==0 or kind==8,"Seuls les fichiers ordinaires sont acceptés")
        assert(u16(s,p+34)==0 and size<=8*1024*1024,"Fichier trop volumineux")
        if name=="manifest.json" then assert(size<=131072,"Manifeste trop volumineux") end
        total=total+size;assert(total<=48*1024*1024,"Paquet décompressé trop volumineux")
        local off=u32(s,p+42)+1
        assert(off>=1 and off<start and s:sub(off,off+3)=="PK\003\004","Entête local absent")
        assert(u16(s,off+6)==flags and u16(s,off+8)==method,"Entêtes ZIP contradictoires")
        local lnl,lxl=u16(s,off+26),u16(s,off+28)
        assert(lnl==nl and s:sub(off+30,off+29+lnl)==name,"Noms ZIP contradictoires")
        local finish=off+30+lnl+lxl+comp
        assert(finish<=start,"Données ZIP hors limites")
        if math.floor(flags/8)%2==0 then
            assert(u32(s,off+18)==comp and u32(s,off+22)==size and u32(s,off+14)==u32(s,p+16),"Tailles ZIP contradictoires")
        end
        spans[#spans+1]={off,finish}
        entries[name]={size=size,compressed=comp,crc=u32(s,p+16)}
        p=p+46+nl+xl+cl;assert(p<=e,"Index ZIP tronqué")
    end
    assert(p==e and entries["manifest.json"],"Manifeste absent ou index invalide")
    table.sort(spans,function(a,b)return a[1]<b[1] end)
    for i=2,#spans do assert(spans[i][1]>=spans[i-1][2],"Entrées ZIP superposées") end
    return entries
end
return Z
