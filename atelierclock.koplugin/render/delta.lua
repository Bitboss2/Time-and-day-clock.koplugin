-- Read only our own, unrotated BB8 tiles. Never read the device framebuffer.
-- Eight tight horizontal bands bound both bookkeeping and EPDC submissions.
local BB=require("ffi/blitbuffer")
local ffi=require("ffi")
local jit_ok,JIT=pcall(require,"jit")
ffi.cdef[[int memcmp(const void *s1, const void *s2, size_t n);]]
local memcmp=ffi.C.memcmp
local D={}
local function union(a,b)
    local x,y=math.min(a.x,b.x),math.min(a.y,b.y)
    return {x=x,y=y,w=math.max(a.x+a.w,b.x+b.w)-x,h=math.max(a.y+a.h,b.y+b.h)-y}
end
local function touches(a,b)
    return a.x<=b.x+b.w and b.x<=a.x+a.w and a.y<=b.y+b.h and b.y<=a.y+a.h
end
function D.area(regions)
    local n=0;for _,r in ipairs(regions or {})do n=n+r.w*r.h end;return n
end
-- Match UIManager's overlap/edge merging before limiting command count.
-- Greedily combine the least expensive pair, rather than expanding every
-- disconnected change to a single bounding rectangle.
function D.plan(regions,limit)
    local out={}
    local function insert(r)
        for i=#out,1,-1 do
            if touches(r,out[i])then
                local joined=union(r,table.remove(out,i));return insert(joined)
            end
        end
        out[#out+1]=r
    end
    for _,r in ipairs(regions)do if r.w>0 and r.h>0 then insert({x=r.x,y=r.y,w=r.w,h=r.h})end end
    while #out>limit do
        local ai,bi,best=1,2,math.huge
        for i=1,#out-1 do for j=i+1,#out do
            local r=union(out[i],out[j]);local cost=r.w*r.h-out[i].w*out[i].h-out[j].w*out[j].h
            if cost<best then ai,bi,best=i,j,cost end
        end end
        local joined=union(out[ai],out[bi]);table.remove(out,bi);table.remove(out,ai);insert(joined)
    end
    return out
end
function D.scan(a,b)
    -- If a future buffer implementation changes, return nil for the existing
    -- conservative ink bounds. Never fall back to interpreted pixel getters.
    if not jit_ok or not JIT.status()then return nil end
    if not a or not b or not a.getType or not b.getType
        or not a.getRotation or not b.getRotation or not a.getInverse or not b.getInverse
        or a:getType()~=BB.TYPE_BB8 or b:getType()~=BB.TYPE_BB8
        or a:getRotation()~=0 or b:getRotation()~=0 or a:getInverse()~=b:getInverse()then return nil end
    local w,h=a:getWidth(),a:getHeight()
    if w<=0 or h<=0 or w~=b:getWidth()or h~=b:getHeight()or w*h>1048576 then return nil end
    local sa,sb=tonumber(a.stride),tonumber(b.stride)
    if not sa or not sb or sa<w or sb<w then return nil end
    local pa,pb=a.data,b.data
    if type(pa)~="cdata"or type(pb)~="cdata"or pa==nil or pb==nil then return nil end
    pa=ffi.cast("const uint8_t*",pa);pb=ffi.cast("const uint8_t*",pb)
    local out={};local step=math.max(1,math.ceil(h/8))
    for top=0,h-1,step do
        local left,right,first,last=w,-1,h,-1
        for y=top,math.min(h-1,top+step-1)do
            local oa,ob=y*sa,y*sb
            if memcmp(pa+oa,pb+ob,w)~=0 then
                -- The middle of the current band is already covered. Search
                -- only for changes extending its horizontal bounds; native
                -- memcmp skips identical rows (including blank space).
                for x=0,left-1 do if pa[oa+x]~=pb[ob+x]then left=x;break end end
                for x=w-1,right+1,-1 do if pa[oa+x]~=pb[ob+x]then right=x;break end end
                if y<first then first=y end;last=y
            end
        end
        if right>=left then out[#out+1]={x=left,y=first,w=right-left+1,h=last-first+1}end
    end
    return out,w*h
end
return D
