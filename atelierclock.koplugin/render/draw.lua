local D={}
local BB=require("ffi/blitbuffer")
local Font=require("ui/font")
local Text=require("ui/rendertext")
function D.color(n) return BB.Color8(math.floor(math.max(0,math.min(255,n)))) end
function D.rect(bb,x,y,w,h,c)
    local x1,y1=math.max(0,math.floor(x)),math.max(0,math.floor(y))
    local x2,y2=math.min(bb:getWidth(),math.ceil(x+w)),math.min(bb:getHeight(),math.ceil(y+h))
    if x2>x1 and y2>y1 then bb:paintRect(x1,y1,x2-x1,y2-y1,D.color(c)) end
end
function D.border(bb,x,y,w,h,c,t)
    t=t or 1;D.rect(bb,x,y,w,t,c);D.rect(bb,x,y+h-t,w,t,c);D.rect(bb,x,y,t,h,c);D.rect(bb,x+w-t,y,t,h,c)
end
function D.circle(bb,cx,cy,r,c)
    for dy=-math.ceil(r),math.ceil(r) do
        if math.abs(dy)<=r then local dx=math.sqrt(r*r-dy*dy);D.rect(bb,cx-dx,cy+dy,dx*2+1,1,c) end
    end
end
function D.line(bb,x1,y1,x2,y2,c,t)
    t=math.max(1,math.floor(t or 1))
    local dx,dy=x2-x1,y2-y1;local n=math.max(1,math.ceil(math.max(math.abs(dx),math.abs(dy))))
    for i=0,n do local f=i/n;D.rect(bb,x1+dx*f-t/2,y1+dy*f-t/2,t,t,c) end
end
function D.text(bb,text,x,y,size,c,align,width,font,bold,outline,measure_only)
    text=tostring(text or "");size=math.max(7,math.floor(size))
    -- Font:getFace scales by device DPI; scene coordinates already use pixels.
    local screen=require("device").screen
    local factor=screen:scaleBySize(100)/100
    local ok,face=pcall(Font.getFace,Font,font or "cfont",size/factor)
    if not ok then font="cfont";face=Font:getFace("cfont",size/factor) end
    if not face then return {x=x,y=y,w=0,h=size} end
    local metrics=Text:sizeUtf8Text(0,nil,face,text,true,bold)
    if width and metrics.x>width then
        size=math.max(7,math.floor(size*width/metrics.x))
        face=Font:getFace(font or "cfont",size/factor)
        metrics=Text:sizeUtf8Text(0,nil,face,text,true,bold)
    end
    local left=x
    if align=="center" then left=x-metrics.x/2 elseif align=="right" then left=x-metrics.x end
    local baseline=y+metrics.y_top
    left=math.floor(left);baseline=math.floor(baseline)
    local rect={x=left-2-(outline or 0),y=math.floor(y)-2-(outline or 0),w=metrics.x+4+2*(outline or 0),h=metrics.y_top+metrics.y_bottom+4+2*(outline or 0)}
    if measure_only then return rect end
    -- Outline is an optional e-ink stencil effect. Border colour is opposite ink.
    if outline and outline>0 then
        for _,v in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
            Text:renderUtf8Text(bb,left+v[1]*outline,baseline+v[2]*outline,face,text,true,bold,D.color(c),width)
        end
        Text:renderUtf8Text(bb,left,baseline,face,text,true,bold,D.color(255-c),width)
    else Text:renderUtf8Text(bb,left,baseline,face,text,true,bold,D.color(c),width) end
    return rect
end
function D.image(bb,path,x,y,w,h,invert)
    local Image=require("ui/widget/imagewidget")
    local widget=Image:new{file=path,width=math.floor(w),height=math.floor(h),scale_factor=nil,alpha=true,file_do_cache=false}
    local ok=pcall(widget.paintTo,widget,bb,math.floor(x),math.floor(y))
    widget:free()
    if not ok then return false end
    if invert then bb:invertRect(math.floor(x),math.floor(y),math.floor(w),math.floor(h)) end
    return true
end
function D.union(a,b)
    if not a then return b end;if not b then return a end
    local x,y=math.min(a.x,b.x),math.min(a.y,b.y)
    return {x=x,y=y,w=math.max(a.x+a.w,b.x+b.w)-x,h=math.max(a.y+a.h,b.y+b.h)-y}
end
-- UI labels keep their physical font size. Long labels are ellipsized instead
-- of silently becoming microscopic to fit one line.
function D.label(bb,text,x,y,size,c,align,width,font,bold)
    text=tostring(text or "")
    if width then
        local measure=D.text(bb,text,0,0,size,c,"left",nil,font,bold,0,true)
        if measure.w>width then
            local chars={};for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=char end
            while #chars>0 do
                chars[#chars]=nil
                local s=table.concat(chars).."…"
                if D.text(bb,s,0,0,size,c,"left",nil,font,bold,0,true).w<=width then text=s;break end
            end
        end
    end
    return D.text(bb,text,x,y,size,c,align,nil,font,bold)
end
-- Rounded shapes by scanlines: identical on every BlitBuffer backend and cheap
-- enough to be cached into layers.
local function inset(r,i)
    if i>=r then return 0 end
    local dy=r-i-.5;return r-math.sqrt(math.max(0,r*r-dy*dy))
end
function D.round(bb,x,y,w,h,r,c)
    r=math.max(0,math.min(r or 0,w/2,h/2))
    if r<1 then return D.rect(bb,x,y,w,h,c)end
    local rr=math.ceil(r)
    for i=0,rr-1 do local a=inset(r,i);D.rect(bb,x+a,y+i,w-2*a,1,c);D.rect(bb,x+a,y+h-1-i,w-2*a,1,c)end
    D.rect(bb,x,y+rr,w,h-2*rr,c)
end
function D.roundBorder(bb,x,y,w,h,r,c,t)
    t=math.max(1,t or 1);r=math.max(0,math.min(r or 0,w/2,h/2))
    if r<1 then return D.border(bb,x,y,w,h,c,t)end
    local rr=math.ceil(r);local ri=math.max(0,r-t)
    for i=0,rr-1 do
        local a=inset(r,i)
        for _,yy in ipairs({y+i,y+h-1-i})do
            if i<t then D.rect(bb,x+a,yy,w-2*a,1,c)
            else local b=t+(ri>0 and inset(ri,i-t)or 0);D.rect(bb,x+a,yy,b-a,1,c);D.rect(bb,x+w-b,yy,b-a,1,c)end
        end
    end
    D.rect(bb,x,y+rr,t,h-2*rr,c);D.rect(bb,x+w-t,y+rr,t,h-2*rr,c)
end
-- Line with round caps (hand-drawn icon strokes).
function D.stroke(bb,x1,y1,x2,y2,c,t)
    t=math.max(1,t or 1);D.line(bb,x1,y1,x2,y2,c,t)
    if t>=3 then D.circle(bb,x1,y1,t/2,c);D.circle(bb,x2,y2,t/2,c)end
end
function D.ring(bb,cx,cy,r,c,t,from,to)
    t=t or 1;from=from or 0;to=to or math.pi*2
    local n=math.max(12,math.ceil(r*(to-from)/2))
    local px,py
    for i=0,n do local a=from+(to-from)*i/n;local x,y=cx+math.sin(a)*r,cy-math.cos(a)*r
        if px then D.line(bb,px,py,x,y,c,t)end;px,py=x,y end
end
return D
