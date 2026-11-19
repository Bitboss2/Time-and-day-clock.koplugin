local load=...
local U=load("core/util")
local D=load("render/draw")
local Time=load("core/time")
local BB=require("ffi/blitbuffer")
local Metrics=load("ui/metrics")
local Scene={}
function Scene.new(app,face,settings,w,h)
    if face.schema_version==2 then return load("render/face_v2").new(app,face,settings,w,h)end
    return setmetatable({app=app,face=face,s=U.copy(settings),input_settings=U.copy(settings),w=math.floor(w),h=math.floor(h),old={},full=true}, {__index=Scene})
end
function Scene:free()
    if self.base then self.base:free();self.base=nil end
    if self.frame then self.frame:free();self.frame=nil end
end
function Scene:background(now)
    if self.base then self.base:free() end
    local b=BB.new(self.w,self.h,BB.TYPE_BB8);b:fill(D.color(255))
    local assets=self.face.assets
    for _,l in ipairs(self.face.layers) do if l.type=="image" then
        D.image(b,self.face.dir.."/"..assets[l.asset],(l.x or 0)*self.w,(l.y or 0)*self.h,(l.w or 1)*self.w,(l.h or 1)*self.h,false)
    end end
    local image=self.app:backgroundImage(self.s,self.w>self.h,now)
    if image then
        local overlay=BB.new(self.w,self.h,BB.TYPE_BB8);overlay:fill(D.color(255))
        if D.image(overlay,image,0,0,self.w,self.h,false) then b:blitFrom(overlay,0,0,0,0,self.w,self.h) end
        overlay:free()
    end
    local dark=self.s.night=="dark" or self.s.night=="follow" and G_reader_settings:isTrue("night_mode")
    if dark then b:invertRect(0,0,self.w,self.h) end
    self.ink=dark and 255 or 0;self.bg=dark and 0 or 255
    if image and dark and not self.s.image_invert then D.image(b,image,0,0,self.w,self.h,false) end
    local pad=math.floor(math.min(self.w,self.h)*0.035);local style=self.s.border
    if style=="simple" or style=="double" then D.border(b,pad,pad,self.w-pad*2,self.h-pad*2,self.ink,1) end
    if style=="double" then D.border(b,pad+5,pad+5,self.w-pad*2-10,self.h-pad*2-10,self.ink,1) end
    if style=="corner" then
        for _,p in ipairs({{pad,pad,1,1},{self.w-pad,pad,-1,1},{pad,self.h-pad,1,-1},{self.w-pad,self.h-pad,-1,-1}}) do
            D.line(b,p[1],p[2],p[1]+p[3]*30,p[2],self.ink,2);D.line(b,p[1],p[2],p[1],p[2]+p[4]*30,self.ink,2)
        end
    end
    self.base=b;self.image=image;self.dark=dark;self.full=true
end
function Scene:data(now)
    local s=self.s;local time,ampm=Time.digital(now,s)
    local capacity=self.app:capacity()
    local battery
    if not capacity then battery="BAT —"
    elseif s.battery_format=="icon" then battery="BAT "..string.rep("|",math.floor(capacity/20))
    elseif s.battery_format=="percent" then battery=capacity.." %"
    else battery="BAT  "..capacity.." %" end
    local world,label=self.app.world:format(now,s.world_zone)
    local wifi="Wi-Fi —"
    if s.show_wifi then
        local ok,net=pcall(require,"ui/network/manager")
        if ok and net.isWifiOn then wifi=net:isWifiOn() and "Wi-Fi ON" or "Wi-Fi OFF" end
    end
    return {time=time,ampm=ampm,date=Time.date(now,s),battery=battery,
        wifi=wifi,memory=string.format("Lua %.1f Mo",collectgarbage("count")/1024),world=world,label=label}
end
function Scene:render(now)
    now=now or os.time()
    local image=self.app:backgroundImage(self.input_settings,self.w>self.h,now)
    if self.input_settings.per_image and image~=self.sidecar_image then
        self.s=U.copy(self.input_settings);self.sidecar_image=image
        local raw=image and U.read(image..".json",131072)
        if raw then
            local ok,side=pcall(require("json").decode,raw)
            if ok and type(side)=="table" then
                for _,key in ipairs({"time","date","battery","wifi","memory","world","scale","gap","auto_layout","units","outline","separator","border"}) do
                    if type(side[key])=="table" and type(self.s[key])=="table" then
                        for field,v in pairs(side[key]) do self.s[key][field]=v end
                    elseif side[key]~=nil then self.s[key]=side[key] end
                end
                local valid,result=pcall(load("core/settings").validate,self.s)
                if valid then self.s=result else self.s=U.copy(self.input_settings);self.app.notice="Réglages par image invalides." end
            else self.app.notice="JSON par image illisible." end
        end
        self.full=true
    end
    if not self.base or image~=self.image then self:background(now) end
    local b=self.base:copy();local s=self.s;local values=self:data(now)
    local ratio=math.min(self.w/self.face.canvas.width,self.h/self.face.canvas.height)
    local fontscale=ratio*s.scale/100;local legible=Metrics.scene(self.app.device.screen,self.w,self.h)
    local dirty=nil;local fresh={}
    local layers={};local layout_boxes={}
    local has={}
    for _,l in ipairs(self.face.layers) do
        if l.type~="image" then
            local c=U.copy(l);local e=s[c.source or "time"]
            c.z=(c.z or 1)+(type(e)=="table" and e.z or 0);layers[#layers+1]=c
            if c.source then has[c.source]=true end
        end
    end
    -- Optional status elements are available on every package, not hard-coded to
    -- one clock design. Their manual offsets remain independent.
    local row=0
    for _,source in ipairs({"date","battery","wifi","memory","world"}) do
        if s["show_"..source] and not has[source] then
            row=row+1;layers[#layers+1]={id="extra_"..source,type="text",source=source,x=0.5,y=0.80+(row-1)*0.045,size=s[source].size,align="center",z=s[source].z}
        end
    end
    table.sort(layers,function(a,c)return (a.z or 0)<(c.z or 0) end)
    for _,l in ipairs(layers) do
        local source=l.source or "time";local e=s[source] or s.time
        local visible=e.visible~=false and (s["show_"..source]~=false)
        if source=="time" or source=="label" or source=="ampm" then visible=e.visible~=false end
        if visible then
            local ux=s.units=="percent" and self.w/100 or ratio
            local uy=s.units=="percent" and self.h/100 or ratio
            local x=(l.x or 0.5)*self.w+(e.x or 0)*ux
            local y=(l.y or 0.5)*self.h+(e.y or 0)*uy
            if s.auto_layout and source~="time" and source~="label" and source~="ampm" then y=y+(s.gap-20)*ratio end
            local size=(l.size or e.size or 24)*fontscale
            if source=="time" then size=size*s.time.size/100
            elseif s[source] then size=size*e.size/(source=="date" and 24 or source=="world" and 22 or source=="battery" and 20 or 18) end
            if source~="time" then size=math.max(size,(source=="label" and 16 or 23)*legible) end
            local c=l.grey and (self.dark and 255-l.grey or l.grey) or self.ink
            local rect,key
            if l.type=="text" then
                local text=l.text or values[source] or ""
                if source=="time" and s.interval>60 then text="≈ "..text end
                if source=="world" then text=values.world.."  "..values.label end
                if s.auto_layout and source~="time" and source~="label" and source~="ampm" then
                    local estimated=D.text(b,text,x,y,size,c,l.align or "center",self.w*(l.w or .88),e.font or l.font,l.bold,0,true)
                    local new_y=y
                    for _,box in ipairs(layout_boxes) do
                        if estimated.x<box.x+box.w and estimated.x+estimated.w>box.x
                            and new_y<box.y+box.h+s.gap*ratio and new_y+estimated.h>box.y then
                            new_y=box.y+box.h+s.gap*ratio
                        end
                    end
                    local available=self.h*.95-new_y
                    if available<estimated.h then
                        -- Avoid collapsing secondary information to 7px when an
                        -- oversized time block leaves little room at the bottom.
                        local floor=16*legible
                        size=math.max(floor,size*math.max(7,available)/estimated.h)
                        new_y=math.min(new_y,self.h*.94-size*1.25)
                    end
                    y=new_y
                end
                key=text..size..c
                rect=D.text(b,text,x,y,size,c,l.align or "center",self.w*(l.w or 0.88),e.font or l.font,l.bold,source=="time" and s.outline or 0)
            elseif l.type=="stack" then
                local h,m=values.time:match("(%d+):(%d+)");h=h or "00";m=m or "00"
                local r1=D.text(b,h,x,y,size,c,"center",self.w*0.85,e.font,true)
                local r2=D.text(b,m,x,y+size*1.12,size,c,"center",self.w*0.85,e.font,true)
                rect=D.union(r1,r2);key=h..m
            elseif l.type=="words" then
                local one,two=Time.words(now,s)
                local a=D.text(b,one,x,y,size,c,"center",self.w*0.88,e.font,l.bold)
                local z=D.text(b,two,x,y+size*1.4,size*0.78,c,"center",self.w*0.85,e.font,false)
                rect=D.union(a,z);key=one..two
            elseif l.type=="dual" then
                local a=D.text(b,values.time,x,y,size,c,"center",self.w*0.85,e.font,true)
                local z=D.text(b,values.world,x,y+size*1.9,size*0.78,c,"center",self.w*0.85,e.font,false)
                D.text(b,values.label,x,y+size*3,size*0.22,c,"center",self.w*0.9,"cfont")
                rect=D.union(a,D.union(z,{x=0,y=y+size*3,w=self.w,h=size*0.4}));key=values.time..values.world..values.label
            elseif l.type=="hands" then
                local r=(l.radius or 0.34)*math.min(self.w,self.h)*s.scale/100
                local dt=os.date("*t",now);local hour=(dt.hour%12+dt.min/60)*math.pi/6-math.pi/2
                local minute=dt.min*math.pi/30-math.pi/2
                for n=1,60 do
                    local a=n*math.pi/30;local long=n%5==0
                    D.line(b,x+math.sin(a)*r*0.92,y-math.cos(a)*r*0.92,x+math.sin(a)*r,y-math.cos(a)*r,c,ratio*(long and 3 or 1))
                end
                local roman={"I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII"}
                if s.analog_numerals~="none" then for n=1,12 do
                    local a=n*math.pi/6;D.text(b,s.analog_numerals=="roman" and roman[n] or n,x+math.sin(a)*r*0.78,y-math.cos(a)*r*0.78-10*ratio,math.max(25*ratio,19*legible),c,"center",r*0.3,e.font)
                end end
                D.line(b,x,y,x+math.cos(hour)*r*0.52,y+math.sin(hour)*r*0.52,c,s.hour_width*ratio)
                D.line(b,x,y,x+math.cos(minute)*r*0.77,y+math.sin(minute)*r*0.77,c,s.minute_width*ratio)
                D.circle(b,x,y,5*ratio,c)
                rect={x=x-r-8,y=y-r-8,w=r*2+16,h=r*2+16};key=dt.hour..":"..dt.min
            elseif l.type=="progress" then
                local d=os.date("*t",now);local v=(d.hour*60+d.min)/1440
                local w,h=(l.w or 0.7)*self.w,(l.h or 0.008)*self.h
                D.rect(b,x-w/2,y,w,h,self.dark and 65 or 220);D.rect(b,x-w/2,y,w*v,h,c)
                rect={x=x-w/2,y=y,w=w,h=h};key=tostring(d.hour*60+d.min)
            elseif l.type=="rule" then
                D.rect(b,x-self.w*(l.w or 0.8)/2,y,self.w*(l.w or 0.8),math.max(1,(l.h or 0.001)*self.h),c)
                rect={x=0,y=y,w=self.w,h=4};key="rule"
            end
            if rect then
                if l.type~="progress" and l.type~="rule" and source~="label" and source~="ampm" then layout_boxes[#layout_boxes+1]=rect end
                fresh[l.id]={rect=rect,key=key,source=source,type=l.type}
                local previous=self.old[l.id]
                if not previous or previous.key~=key or previous.rect.x~=rect.x or previous.rect.y~=rect.y
                    or previous.rect.w~=rect.w or previous.rect.h~=rect.h then
                    dirty=D.union(dirty,D.union(rect,previous and previous.rect))
                end
            end
        end
    end
    if s.separator~="none" then
        local y=self.h*0.73;local x=self.w/2;local c=self.ink
        if s.separator=="line" then D.line(b,x-self.w*.16,y,x+self.w*.16,y,c,1)
        elseif s.separator=="dots" then for i=-2,2 do D.circle(b,x+i*12*ratio,y,2*ratio,c) end
        else D.line(b,x-7,y,x,y-7,c,2);D.line(b,x,y-7,x+7,y,c,2);D.line(b,x+7,y,x,y+7,c,2);D.line(b,x,y+7,x-7,y,c,2)
            if s.separator=="ornament" then D.line(b,x-60,y,x-18,y,c,1);D.line(b,x+18,y,x+60,y,c,1) end
        end
    end
    if s.interval~=60 or self.app.paused_warning then
        local note=self.app.paused_warning or (s.interval==0 and "HEURE À LA MISE EN VEILLE" or "≈  ACTUALISATION / "..math.floor(s.interval/60).." MIN")
        local rect=D.text(b,note,self.w*.5,self.h*.965,math.max(11*ratio,15*legible),self.ink,"center",self.w*.88,"cfont")
        fresh.pause_note={rect=rect,key=note}
        if not self.old.pause_note or self.old.pause_note.key~=note then dirty=D.union(dirty,rect) end
    end
    for id,old in pairs(self.old) do if not fresh[id] then dirty=D.union(dirty,old.rect) end end
    self.old=fresh
    if self.full then dirty={x=0,y=0,w=self.w,h=self.h};self.full=false end
    if self.frame then self.frame:free() end
    self.frame=b
    if dirty then
        local x,y=math.max(0,math.floor(dirty.x)),math.max(0,math.floor(dirty.y))
        dirty={x=x,y=y,w=math.max(0,math.min(self.w,math.ceil(dirty.x+dirty.w))-x),h=math.max(0,math.min(self.h,math.ceil(dirty.y+dirty.h))-y)}
    end
    return dirty
end
function Scene:paintTo(bb,x,y)
    if not self.frame then self:render() end
    bb:blitFrom(self.frame,math.floor(x),math.floor(y),0,0,self.w,self.h)
end
return Scene
