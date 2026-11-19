-- Retained, independent tiles: unchanged date/calendar/decoration is never
-- rasterized again on a minute tick. No animation or second-hand timer.
local load=...
local U=load("core/util")
local D=load("render/draw")
local Time=load("core/time")
local C=load("core/collection")
local BB=require("ffi/blitbuffer")
local Delta=load("render/delta")
local F={}
local function fit(bb,text,x,y,w,h,size,ink,font,bold,outline)
    local r=D.text(bb,text,0,0,size,ink,"left",w,font,bold,outline,true)
    if r.h>h then size=size*h/r.h;r=D.text(bb,text,0,0,size,ink,"left",w,font,bold,outline,true)end
    return D.text(bb,text,x+w/2,y+(h-r.h)/2+2,size,ink,"center",w,font,bold,outline)
end
local function arc(bb,x,y,r,f,ink,t,start)
    local steps=math.max(1,math.ceil(f*120));local a=start or -math.pi/2
    for i=1,steps do local b=a+f*math.pi*2/steps
        D.line(bb,x+math.cos(a)*r,y+math.sin(a)*r,x+math.cos(b)*r,y+math.sin(b)*r,ink,t);a=b
    end
end
function F.new(app,face,s,w,h)
    local self=setmetatable({app=app,face=face,s=U.copy(s),w=math.floor(w),h=math.floor(h),old={},tiles={},statics={},static_keys={},full=true,draws=0}, {__index=F})
    self.options=C.options(s,face);self.layout=face.layouts[w>h and "landscape"or "portrait"]
    self.book=app.readingSnapshot and app:readingSnapshot()or {}
    return self
end
function F:free()
    if self.base then self.base:free();self.base=nil end
    if self.frame then self.frame:free();self.frame=nil end
    for _,t in pairs(self.tiles)do t.bb:free()end;self.tiles={}
    for _,t in pairs(self.statics)do t:free()end;self.statics={}
end
function F:rect(r)
    local x,y=math.floor(r[1]*self.w),math.floor(r[2]*self.h)
    return {x=x,y=y,w=math.max(1,math.floor((r[1]+r[3])*self.w)-x),h=math.max(1,math.floor((r[2]+r[4])*self.h)-y)}
end
function F:background(now)
    local o=self.options;local dark=o.appearance=="ink"or o.appearance=="follow"and(self.s.night=="dark"or self.s.night=="follow"and G_reader_settings:isTrue("night_mode"))
    self.ink=dark and 255 or 0;self.bg=255-self.ink;self.dark=dark
    self.base=BB.new(self.w,self.h,BB.TYPE_BB8);self.base:fill(D.color(self.bg))
    local texture=self.face.texture
    if self.w>self.h then texture=self.face.texture_landscape end
    if texture then D.image(self.base,self.face.dir.."/"..self.face.assets[texture],0,0,self.w,self.h,dark)end
    self.frame=self.base:copy()
end
function F:tile(id,box,key,draw,source,kind)
    local r=self:rect(box);local old=self.tiles[id]
    self.old[id]={rect=r,key=key,source=source,type=kind}
    if old and old.key==key then return end
    local b=BB.new(r.w,r.h,BB.TYPE_BB8);b:blitFrom(self.base,0,0,r.x,r.y,r.w,r.h)
    local ink=draw(b,r.w,r.h)
    local local_dirty=ink and D.union(ink,old and old.ink)or {x=0,y=0,w=r.w,h=r.h}
    local x,y=math.max(0,math.floor(local_dirty.x)),math.max(0,math.floor(local_dirty.y))
    local clipped={x=r.x+x,y=r.y+y,w=math.max(0,math.min(r.w,math.ceil(local_dirty.x+local_dirty.w))-x),h=math.max(0,math.min(r.h,math.ceil(local_dirty.y+local_dirty.h))-y)}
    local bands,scanned,skipped;local policy=old and old.delta_policy or {samples=0,coarse=0,fine=0,cooldown=0}
    if old and policy.cooldown>0 then
        policy.cooldown=policy.cooldown-1;self.delta_skipped=self.delta_skipped+1;skipped=true
    elseif old then
        local ok,found,pixels=pcall(Delta.scan,old.bb,b)
        if ok then bands,scanned=found,pixels end
    end
    if old then old.bb:free()end
    self.delta_scanned_pixels=self.delta_scanned_pixels+(scanned or 0)
    -- Pixel evidence wins if a future draw function reports an incomplete ink
    -- box. Do not let the later area guard select an unsafe smaller fallback.
    if bands then for _,v in ipairs(bands)do
        if r.x+v.x<clipped.x or r.y+v.y<clipped.y
            or r.x+v.x+v.w>clipped.x+clipped.w or r.y+v.y+v.h>clipped.y+clipped.h then
            clipped={x=r.x,y=r.y,w=r.w,h=r.h};break
        end
    end end
    if bands then
        policy.samples=policy.samples+1;policy.coarse=policy.coarse+clipped.w*clipped.h
        policy.fine=policy.fine+Delta.area(Delta.plan(bands,4))
        if policy.samples>=3 then
            -- Avoid paying a pixel scan every minute when three observations
            -- save less than 20% of the requested area. Probe again after
            -- seven updates, since the value/drawing may become sparse later.
            if policy.coarse>0 and policy.fine>policy.coarse*.8 then policy.cooldown=7 end
            policy.samples=0;policy.coarse=0;policy.fine=0
        end
    end
    self.coarse_regions[#self.coarse_regions+1]=clipped
    if bands then
        for _,v in ipairs(bands)do self.regions[#self.regions+1]={x=r.x+v.x,y=r.y+v.y,w=v.w,h=v.h}end
    else
        self.regions[#self.regions+1]=clipped
        if old and not skipped then self.delta_fallbacks=self.delta_fallbacks+1 end
    end
    self.tiles[id]={bb=b,key=key,ink=ink,delta_policy=policy};self.frame:blitFrom(b,r.x,r.y,0,0,r.w,r.h)
    self.draws=self.draws+1
end
function F:block(b,now,values)
    local t=os.date("*t",now);local ink,bg=self.ink,self.bg
    local style=self.options.style;local bold=style~="fin";local font=style=="fin"and "tfont"or "cfont"
    local key,source="static","time"
    if b.type=="digits"or b.type=="segments"then
        key=b.part=="hour"and values.hour or b.part=="minute"and values.minute or values.time
        if b.part~="minute"then key=key..values.ampm end
    elseif b.type=="analog"or b.type=="words"then key=t.hour..":"..t.min
    elseif b.type=="timeline"then key=t.hour..":"..math.floor(t.min/5)
    elseif b.type=="calendar"then key=os.date("%Y-%m-%d",now);source="date"
    end
    self:tile(b.id,b.box,key,function(bb,w,h)
        local c,back=ink,bg
        if b.invert then c,back=bg,ink;D.rect(bb,0,0,w,h,back)end
        local small=math.min(w,h);local stroke=math.max(1,small*(style=="fin"and .0045 or .008))
        if b.type=="label"then fit(bb,b.text,0,0,w,h,h*.7,c,"cfont",false)
        elseif b.type=="digits"then
            local value=b.part=="hour"and values.hour or b.part=="minute"and values.minute or values.time
            local r=fit(bb,value,w*.02,h*.04,w*.96,h*.9,h*1.18,c,font,bold,style=="contour"and math.max(1,small*.012)or 0)
            if b.part~="minute"and values.ampm~=""then r=D.union(r,D.text(bb,values.ampm,w*.92,h*.02,h*.09,c,"right",w*.25,"cfont"))end
            return r
        elseif b.type=="segments"then
            local text=b.part=="hour"and values.hour or b.part=="minute"and values.minute or values.time
            local map={['0']={1,2,3,4,5,6},['1']={2,3},['2']={1,2,7,5,4},['3']={1,2,3,4,7},['4']={6,7,2,3},['5']={1,6,7,3,4},['6']={1,6,5,4,3,7},['7']={1,2,3},['8']={1,2,3,4,5,6,7},['9']={1,2,3,4,6,7}}
            if b.part~="minute"and values.ampm~=""then D.text(bb,values.ampm,w*.98,0,h*.065,c,"right",w*.20,"cfont")end
            local cells=#text;local cw=w/(cells+.12);local dh=math.min(h*.88,cw*1.9);local dw=dh*.48;local oy=(h-dh)/2
            for i=1,cells do local ch=text:sub(i,i);local x=(i-1)*cw+(cw-dw)/2;local thick=math.max(2,dh*(style=="fin"and .035 or .065));local mid=oy+dh/2
                if ch==":"then D.circle(bb,x+dw/2,oy+dh*.33,thick/2,c);D.circle(bb,x+dw/2,oy+dh*.67,thick/2,c)
                else local seg={{x+thick,oy,dw-2*thick,thick},{x+dw-thick,oy+thick,thick,dh/2-1.5*thick},{x+dw-thick,mid+thick/2,thick,dh/2-1.5*thick},{x+thick,oy+dh-thick,dw-2*thick,thick},{x,mid+thick/2,thick,dh/2-1.5*thick},{x,oy+thick,thick,dh/2-1.5*thick},{x+thick,mid-thick/2,dw-2*thick,thick}}
                    for _,n in ipairs(map[ch]or {})do local r=seg[n];D.rect(bb,r[1],r[2],r[3],r[4],c)end
                end
            end
        elseif b.type=="analog"then
            local cx,cy=w/2,h/2;local r=small*.46
            if b.design=="sector"then
                if self.statics[b.id]and self.static_keys[b.id]==t.hour then bb:blitFrom(self.statics[b.id],0,0,0,0,w,h)else
                if self.statics[b.id]then self.statics[b.id]:free()end
                for n=0,11 do local a=n*math.pi/6-math.pi/2
                    local px,py=cx+math.cos(a)*r*.81,cy+math.sin(a)*r*.81
                    if n==t.hour%12 then D.circle(bb,px,py,r*.14,c);fit(bb,n==0 and "12"or tostring(n),px-r*.11,py-r*.10,r*.22,r*.20,r*.19,back,"cfont",true)
                    else fit(bb,n==0 and "12"or tostring(n),px-r*.11,py-r*.10,r*.22,r*.20,r*.19,c,"cfont",false)end
                end
                self.statics[b.id]=bb:copy();self.static_keys[b.id]=t.hour
                end
                arc(bb,cx,cy,r,t.min/60,c,stroke*2)
            else
                local cached=self.statics[b.id]
                if cached then bb:blitFrom(cached,0,0,0,0,w,h)else
                for n=0,59 do local a=n*math.pi/30;local major=n%5==0
                    if b.design~="cardinal"or major then D.line(bb,cx+math.sin(a)*r*(major and .86 or .94),cy-math.cos(a)*r*(major and .86 or .94),cx+math.sin(a)*r,cy-math.cos(a)*r,c,major and stroke*1.5 or stroke*.55)end
                end
                if b.design=="cardinal"then for n=3,12,3 do local a=n*math.pi/6
                    fit(bb,tostring(n),cx+math.sin(a)*r*.65-r*.16,cy-math.cos(a)*r*.65-r*.12,r*.32,r*.24,r*.24,c,"cfont",bold)
                end end
                self.statics[b.id]=bb:copy()
                end
            end
            local hour=(t.hour%12+t.min/60)*math.pi/6-math.pi/2;local minute=t.min*math.pi/30-math.pi/2
            D.line(bb,cx,cy,cx+math.cos(hour)*r*.49,cy+math.sin(hour)*r*.49,c,stroke*3)
            D.line(bb,cx,cy,cx+math.cos(minute)*r*.72,cy+math.sin(minute)*r*.72,c,stroke*1.6)
            D.circle(bb,cx,cy,stroke*2.5,c)
            if b.design~="sector"then
                local hx,hy=cx+math.cos(hour)*r*.49,cy+math.sin(hour)*r*.49
                local mx,my=cx+math.cos(minute)*r*.72,cy+math.sin(minute)*r*.72
                local pad=stroke*3+2
                local x1,y1=math.min(cx,hx,mx)-pad,math.min(cy,hy,my)-pad
                return {x=x1,y=y1,w=math.max(cx,hx,mx)+pad-x1,h=math.max(cy,hy,my)+pad-y1}
            end
        elseif b.type=="calendar"then
            local first=os.time{year=t.year,month=t.month,day=1,hour=12};local start=(tonumber(os.date("%w",first))+6)%7
            local days=os.date("*t",os.time{year=t.year,month=t.month+1,day=0,hour=12}).day
            local months=self.s.locale=="en"and {"JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE","JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"}or {"JANVIER","FÉVRIER","MARS","AVRIL","MAI","JUIN","JUILLET","AOÛT","SEPTEMBRE","OCTOBRE","NOVEMBRE","DÉCEMBRE"}
            fit(bb,months[t.month].." "..t.year,0,0,w,h*.15,h*.1,c,"cfont",true)
            local labels=self.s.locale=="en"and {"M","T","W","T","F","S","S"}or {"L","M","M","J","V","S","D"}
            local cw,rh=w/7,h*.11
            for i,v in ipairs(labels)do fit(bb,v,(i-1)*cw,h*.18,cw,rh,rh*.55,c,"cfont",true)end
            for day=1,days do local index=day-1+start;local x,y=index%7*cw,h*.30+math.floor(index/7)*rh
                if day==t.day then D.rect(bb,x+cw*.13,y,cw*.74,rh*.94,c)end
                fit(bb,day,x,y,cw,rh*.94,rh*.62,day==t.day and back or c,"cfont",day==t.day)
            end
        elseif b.type=="words"then
            local one,two=Time.words(now,self.s)
            local intro=fit(bb,self.s.locale=="en"and "THE TIME IS"or "IL EST",0,0,w,h*.12,h*.09,c,"cfont",false)
            local first=fit(bb,one,0,h*.22,w,h*.34,h*.34,c,font,bold,style=="contour"and math.max(1,small*.005)or 0)
            local second=fit(bb,two,0,h*.66,w,h*.25,h*.24,c,font,false,style=="contour"and math.max(1,small*.005)or 0)
            return D.union(intro,D.union(first,second))
        elseif b.type=="timeline"then
            local vertical=h>w;local value=(t.hour+t.min/60)/24
            for n=0,24 do local f=n/24;local long=n%6==0
                if vertical then local y=h*.04+f*h*.92;D.line(bb,w*.2,y,w*(long and .65 or .4),y,c,stroke)
                    if long then fit(bb,n,w*.66,y-h*.025,w*.33,h*.05,h*.04,c,"cfont",false)end
                else local x=w*.04+f*w*.92;D.line(bb,x,h*.15,x,h*(long and .55 or .35),c,stroke)
                    if long then fit(bb,n,x-w*.035,h*.6,w*.07,h*.3,h*.25,c,"cfont",false)end
                end
            end
            if vertical then D.circle(bb,w*.20,h*.04+value*h*.92,w*.12,c)else D.circle(bb,w*.04+value*w*.92,h*.16,h*.1,c)end
        end
    end,source,b.type)
end
function F:complication(id,spec,box,now)
    local slot=C.slot(self.options,self.face,id);if not C.allowed(spec,slot.provider)then slot={provider=spec.default,zone="UTC"}end
    local p=slot.provider;local t=os.date("*t",now);local title,value,extra,fraction,key
    if p=="date"then title=self.s.locale=="en"and "TODAY"or "AUJOURD'HUI";value=tostring(t.day);extra=Time.date(now,self.s);key=os.date("%Y-%m-%d",now)
    elseif p=="battery"then local cap=self.app.cycle_capacity;if cap==nil then cap=self.app:capacity()end
        title=self.s.locale=="en"and "BATTERY"or "BATTERIE";value=cap and cap.."%"or "—";extra=cap and(self.s.locale=="en"and "Remaining charge"or "Charge restante")or(self.s.locale=="en"and "Unavailable"or "Indisponible");fraction=cap and cap/100;key=value
    elseif p=="day"then local mins=math.floor((t.hour*60+t.min)/15)*15
        title=self.s.locale=="en"and "DAY"or "JOURNÉE";fraction=mins/1440;value=math.floor(fraction*100).."%";extra="00 h — 24 h";key=tostring(mins)
    elseif p=="week"then local n=(t.wday+5)%7+1
        title=(self.s.locale=="en"and "WEEK "or "SEMAINE ")..os.date("%V",now);value=n.." / 7";extra=self.s.locale=="en"and "Monday — Sunday"or "Lundi — dimanche";fraction=n/7;key=os.date("%Y-%m-%d",now)
    elseif p=="world"then value,title=self.app.world:format(now,slot.zone);extra=slot.zone;key=value..title
    elseif p=="book"then title=self.s.locale=="en"and "READING"or "LECTURE";value=self.book.percent and math.floor(self.book.percent*100).."%"or "—";extra=self.book.title or "Ouvrir un livre dans KOReader";fraction=self.book.percent;key=value..extra
    else title="";value="";extra="";key="empty"end
    self:tile("slot_"..id,box,key,function(bb,w,h)
        if p=="none"then return end
        local ink,bg=self.ink,self.bg;local edge=math.min(w,h);local circle=spec.family=="circle"
        if circle then
            local r=edge*.44;arc(bb,w/2,h/2,r,1,ink,math.max(1,edge*.007))
            if fraction then arc(bb,w/2,h/2,r,fraction,ink,math.max(3,edge*.04))end
            fit(bb,title,w*.1,h*.22,w*.8,h*.14,h*.10,ink,"cfont",false)
            fit(bb,value,w*.12,h*.43,w*.76,h*.24,h*.23,ink,"cfont",true)
        elseif spec.family=="inline"then
            local str=p=="date"and extra or title.."  "..value
            fit(bb,str,w*.025,h*.1,w*.95,h*.8,h*.6,ink,"cfont",false)
        else
            local border=math.max(1,edge*.009);D.border(bb,0,0,w,h,ink,border)
            local pad=w*.055;fit(bb,title,pad,h*.08,w-2*pad,h*.15,h*.11,ink,"cfont",false)
            fit(bb,value,pad,h*.29,w-2*pad,h*.32,h*.31,ink,"cfont",true)
            D.label(bb,extra,w/2,h*.72,math.min(h*.13,w*.055),ink,"center",w*.87,"cfont",false)
            if fraction then D.border(bb,pad,h*.92,w-2*pad,h*.025,ink,1);D.rect(bb,pad,h*.92,(w-2*pad)*fraction,h*.025,ink)end
        end
    end,p,"complication")
end
function F:render(now)
    now=now or os.time();self.regions={};self.coarse_regions={};self.delta_scanned_pixels=0;self.delta_fallbacks=0;self.delta_skipped=0
    if not self.base then self:background(now)end
    local time,ampm=Time.digital(now,self.s);local hour,minute=time:match("(%d+):(%d+)")
    local values={time=time,hour=hour,minute=minute,ampm=ampm or ""}
    for _,block in ipairs(self.layout.blocks)do self:block(block,now,values)end
    for _,slot in ipairs(self.face.slots)do self:complication(slot.id,slot,self.layout.slots[slot.id],now)end
    local note=self.app.paused_warning or(self.s.interval==0 and "HEURE À LA MISE EN VEILLE"or self.s.interval>60 and "≈ ACTUALISATION / "..math.floor(self.s.interval/60).." MIN"or "")
    self:tile("note",{.03,.959,.94,.034},note,function(bb,w,h)fit(bb,note,0,0,w,h,h*.65,self.ink,"cfont",false)end,"label","label")
    self.regions=Delta.plan(self.regions,4)
    self.coarse_regions=Delta.plan(self.coarse_regions,4)
    -- Extra command overhead is bounded; if band merging would enlarge the
    -- submitted area, retain the established conservative windows instead.
    if Delta.area(self.regions)>Delta.area(self.coarse_regions)then self.regions=self.coarse_regions end
    local union
    for _,r in ipairs(self.regions)do union=D.union(union,r)end
    if self.full then union={x=0,y=0,w=self.w,h=self.h};self.regions={union};self.coarse_regions={union};self.full=false end
    return union
end
function F:paintTo(bb,x,y)
    if not self.frame then self:render()end
    bb:blitFrom(self.frame,math.floor(x or 0),math.floor(y or 0),0,0,self.w,self.h)
end
return F
