-- Atelier design system: tokens and components drawn on 8-bit BlitBuffers.
-- Paper and ink first; grey only for depth and hierarchy (Fluid Ink dithers it,
-- the classic path shows it with KOReader's grey waveforms).
local load=...
local D=load("render/draw")
local Icon=load("ui/icons")
local K={}
K.ink,K.paper=0,255
K.muted=88      -- secondary text
K.line=200      -- hairlines
K.wash=238      -- subtle fills
K.shade=214     -- shadows / pressed
K.scrim=.42     -- dim behind sheets
K.size={display=34,title=27,heading=21,body=19,small=16,micro=13}
function K.new(k)return setmetatable({k=k},{__index=K})end
function K:u(n)return n*self.k end
function K:text(bb,text,x,y,size,c,align,width,bold)
    return D.label(bb,text,x,y,self:u(size),c or 0,align or "left",width,"cfont",bold)
end
function K:measure(text,size,bold)return D.text(nil,text,0,0,self:u(size),0,"left",nil,"cfont",bold,0,true)end
-- Card with a soft offset shadow: depth without noise.
function K:card(bb,x,y,w,h,o)
    o=o or {};local r=o.radius or self:u(18)
    if o.shadow~=false then D.round(bb,x+self:u(2),y+self:u(4),w,h,r,o.shadow_color or K.shade)end
    D.round(bb,x,y,w,h,r,o.fill or K.paper)
    if o.stroke~=false then D.roundBorder(bb,x,y,w,h,r,o.stroke_color or 0,o.stroke_width or math.max(2,self:u(1.5)))end
end
-- Pill button. style: primary (ink), secondary (outlined), ghost (text only), soft (wash).
function K:button(bb,x,y,w,h,label,o)
    o=o or {};local style=o.style or "secondary";local r=h/2
    local fill,ink=K.paper,0
    if style=="primary"then fill,ink=0,255 elseif style=="soft"then fill=K.wash end
    if style~="ghost"then D.round(bb,x,y,w,h,r,fill)end
    if style=="secondary"then D.roundBorder(bb,x,y,w,h,r,0,math.max(2,self:u(1.5)))end
    local icon=o.icon;local isz=self:u(o.icon_size or 22)
    local tw=label and label~=""and self:measure(label,o.size or K.size.body,style=="primary").w or 0
    if tw>w-self:u(28)-(icon and isz+self:u(8)or 0)then tw=w-self:u(28)-(icon and isz+self:u(8)or 0)end
    local total=tw+(icon and(isz+(tw>0 and self:u(9)or 0))or 0)
    local cx=x+(w-total)/2
    if icon then Icon.draw(bb,icon,cx,y+(h-isz)/2,isz,ink);cx=cx+isz+self:u(9)end
    if tw>0 then
        local sz=self:u(o.size or K.size.body)
        local m=D.text(nil,label,0,0,sz,0,"left",nil,"cfont",style=="primary",0,true)
        D.label(bb,label,cx,y+(h-m.h)/2+self:u(1),sz,ink,"left",tw+2,"cfont",style=="primary")
    end
end
function K:iconButton(bb,x,y,size,icon,o)
    o=o or {};local filled=o.filled
    if o.ring~=false or filled then
        D.circle(bb,x+size/2,y+size/2,size/2,filled and 0 or(o.fill or K.paper))
        if not filled and o.ring~=false then D.ring(bb,x+size/2,y+size/2,size/2-1,0,math.max(2,self:u(1.5)))end
    end
    local isz=size*(o.scale or .52)
    Icon.draw(bb,icon,x+(size-isz)/2,y+(size-isz)/2,isz,filled and 255 or 0)
end
-- Switch; t in [0,1] is the knob position (animated by the caller).
function K:switch(bb,x,y,t,w,h)
    w=w or self:u(56);h=h or self:u(32);t=math.max(0,math.min(1,t))
    local fill=t>.5 and 0 or K.paper
    D.round(bb,x,y,w,h,h/2,fill)
    D.roundBorder(bb,x,y,w,h,h/2,0,math.max(2,self:u(1.5)))
    local r=h/2-self:u(4);local cx=x+h/2+(w-h)*t
    D.circle(bb,cx,y+h/2,r,t>.5 and 255 or 0)
    return {x=x,y=y,w=w,h=h}
end
-- Segmented control with a gliding indicator at fractional index `at`.
function K:segmented(bb,x,y,w,h,items,at)
    D.round(bb,x,y,w,h,h/2,K.wash)
    local n=#items;local sw=w/n;local pad=self:u(3)
    local ix=x+pad+(at-1)*sw
    D.round(bb,ix,y+pad,sw-2*pad,h-2*pad,(h-2*pad)/2,0)
    for i,item in ipairs(items)do
        local active=math.abs(at-i)<.5
        local label=type(item)=="table"and item.label or item
        local icon=type(item)=="table"and item.icon
        local cx=x+(i-1)*sw
        if icon then
            local isz=self:u(18);local tw=self:measure(label,K.size.small,active).w
            local total=math.min(sw-self:u(12),isz+self:u(6)+tw)
            Icon.draw(bb,icon,cx+(sw-total)/2,y+(h-isz)/2,isz,active and 255 or 0)
            self:text(bb,label,cx+(sw-total)/2+isz+self:u(6),y+(h-self:u(K.size.small))/2-self:u(1),K.size.small,active and 255 or 0,"left",total-isz-self:u(6),active)
        else
            self:text(bb,label,cx+sw/2,y+(h-self:u(K.size.small))/2-self:u(1),K.size.small,active and 255 or 0,"center",sw-self:u(10),active)
        end
    end
    return sw
end
-- List row: icon, title, subtitle, trailing value.
function K:row(bb,x,y,w,h,o)
    local pad=self:u(16);local tx=x+pad
    if o.icon then
        D.circle(bb,x+pad+self:u(18),y+h/2,self:u(18),K.wash)
        Icon.draw(bb,o.icon,x+pad+self:u(7),y+h/2-self:u(11),self:u(22),0);tx=x+pad+self:u(48)
    end
    local right=o.value and self:u(math.min(170,w/self.k*.42))or self:u(30)
    local tw=w-(tx-x)-right-pad
    if o.subtitle then
        self:text(bb,o.title,tx,y+h/2-self:u(23),K.size.body,0,"left",tw,true)
        self:text(bb,o.subtitle,tx,y+h/2+self:u(2),K.size.small,K.muted,"left",tw)
    else self:text(bb,o.title,tx,y+(h-self:u(K.size.body))/2-self:u(2),K.size.body,0,"left",tw,o.bold~=false)end
    if o.value then self:text(bb,o.value,x+w-pad-(o.chevron and self:u(18)or 0),y+(h-self:u(K.size.body))/2-self:u(2),K.size.body,K.muted,"right",right,false)end
    if o.chevron then Icon.draw(bb,"right",x+w-pad-self:u(14),y+h/2-self:u(8),self:u(16),K.muted)end
    if o.divider then D.rect(bb,tx,y+h-1,x+w-tx-pad,1,K.line)end
end
-- Grouped section title, in small caps style.
local accents={["é"]="É",["è"]="È",["ê"]="Ê",["ë"]="Ë",["à"]="À",["â"]="Â",["ç"]="Ç",["î"]="Î",["ï"]="Ï",["ô"]="Ô",["ù"]="Ù",["û"]="Û",["œ"]="Œ"}
function K.upper(s)
    s=tostring(s):upper()
    for a,b in pairs(accents)do s=s:gsub(a,b)end
    return s
end
function K:section(bb,label,x,y,w)
    self:text(bb,K.upper(label),x+self:u(6),y,K.size.micro+1,K.muted,"left",w,true)
end
-- Progress ring with a centred value.
function K:gauge(bb,cx,cy,r,fraction,label,caption)
    D.ring(bb,cx,cy,r,K.line,self:u(5))
    if fraction and fraction>0 then D.ring(bb,cx,cy,r,0,self:u(7),0,math.pi*2*math.min(1,fraction))end
    self:text(bb,label,cx,cy-self:u(caption and 20 or 14),K.size.title,0,"center",r*1.6,true)
    if caption then self:text(bb,caption,cx,cy+self:u(13),K.size.micro,K.muted,"center",r*1.5)end
end
-- Page dots; `at` fractional (the active dot stretches into a capsule).
function K:dots(bb,cx,y,n,at)
    if n<=1 then return end
    local gap=self:u(16);local r=self:u(3.5);local start=cx-(n-1)*gap/2
    for i=1,n do D.circle(bb,start+(i-1)*gap,y,r,K.line)end
    local ax=start+(math.max(1,math.min(n,at))-1)*gap;local w=r*2+self:u(12)
    D.round(bb,ax-w/2,y-r,w,r*2,r,0)
end
return K
