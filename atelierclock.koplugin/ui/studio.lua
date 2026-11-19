-- Atelier: fullscreen native canvas rendered as 8-bit frames.
-- Frames are composed from cached layers (header, scrolling content, tab bar,
-- sheets) and presented either by Fluid Ink (30 Hz target) or by KOReader's
-- classic refreshes, where every animation collapses to its final state.
local load=...
local U=load("core/util")
local D=load("render/draw")
local Metrics=load("ui/metrics")
local Motion=load("ui/motion")
local Kit=load("ui/kit")
local Icon=load("ui/icons")
local Display=load("engine/display")
local BB=require("ffi/blitbuffer")
local Geom=require("ui/geometry")
local GestureRange=require("ui/gesturerange")
local Studio=load("ui/studio_actions"):extend{covers_fullscreen=true,modal=true}
local TABS={{"Galerie","Cadrans","gallery"},{"Composer","Modifier","edit"},{"Veille","Veille","moon"},{"Diagnostic","Diagnostic","pulse"}}
local function hit(r,x,y)return r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h end
local function newBB(w,h)
    local b=BB.new(math.max(1,math.floor(w)),math.max(1,math.floor(h)),BB.TYPE_BB8)
    D.rect(b,0,0,b:getWidth(),b:getHeight(),255);return b
end
-- Bounded blit: never read or write outside either buffer.
local function blit(dst,src,dx,dy,sx,sy,w,h)
    dx,dy,sx,sy=math.floor(dx),math.floor(dy),math.floor(sx),math.floor(sy);w,h=math.floor(w),math.floor(h)
    if dx<0 then sx=sx-dx;w=w+dx;dx=0 end;if dy<0 then sy=sy-dy;h=h+dy;dy=0 end
    if sx<0 then dx=dx-sx;w=w+sx;sx=0 end;if sy<0 then dy=dy-sy;h=h+sy;sy=0 end
    w=math.min(w,dst:getWidth()-dx,src:getWidth()-sx);h=math.min(h,dst:getHeight()-dy,src:getHeight()-sy)
    if w>0 and h>0 then dst:blitFrom(src,dx,dy,sx,sy,w,h)end
end
Studio.blit=blit;Studio.newBB=newBB
local function shade(bb,x,y,w,h,by,dark)
    x,y,w,h=math.floor(x),math.floor(y),math.floor(w),math.floor(h)
    if w<=0 or h<=0 then return end
    local f=dark and bb.darkenRect or bb.lightenRect
    if f then f(bb,x,y,w,h,by)end
end
Studio.shade=shade

function Studio:init()
    local s=self.app.device.screen;self.w=s:getWidth();self.h=s:getHeight()
    self.draft=U.copy(self.app.settings.data)
    self.dimen=Geom:new{x=0,y=0,w=self.w,h=self.h}
    self.tab="Galerie";self.section="Aperçu";self.element="time";self.page=1;self.faces_page=1
    self.regions={};self.status="";self.dirty=false;self.anims={};self.layers={}
    self:layout()
    self.scroll=Motion.scroller{}
    self.tab_spring=Motion.spring(1,{omega=20,zeta=.78,eps=.004})
    self.draft_spring=Motion.spring(0,{omega=19,zeta=.82,eps=.004})
    self.toast_spring=Motion.spring(0,{omega=18,zeta=.9,eps=.004})
    for name,ges in pairs({Touch="touch",Tap="tap",Hold="hold",Pan="pan",PanRelease="pan_release",Swipe="swipe"})do
        self.ges_events[name]={GestureRange:new{ges=ges,range=self.dimen}}
    end
    if self.app.device:hasKeys()then self.key_events.Back={{"Back"},{"Esc"}}end
    self.tick_action=function()self:tick()end
    self.watch_action=function()self:watch()end
    self.display=Display.new{app=self.app,ui=self.app.ui,on_change=function(state)self:onDisplay(state)end,
        native_factory=self.native_factory,startup_factory=self.startup_factory,platform_factory=self.platform_factory}
    self.content_dirty=true
end
function Studio:layout()
    self.k,self.dpi=Metrics.ui(self.app.device.screen,self.w,self.h,self.draft.ui_scale)
    local k=self.k
    self.kit=Kit.new(k);self.pad=math.floor(20*k)
    self.header_h=math.floor(92*k);self.tab_h=math.floor(70*k)
    self.top=self.header_h;self.bottom=self.h-self.tab_h
    self.layers={}
end
-- Animated presentation only with the fluid engine (and full motion).
function Studio:animated()
    return self.display and self.display:isFluid()and self.draft.motion~="reduced"and not self.force_instant
end
function Studio:fps()return self.app.settings.data.display_fps or 30 end

------------------------------------------------------------------ regions
function Studio:region(x,y,w,h,callback,extra)
    local r=extra or {};r.x=x;r.y=y;r.w=w;r.h=h;r.callback=callback
    if self.collect and self.collect==self.cregions then r.gen=self.content_gen end
    local list=self.collect or self.regions;list[#list+1]=r;return r
end
function Studio:label(bb,text,x,y,size,width,bold,c)
    return D.label(bb,text,x,y,size*self.k,c or 0,"left",width,"cfont",bold)
end
function Studio:paragraph(bb,text,x,y,width,size,lines,c)
    local line="";local row=0;local words={}
    for word in tostring(text):gmatch("%S+")do words[#words+1]=word end
    for index,word in ipairs(words)do
        local s=line==""and word or line.." "..word
        if D.text(bb,s,0,0,size*self.k,0,"left",nil,"cfont",false,0,true).w>width and line~=""then
            self:label(bb,line,x,y+row*(size+7)*self.k,size,width,false,c);row=row+1;line=word
            if row>=(lines or 2)-1 then line=table.concat(words," ",index);break end
        else line=s end
    end
    self:label(bb,line,x,y+row*(size+7)*self.k,size,width,false,c)
    return (row+1)*(size+7)*self.k
end
-- Back-compat helpers used by legacy views and tests.
function Studio:button(bb,text,x,y,w,h,callback,active,icon)
    self.kit:button(bb,x,y,w,h,text,{style=active and "primary"or "secondary",icon=icon})
    return self:region(x,y,w,h,callback,{radius=h/2})
end
function Studio:iconButton(bb,icon,x,y,size,callback,active)
    self.kit:iconButton(bb,x,y,size,icon,{filled=active})
    return self:region(x,y,size,size,callback,{radius=size/2})
end

------------------------------------------------------------------ invalidation
function Studio:refresh()
    if self.preview then self.preview:free();self.preview=nil end
    self.content_dirty=true;self.layers.header=nil
    if self.status~=""and self.status~=self.shown_status then self:toast(self.status)end
    self:request()
end
-- Request at least one new frame.
function Studio:request()
    self.frame_dirty=true
    if self.closed then return end
    if self:animated()then self:kick()else self:presentClassic(false)end
end
function Studio:invalidateLayer(name)self.layers[name]=nil;self.frame_dirty=true end

------------------------------------------------------------------ layers
function Studio:headerLayer()
    if self.layers.header then return self.layers.header end
    local k,w,kit=self.k,self.w,self.kit;local b=newBB(w,self.header_h)
    local info=self:headerInfo()
    local x=self.pad
    if info.back then kit:iconButton(b,x,self.header_h/2-21*k,42*k,"left");x=x+54*k end
    kit:text(b,info.eyebrow or "ATELIER CLOCK",x+1,18*k,Kit.size.micro+1,Kit.muted,"left",w-x-90*k,true)
    kit:text(b,info.title,x,36*k,Kit.size.title,0,"left",w-x-92*k,true)
    kit:iconButton(b,w-self.pad-44*k,self.header_h/2-20*k,44*k,"close")
    self.layers.header=b;return b
end
function Studio:headerInfo()
    local t={Galerie=self.catalog and "Catalogue"or "Mes cadrans",Composer="Personnaliser",Veille="Veille",Diagnostic="Diagnostic"}
    local info={title=t[self.tab]or self.tab}
    if self.tab=="Composer"then
        local ok,face=pcall(self.app.face,self.app,self.draft.face)
        local item=load("core/collection").current(self.draft)
        info.eyebrow=Kit.upper((item and item.title)or(ok and face.name)or "")
        if self.element_selector or(face and face.schema_version~=2 and self.section~="Aperçu")then info.back=true end
    end
    return info
end
function Studio:headerRegions()
    local k=self.k;local info=self:headerInfo()
    if info.back then self:region(self.pad,self.header_h/2-21*k,42*k,42*k,function()self:onBack()end,{radius=21*k})end
    self:region(self.w-self.pad-44*k,self.header_h/2-20*k,44*k,44*k,function()self:leave()end,{radius=22*k,role="close"})
end
-- Two tab bars (ink on paper / paper on ink); the indicator reveals the second.
function Studio:tabLayers()
    if self.layers.tab_a then return self.layers.tab_a,self.layers.tab_b end
    local k,w,th=self.k,self.w,self.tab_h
    local a,b=newBB(w,th),newBB(w,th)
    D.rect(a,0,0,w,1,Kit.line);D.rect(b,0,0,w,th,0)
    local cw=w/#TABS
    for i,t in ipairs(TABS)do
        local cx=(i-1)*cw+cw/2;local py=8*k
        for _,layer in ipairs({{a,0},{b,255}})do
            Icon.draw(layer[1],t[3],cx-11*k,py+7*k,22*k,layer[2])
            D.label(layer[1],t[2],cx,py+32*k,14*k,layer[2],"center",cw-12*k,"cfont",layer[2]==255)
        end
    end
    self.layers.tab_a,self.layers.tab_b=a,b;return a,b
end
function Studio:tabIndex(name)for i,t in ipairs(TABS)do if t[1]==(name or self.tab)then return i end end;return 1 end
function Studio:drawTabBar(f)
    local a,b=self:tabLayers();local y0=self.bottom;local k=self.k;local cw=self.w/#TABS
    blit(f,a,0,y0,0,0,self.w,self.tab_h)
    local at=self.tab_spring.x;local pw,ph=cw-16*k,self.tab_h-16*k
    local px=(at-1)*cw+8*k;local py=8*k;local r=ph/2
    -- Rounded reveal, one scanline at a time (the pill glides between tabs).
    for row=0,math.floor(ph)-1 do
        local dy=math.abs(row+.5-ph/2);local inset=r-math.sqrt(math.max(0,r*r-dy*dy))
        local x1=math.floor(px+inset);local wid=math.floor(pw-2*inset)
        -- Same columns as the destination: labels under the pill appear inverted.
        blit(f,b,x1,y0+py+row,x1,py+row,wid,1)
    end
    for i,t in ipairs(TABS)do
        self:region((i-1)*cw,y0,cw,self.tab_h,function()self:switchTab(t[1])end,{radius=r,tab=t[1]})
    end
end
function Studio:draftLayer()
    if self.layers.draft then return self.layers.draft end
    local k,kit=self.k,self.kit;local w=self.w-2*self.pad;local h=math.floor(62*k)
    local b=newBB(w,h+6*k)
    kit:card(b,0,0,w,h,{radius=h/2,fill=0,stroke=false,shadow_color=Kit.shade})
    D.circle(b,h/2,h/2,5*k,255)
    kit:text(b,"Brouillon",h/2+14*k,h/2-11*k,Kit.size.body,255,"left",w*.34,true)
    local bw=w*.27
    kit:button(b,w-bw-8*k,8*k,bw,h-16*k,"Appliquer",{style="secondary",icon="check",size=Kit.size.small,icon_size=18})
    kit:text(b,"Annuler",w-bw-24*k,h/2-11*k,Kit.size.small,255,"right",w*.24,false)
    self.layers.draft=b;return b
end
function Studio:drawDraftBar(f)
    local t=self.draft_spring.x
    if t<=.01 then return end
    local k=self.k;local layer=self:draftLayer();local w=self.w-2*self.pad;local h=math.floor(62*k)
    local y=self.bottom+6*k-(h+16*k)*t
    blit(f,layer,self.pad,y,0,0,w,layer:getHeight())
    if t>.6 then
        local bw=w*.27
        self:region(self.pad+w-bw-8*k,y+8*k,bw,h-16*k,function()self:apply()end,{radius=h/2,role="apply"})
        self:region(self.pad+w*.45,y,w*.28,h,function()self:cancelDraft()end,{radius=h/2,role="cancel"})
    end
end
function Studio:cancelDraft()
    self.draft=U.copy(self.app.settings.data);self:clearDirty();self:layout()
    self.status="Modifications annulées";self:refresh()
end
-- Toasts replace the old status line: short, animated, never blocking.
function Studio:toast(text)
    self.shown_status=text;self.toast_text=text;self.layers.toast=nil
    self.toast_until=Motion.now()+2.6;self.toast_spring:set(1)
    if not self:animated()then self.toast_spring:jump(1)end
end
function Studio:toastLayer()
    if self.layers.toast then return self.layers.toast end
    local k,kit=self.k,self.kit;local text=self.toast_text or ""
    local m=kit:measure(text,Kit.size.small,true);local w=math.min(self.w-2*self.pad,m.w+52*k);local h=math.floor(40*k)
    local b=newBB(w,h+5*k)
    kit:card(b,0,0,w,h,{radius=h/2,fill=0,stroke=false})
    kit:text(b,text,w/2,h/2-10*k,Kit.size.small,255,"center",w-28*k,true)
    self.layers.toast=b;return b
end
function Studio:drawToast(f)
    local t=self.toast_spring.x
    if t<=.01 or not self.toast_text then return end
    local layer=self:toastLayer();local w=layer:getWidth()
    local y=self.top-layer:getHeight()+(layer:getHeight()+10*self.k)*t
    blit(f,layer,(self.w-w)/2,y,0,0,w,layer:getHeight())
end

------------------------------------------------------------------ content
-- A view returns its height and a draw function (content coordinates).
function Studio:buildView()
    if self.tab=="Galerie"then return self:galleryView()
    elseif self.tab=="Composer"then return self:composerView()
    elseif self.tab=="Veille"then return self:powerView()
    else return self:diagnosticView()end
end
function Studio:ensureContent()
    if self.content and not self.content_dirty then return end
    local vh=self.bottom-self.top
    local view=self:buildView()
    local height=math.max(vh,math.floor(view.height or vh))
    if not self.content or self.content:getHeight()~=height or self.content:getWidth()~=self.w then
        if self.content then self.content:free()end
        self.content=newBB(self.w,height)
    else D.rect(self.content,0,0,self.w,height,255)end
    self.content_gen=(self.content_gen or 0)+1
    self.cregions={};self.collect=self.cregions
    local ok,err=pcall(view.draw,self.content)
    self.collect=nil
    if not ok then
        self.content_error=tostring(err)
        self.kit:text(self.content,"Affichage impossible : "..tostring(err),self.pad,20*self.k,Kit.size.small,0,"left",self.w-2*self.pad)
    end
    self.cview=view;self.content_dirty=false
    self.scroll:setBounds(0,height-vh)
    if view.scroll_to then self.scroll:scrollTo(view.scroll_to,false);view.scroll_to=nil end
    if self.scroll.offset>height-vh and not self.scroll.dragging then self.scroll:scrollTo(height-vh,false)end
end
-- Keep a gliding indicator (segmented control) moving until its spring rests.
function Studio:glide(box,spring)
    if not self:animated()then spring:jump(spring.target);return end
    if spring:settled()or box.gliding then return end
    box.gliding=true
    self:animate(function()
        if not self.cregions or(box.gen and box.gen~=self.content_gen)then box.gliding=false;return false end
        self:repaint(box)
        if spring:settled()then box.gliding=false;return false end
        return true
    end)
end
-- Repaint one content region in place (animated switches, counters, sliders).
function Studio:repaint(r)
    r=r and(r.content or r)
    if not r or not r.paint or not self.content then return end
    -- A region from a previous content build must never paint over this one.
    if r.gen and r.gen~=self.content_gen then return end
    local c=r.clear or r
    D.rect(self.content,c.x,c.y,c.w,c.h,255);r.paint(self.content,r)
    self.frame_dirty=true
end

------------------------------------------------------------------ frame
function Studio:compose()
    if not self.frame or self.frame:getWidth()~=self.w or self.frame:getHeight()~=self.h then
        if self.frame then self.frame:free()end;self.frame=newBB(self.w,self.h)
    end
    local f=self.frame;D.rect(f,0,0,self.w,self.h,255)
    self.regions={}
    local ti=self:tabIndex()
    if self.tab_spring.target~=ti then self.tab_spring:set(ti);if not self:animated()then self.tab_spring:jump(ti)end end
    self:ensureContent()
    local vh=self.bottom-self.top
    if self.transition then
        local tr=self.transition;local e=tr.e or 0;local w=self.w
        blit(f,tr.layer,-tr.dir*w*e,self.top,0,tr.offset,w,vh)
        local off=self.scroll:value()
        blit(f,self.content,tr.dir*w*(1-e),self.top,0,off,w,vh)
        if self.cview and self.cview.overlay then self.cview.overlay(f,tr.dir*w*(1-e),self.top-off,true)end
    else
        local off=self.scroll:value()
        blit(f,self.content,0,self.top,0,off,self.w,vh)
        if self.cview and self.cview.overlay then self.cview.overlay(f,0,self.top-off,false)end
        for _,r in ipairs(self.cregions or {})do
            local y=r.y-off+self.top;local y2=y+r.h
            if r.fixed then y=r.y+self.top;y2=y+r.h end
            local cy,cy2=math.max(y,self.top),math.min(y2,self.bottom)
            if cy2-cy>=4 then
                local c={};for key,v in pairs(r)do c[key]=v end
                c.y=cy;c.h=cy2-cy;c.content=r;self.regions[#self.regions+1]=c
            end
        end
    end
    blit(f,self:headerLayer(),0,0,0,0,self.w,self.header_h)
    self:headerRegions()
    if self.pressed then
        local p=self.pressed;local a=p.alpha or .16
        shade(f,p.x,math.max(p.y,0),p.w,p.h,a,true)
    end
    self:drawDraftBar(f)
    self:drawToast(f)
    self:drawTabBar(f)
    if self.sheet then self:drawSheet(f)end
    if self.portal then self:drawPortal(f)end
    self.frame_dirty=false
end
function Studio:paintTo(bb,x,y)
    if self.frame_dirty or not self.frame or self.content_dirty then self:compose()end
    bb:blitFrom(self.frame,x or 0,y or 0,0,0,self.w,self.h)
    if not self.started_display then
        self.started_display=true
        self.app.ui:scheduleIn(.15,function()if not self.closed then self.display:start()end end)
    end
end

------------------------------------------------------------------ presentation
function Studio:presentClassic(moving)
    if self.closed then return end
    if self.display and self.display.state=="fluid"then return end
    self.app.ui:setDirty(self,moving and "fast"or "ui")
end
function Studio:present(moving)
    if self.display:isFluid()then self.display:publish(self.frame,moving)
    else self:presentClassic(moving)end
end
function Studio:kick()
    if self.closed then return end
    if self.ticking then self.tick_again=true;return end
    self.ticking=true;self.last_tick=Motion.now();self.deadline=self.last_tick
    self.app.ui:scheduleIn(0,self.tick_action)
end
function Studio:animate(fn)self.anims[#self.anims+1]=fn;if self:animated()then self:kick()else self:finishAnimations()end end
function Studio:finishAnimations()
    local list=self.anims;self.anims={}
    for _,fn in ipairs(list)do pcall(fn,math.huge,true)end
    self.frame_dirty=true
end
-- Advance every motion model; returns true while something still moves.
function Studio:step(dt,now)
    local moving=false
    local instant=not self:animated()
    local function spring(s)if instant then s:jump(s.target)elseif not s:settled()then s:step(dt);moving=true end end
    spring(self.tab_spring);spring(self.draft_spring);spring(self.toast_spring)
    if self.toast_until and now>=self.toast_until then self.toast_until=nil;self.toast_spring:set(0);if instant then self.toast_spring:jump(0)end;moving=moving or not instant end
    if self.toast_spring.x<=.01 and self.toast_spring.target==0 then self.toast_text=nil end
    if instant and not self.scroll.dragging then
        if self.scroll:moving()then self.scroll:settle();self.scroll.offset=self.scroll.spring.target;self.scroll.settling=false end
    elseif self.scroll:step(dt)then moving=true end
    if self.sheet then if self:stepSheet(dt,instant)then moving=true end end
    if self.stepCarousel and self:stepCarousel(dt,instant)then moving=true end
    if #self.anims>0 then
        local list=self.anims;self.anims={}
        for _,fn in ipairs(list)do
            local ok,more=pcall(fn,instant and math.huge or now,instant)
            if ok and more then self.anims[#self.anims+1]=fn end
        end
        if #self.anims>0 then moving=true end
        self.frame_dirty=true
    end
    if moving then self.frame_dirty=true end
    return moving
end
function Studio:tick()
    if self.closed then self.ticking=false;return end
    local now=Motion.now();local dt=now-(self.last_tick or now);self.last_tick=now
    self.tick_again=false
    local moving=self:step(dt,now)
    local touching=self.scroll.dragging or self.drag or self.canvas_drag or(self.carousel and self.carousel.dragging)
        or(self.sheet and self.sheet.scroll and self.sheet.scroll.dragging)
    if self.frame_dirty or moving then self:compose();self:present(moving or touching)end
    if self.display:isFluid()then self.display:check()end
    -- Something started during this frame (a sheet, a counter…): keep going.
    if self.tick_again then moving=true end
    if (moving or touching)and self:animated()then
        local next_at=Motion.deadline(self.deadline,Motion.now(),1/self:fps())
        self.deadline=next_at
        self.app.ui:scheduleIn(math.max(.001,next_at-Motion.now()),self.tick_action)
    else
        self.ticking=false
        if self.display:isFluid()then
            -- Final still frame lets Fluid Ink settle and clean at rest.
            self:compose();self.display:publish(self.frame,false)
            self.app.ui:unschedule(self.watch_action);self.app.ui:scheduleIn(1,self.watch_action)
        end
    end
end
-- Slow health watch while Fluid Ink owns the panel and nothing moves.
function Studio:watch()
    if self.closed or not self.display:isFluid()then return end
    self.display:check()
    if self.tab=="Diagnostic"and self.live_region then self:repaint(self.live_region);self:compose();self.display:publish(self.frame,false)end
    if not self.ticking then self.app.ui:scheduleIn(1,self.watch_action)end
end
function Studio:onDisplay(state)
    if self.closed then return end
    if state=="fluid"then
        self.content_dirty=true;self.layers.header=nil;self:compose();self.display:publish(self.frame,false)
        self.app.ui:unschedule(self.watch_action);self.app.ui:scheduleIn(1,self.watch_action)
    elseif state=="classic"then
        local notice=self.display.notice
        if notice and not self.display.notice_quiet and notice~=self.last_display_notice then
            self.last_display_notice=notice;self:toast(notice)
        end
        if self.ticking then self:finishAnimations()end
        self.frame_dirty=true;self.content_dirty=true
        self.app.ui:setDirty(self,"full")
    end
end

------------------------------------------------------------------ navigation
function Studio:switchTab(name,dir)
    if name==self.tab and not self.transition then
        if self.scroll.offset>1 then self.scroll:scrollTo(0,self:animated());self:request()end
        return
    end
    local from,to=self:tabIndex(),self:tabIndex(name)
    dir=dir or(to>from and 1 or -1)
    self:beginTransition(dir)
    self.tab=name;self.page=1;self.status="";self.element_selector=false;self.power_detail=false;self.diagnostic_detail=false
    self.scroll:scrollTo(0,false);self.tab_spring:set(to)
    if not self:animated()then self.tab_spring:jump(to)end
    self:closeSheet(true)
    self:refresh()
end
-- Horizontal slide between the current content and the next one.
function Studio:beginTransition(dir)
    if self:animated()and self.content then
        local snap=newBB(self.w,self.bottom-self.top)
        blit(snap,self.frame or self.content,0,0,0,self.frame and self.top or self.scroll:value(),self.w,self.bottom-self.top)
        if self.transition and self.transition.layer then self.transition.layer:free()end
        self.transition={layer=snap,offset=0,dir=dir,e=0}
        local tw=Motion.tween(0,1,.32,"outCubic",Motion.now())
        local tr=self.transition
        self:animate(function(now,instant)
            if self.transition~=tr then return false end
            tr.e=instant and 1 or tw:value(now)
            if instant or tw:done(now)then tr.layer:free();self.transition=nil;return false end
            return true
        end)
    end
end

------------------------------------------------------------------ sheets
-- Bottom sheet: {title, height, draw(bb,w), content_h}. Modal, swipe to close.
function Studio:openSheet(spec)
    if self.sheet and not self.sheet.closing then self:closeSheet(true)end
    local k=self.k
    local maxh=self.h-self.top-12*k
    local head=math.floor(78*k)
    local content_h=math.floor(spec.content_h or 200*k)
    local h=math.min(maxh,head+content_h+math.max(self.tab_h,24*k))
    spec.h=h;spec.head=head;spec.content_h=content_h
    spec.view_h=h-head-math.max(self.tab_h,24*k)
    spec.scroll=Motion.scroller{min=0,max=math.max(0,content_h-spec.view_h)}
    spec.spring=Motion.spring(0,{omega=21,zeta=.86,eps=.003})
    spec.spring:set(1)
    if not self:animated()then spec.spring:jump(1)end
    self.sheet=spec;self:buildSheet()
    self:request()
    return spec
end
function Studio:buildSheet()
    local s=self.sheet;if not s then return end
    local k,kit,w=self.k,self.kit,self.w
    if s.layer then s.layer:free()end
    local layer=newBB(w,s.head+math.max(s.content_h,s.view_h)+math.max(self.tab_h,24*k))
    D.round(layer,0,0,w,layer:getHeight()+40*k,28*k,255)
    D.round(layer,w/2-22*k,10*k,44*k,5*k,2.5*k,Kit.line)
    kit:text(layer,s.title or "",self.pad+4*k,30*k,Kit.size.heading,0,"left",w-2*self.pad-60*k,true)
    if s.subtitle then kit:text(layer,s.subtitle,self.pad+4*k,56*k,Kit.size.micro+1,Kit.muted,"left",w-2*self.pad-60*k)end
    D.circle(layer,w-self.pad-19*k,45*k,19*k,Kit.wash);Icon.draw(layer,"close",w-self.pad-29*k,35*k,20*k,0)
    local saved=self.collect
    s.regions={};self.collect=s.regions
    local body=newBB(w,math.max(1,s.content_h))
    local ok,err=pcall(s.draw,body,w)
    if not ok then kit:text(body,tostring(err),self.pad,10*k,Kit.size.small,0,"left",w-2*self.pad)end
    self.collect=saved
    s.body=body;s.layer=layer
end
function Studio:closeSheet(instant)
    local s=self.sheet;if not s or s.closing then if instant and s then self:dropSheet()end;return end
    s.closing=true;s.spring:set(0)
    if s.on_close then pcall(s.on_close)end
    if instant or not self:animated()then self:dropSheet()else self:kick()end
end
function Studio:dropSheet()
    local s=self.sheet;if not s then return end
    if s.layer then s.layer:free()end;if s.body then s.body:free()end
    self.sheet=nil;self.frame_dirty=true
end
function Studio:stepSheet(dt,instant)
    local s=self.sheet;local moving=false
    if instant then s.spring:jump(s.spring.target)
    elseif not s.spring:settled()then s.spring:step(dt);moving=true end
    if instant and not s.scroll.dragging then
        if s.scroll:moving()then s.scroll:settle();s.scroll.offset=s.scroll.spring.target;s.scroll.settling=false end
    elseif s.scroll:step(dt)then moving=true end
    if s.closing and s.spring.x<=.01 then self:dropSheet();return true end
    return moving
end
function Studio:sheetTop()local s=self.sheet;return self.h-s.h*s.spring.x+(s.pull or 0)end
function Studio:drawSheet(f)
    local s=self.sheet;local t=s.spring.x
    shade(f,0,0,self.w,self.h,Kit.scrim*math.min(1,t),true)
    local y=self:sheetTop()
    blit(f,s.layer,0,y,0,0,self.w,s.head)
    local off=s.scroll:value()
    local sh=s.layer:getHeight()-s.head
    blit(f,s.layer,0,y+s.head,0,s.head,self.w,sh)
    blit(f,s.body,0,y+s.head,0,off,self.w,math.min(s.view_h,s.content_h-off))
    -- Modal: replace every underlying target by the scrim + sheet targets.
    self.regions={}
    self:region(0,0,self.w,y,function()self:closeSheet()end,{role="scrim"})
    self:region(self.w-self.pad-44*self.k,y+20*self.k,50*self.k,50*self.k,function()self:closeSheet()end,{radius=25*self.k,role="sheet_close"})
    if t>.85 then
        local top,bottom=y+s.head,y+s.head+s.view_h
        for _,r in ipairs(s.regions)do
            local ry=r.y-off+y+s.head;local ry2=ry+r.h
            local cy,cy2=math.max(ry,top),math.min(ry2,bottom,self.bottom)
            if cy2-cy>=4 then local c={};for key,v in pairs(r)do c[key]=v end;c.y=cy;c.h=cy2-cy;self.regions[#self.regions+1]=c end
        end
    end
end
-- Confirmation sheet (replaces KOReader's ConfirmBox: no screen hand-off).
function Studio:confirmSheet(title,text,ok_text,callback,danger)
    local k,kit=self.k,self.kit
    self:openSheet{title=title,content_h=150*k,draw=function(bb,w)
        local p=self.pad
        self:paragraph(bb,text,p+4*k,6*k,w-2*p-8*k,Kit.size.body,3,Kit.muted)
        local bw=(w-2*p-12*k)/2;local y=78*k;local bh=52*k
        kit:button(bb,p,y,bw,bh,"Annuler",{style="secondary"})
        self:region(p,y,bw,bh,function()self:closeSheet()end,{radius=bh/2,role="cancel"})
        kit:button(bb,p+bw+12*k,y,bw,bh,ok_text,{style="primary",icon=danger and "trash"or "check"})
        self:region(p+bw+12*k,y,bw,bh,function()self:closeSheet();callback()end,{radius=bh/2,role="confirm"})
    end}
end
-- Choice sheet: every option visible with a check mark.
function Studio:choiceSheet(title,options,current,callback)
    local k,kit=self.k,self.kit;local rh=58*k
    self:openSheet{title=title,content_h=#options*rh+12*k,draw=function(bb,w)
        local p=self.pad
        for i,o in ipairs(options)do
            local y=(i-1)*rh;local active=o.value==current
            if active then D.round(bb,p,y+4*k,w-2*p,rh-8*k,(rh-8*k)/2,Kit.wash)end
            if o.icon then Icon.draw(bb,o.icon,p+16*k,y+rh/2-11*k,22*k,0)end
            kit:text(bb,o.label,p+(o.icon and 52 or 20)*k,y+rh/2-12*k,Kit.size.body,0,"left",w-2*p-110*k,active)
            if o.hint then kit:text(bb,o.hint,w-p-52*k,y+rh/2-10*k,Kit.size.small,Kit.muted,"right",w*.4)end
            if active then Icon.draw(bb,"check",w-p-40*k,y+rh/2-11*k,22*k,0)end
            self:region(p,y,w-2*p,rh,function()self:closeSheet();callback(o.value)end,{radius=rh/2,choice=o.value})
        end
    end}
end

------------------------------------------------------------------ portal
-- « Afficher » grows the preview into the real full-screen clock.
function Studio:launchClock(from)
    if not self:apply()then return end
    local function finish()
        self.display:close(function()self.app.ui:close(self,"full");self.app:launch()end)
    end
    if not self:animated()or not from then return finish()end
    local Scene=load("render/scene")
    local ok,scene=pcall(Scene.new,self.app,self.app:face(),self.app.settings.data,self.w,self.h)
    if not ok then return finish()end
    if not pcall(scene.render,scene,os.time())then scene:free();return finish()end
    local tw=Motion.tween(0,1,.42,"inOutCubic",Motion.now())
    self.portal={scene=scene,from=from,e=0}
    self:animate(function(now,instant)
        local p=self.portal;if not p then return false end
        p.e=instant and 1 or tw:value(now)
        if instant or tw:done(now)then p.e=1;self:compose();self:present(false);finish();return false end
        return true
    end)
end
function Studio:drawPortal(f)
    local p=self.portal;local e=p.e;local a=p.from
    local x=Motion.lerp(a.x,0,e);local y=Motion.lerp(a.y,0,e)
    local w=Motion.lerp(a.w,self.w,e);local h=Motion.lerp(a.h,self.h,e)
    shade(f,0,0,self.w,self.h,.5*e,false)
    local src=p.scene.frame
    -- True zoom through KOReader's MuPDF scaler (C). Never BlitBuffer:scale,
    -- which is a per-pixel Lua loop; without MuPDF the reveal is a crop.
    local ok,RI=pcall(require,"ui/renderimage")
    local scaled
    if ok and RI and RI.scaleBlitBuffer and w>=8 and h>=8 then
        local good,b=pcall(RI.scaleBlitBuffer,RI,src,math.floor(w),math.floor(h),false)
        if good and b then scaled=b end
    end
    if scaled then blit(f,scaled,x,y,0,0,w,h);if scaled~=src then scaled:free()end
    else blit(f,src,x,y,(self.w-w)*.5,(self.h-h)*.5,w,h)end
    D.border(f,x,y,w,h,0,math.max(1,2*(1-e)))
    self.regions={}
end

------------------------------------------------------------------ gestures
function Studio:hitRegion(x,y)
    for i=#self.regions,1,-1 do local r=self.regions[i];if hit(r,x,y)then return r end end
end
function Studio:onTouch(_,ges)
    local p=ges and ges.pos;if not p then return true end
    self.touch_pos={x=p.x,y=p.y};self.touch_time=Motion.gestime(ges);self.gesture=nil
    if self.frame_dirty or not self.frame then self:compose()end
    local r=self:hitRegion(p.x,p.y)
    -- Fingers stop momentum immediately, like on a phone.
    if self.scroll:moving()and not self.sheet then self.scroll.velocity=0;self.scroll.settling=false;self.stopped_scroll=true else self.stopped_scroll=false end
    if self:animated()and r and r.role~="scrim"and(r.callback or r.slider)then
        self.pressed={x=r.x,y=r.y,w=r.w,h=r.h,alpha=.18,region=r};self:kick()
    end
    return true
end
function Studio:releasePress(delay)
    local p=self.pressed;if not p then return end
    if not self:animated()then self.pressed=nil;return end
    local t0=Motion.now()+(delay or 0)
    self:animate(function(now,instant)
        if self.pressed~=p then return false end
        if instant then self.pressed=nil;return false end
        local e=math.max(0,math.min(1,(now-t0)/.14))
        p.alpha=.18*(1-e)
        if e>=1 then self.pressed=nil;return false end
        return true
    end)
end
function Studio:onTap(_,ges)
    local p=ges and ges.pos;if not p then return true end
    if self.frame_dirty or not self.frame or self.content_dirty then self:compose()end
    if self.stopped_scroll then self.stopped_scroll=false;self:releasePress();return true end
    local r=self:hitRegion(p.x,p.y)
    self:releasePress(.06)
    local gen,sheet,tab=self.content_gen,self.sheet,self.tab
    if r then
        if r.callback then r.callback(r,p)elseif r.slider then r.slider(p.x)end
    end
    -- The pressed tint belongs to the old view once the action changed it.
    if self.content_dirty or self.content_gen~=gen or self.sheet~=sheet or self.tab~=tab then self.pressed=nil end
    return true
end
function Studio:onHold(_,ges)
    local p=ges and ges.pos;if not p then return true end
    local r=self:hitRegion(p.x,p.y);self:releasePress()
    if r and r.hold then r.hold(r,p)end
    return true
end
function Studio:viewport()return {x=0,y=self.top,w=self.w,h=self.bottom-self.top}end
function Studio:onPan(_,ges)
    local p=ges and ges.pos;if not p then return true end
    local start=ges.start_pos or self.touch_pos or p
    local rel=ges.relative or {x=p.x-start.x,y=p.y-start.y}
    local t=Motion.gestime(ges)
    if not self.gesture then
        if self.pressed then self.pressed=nil end
        self.gesture="none"
        if self.sheet then
            local s=self.sheet
            if start.y>=self:sheetTop()then self.gesture="sheet";s.scroll:touch(start.y,self.touch_time or t);s.pull=0 end
        else
            local r=self:hitRegion(start.x,start.y)
            if r and r.slider then self.gesture="slider";self.drag=r
            elseif self.canvasGesture and self:canvasGesture(start,ges)then self.gesture="canvas"
            elseif self.carousel_box and hit(self.carousel_box,start.x,start.y)and math.abs(rel.x)>=math.abs(rel.y)then
                self.gesture="carousel";self.carousel:touch(start.x,self.touch_time or t)
            elseif hit(self:viewport(),start.x,start.y)and math.abs(rel.y)>math.abs(rel.x)then
                self.gesture="scroll";self.scroll:touch(start.y,self.touch_time or t)
            end
        end
    end
    local g=self.gesture
    if g=="slider"then self.drag_x=p.x;self.drag.slider(p.x,true)
    elseif g=="canvas"then self:canvasPan(ges,p)
    elseif g=="carousel"then self.carousel:drag(p.x,t);self:carouselChanged()
    elseif g=="scroll"then self.scroll:drag(p.y,t)
    elseif g=="sheet"then
        local s=self.sheet
        if s.scroll.offset<=0 and p.y>start.y and(s.pull or 0)>=0 then s.pull=math.max(0,p.y-start.y)
        else s.scroll:drag(p.y,t)end
    end
    if g~="none"then
        if self:animated()then self:kick()
        else
            local now=Motion.now()
            if not self.classic_pan or now-self.classic_pan>.2 then self.classic_pan=now;self:compose();self:presentClassic(true)end
        end
    end
    return true
end
function Studio:onPanRelease(_,ges)
    local t=Motion.gestime(ges);local g=self.gesture;self.gesture=nil
    if g=="slider"and self.drag then self.drag.slider(ges and ges.pos and ges.pos.x or self.drag_x,false)
    elseif g=="canvas"then self:canvasRelease()
    elseif g=="carousel"then self.carousel:release(t);self:carouselSettle()
    elseif g=="scroll"then self.scroll:release(t)
    elseif g=="sheet"then
        local s=self.sheet
        if s and(s.pull or 0)>s.h*.22 then s.pull=0;self:closeSheet()
        elseif s then s.pull=0;s.scroll:release(t)end
    end
    self.drag=nil;self.drag_time=nil;self.canvas_drag=nil
    if self:animated()then self:kick()else self.frame_dirty=true;self:presentClassic(false)end
    return true
end
function Studio:onSwipe(_,ges)
    local dir=ges and ges.direction or "";local p=ges and ges.pos
    local dt=math.max(.05,Motion.gestime(ges)-(self.touch_time or 0));if dt>1 then dt=.25 end
    local v=math.min(4200,(ges and ges.distance or 300)/dt)
    if self.pressed then self.pressed=nil end
    if self.sheet then
        if dir=="south"and(not p or p.y>=self:sheetTop())and self.sheet.scroll.offset<=1 then self:closeSheet()
        elseif dir=="north"then self.sheet.scroll:fling(v)elseif dir=="south"then self.sheet.scroll:fling(-v)end
        self:request();return true
    end
    local horizontal=dir=="west"or dir=="east"
    if horizontal and self.tab=="Galerie"then
        self:carouselFling(dir=="west"and 1 or -1,v);return true
    end
    if horizontal and self.swipeHorizontal and self:swipeHorizontal(dir=="west"and 1 or -1)then return true end
    if horizontal then
        local i=self:tabIndex()+(dir=="west"and 1 or -1)
        if TABS[i]then self:switchTab(TABS[i][1],dir=="west"and 1 or -1)end
        return true
    end
    if dir=="north"then self.scroll:fling(v)elseif dir=="south"then self.scroll:fling(-v)end
    if self:animated()then self:kick()else self.scroll:settle();self.scroll.offset=self.scroll.spring.target;self.scroll.settling=false;self:request()end
    return true
end
function Studio:onBack()
    if self.sheet then self:closeSheet();return true end
    if self.backView and self:backView()then return true end
    self:leave();return true
end

------------------------------------------------------------------ lifecycle
function Studio:onSuspend()
    if self.closed then return end
    self.app.ui:unschedule(self.tick_action);self.app.ui:unschedule(self.watch_action);self.ticking=false
    self:finishAnimations()
    self.display:suspend()
end
function Studio:onResume()
    if self.closed then return end
    self.app.ui:scheduleIn(.6,function()if not self.closed then self.display:wake()end end)
end
function Studio:onSetRotationMode()
    self.display:release(function()
        local s=self.app.device.screen;self.w=s:getWidth();self.h=s:getHeight();self.dimen.w=self.w;self.dimen.h=self.h
        self:layout();self.display:select();self:refresh()
    end)
end
Studio.onScreenResize=Studio.onSetRotationMode
function Studio:onCloseWidget()
    if self.closed then return end
    self.closed=true
    self.app.ui:unschedule(self.tick_action);self.app.ui:unschedule(self.watch_action)
    if self.resume_action then self.app.ui:unschedule(self.resume_action)end
    if self.display then self.display.closed=true;if self.display.backend then self.display:releaseNow(false)end end
    self:dropSheet()
    if self.preview then self.preview:free();self.preview=nil end
    if self.clearFaces then self:clearFaces()end
    if self.portal and self.portal.scene then self.portal.scene:free();self.portal=nil end
    if self.transition and self.transition.layer then self.transition.layer:free();self.transition=nil end
    for _,key in ipairs({"content","frame"})do if self[key]then self[key]:free();self[key]=nil end end
    for _,l in pairs(self.layers)do if l.free then l:free()end end;self.layers={}
end

load("ui/views").install(Studio)
load("ui/faces").install(Studio)
return Studio
