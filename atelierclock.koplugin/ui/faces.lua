-- Collection carousel, catalogue, slot-based editing and the complication
-- sheet. The legacy free layout remains for imported v1 packages.
local load=...
local C=load("core/collection")
local U=load("core/util")
local D=load("render/draw")
local Kit=load("ui/kit")
local Icon=load("ui/icons")
local Motion=load("ui/motion")
local Scene=load("render/scene")
local M={}
local MODES={{"style","Style","style"},{"complications","Modules","layers"},{"options","Options","sliders"}}
local STYLE_LABELS={plein="Plein",fin="Fin",contour="Contour"}
function M.install(S)
    -------------------------------------------------------------- caches
    function S:clearFaces()
        for _,c in pairs(self.cards or {})do if c.scene then c.scene:free()end end
        self.cards={}
        for _,key in ipairs({"gallery_scene","picker_scene"})do if self[key]then self[key]:free();self[key]=nil end end
        if self.title_layer then self.title_layer:free();self.title_layer=nil end
    end
    function S:faceList()
        local result={}
        if self.catalog then for _,f in ipairs(self.app.faces)do result[#result+1]={face=f.id,title=f.name}end
        else for _,v in ipairs(self.draft.collection)do result[#result+1]=v end end
        return result
    end
    local function signature(self,item)
        local s=self.draft
        local parts={item.face,item.uid or "",item.style or "",item.appearance or "",s.format,s.locale,s.date_format,s.night,self.catalog and "c"or "m"}
        if item.slots then local keys={};for id in pairs(item.slots)do keys[#keys+1]=id end;table.sort(keys)
            for _,id in ipairs(keys)do parts[#parts+1]=id.."="..tostring(item.slots[id].provider)..tostring(item.slots[id].zone)end end
        return table.concat(parts,"|")
    end
    -- One rendered preview per variant, kept across refreshes.
    function S:card(item,pw,ph)
        self.cards=self.cards or {}
        local key=signature(self,item)..math.floor(pw).."x"..math.floor(ph)
        local c=self.cards[key]
        if c then return c end
        local count=0;for _ in pairs(self.cards)do count=count+1 end
        if count>14 then self:clearFaces();self.cards={}end
        local ok,f=pcall(self.app.face,self.app,item.face)
        if not ok then return nil end
        local s=U.copy(self.draft);s.face=f.id;s.active_id=item.uid or "";s.image_enabled=false
        local scene=Scene.new(self.app,f,s,pw,ph)
        local good=pcall(scene.render,scene,os.time())
        c={scene=good and scene or nil,face=f};if not good then scene:free()end
        self.cards[key]=c;return c
    end
    function S:browse(delta)
        self.browser_index=U.clamp((self.browser_index or 1)+delta,1,math.max(1,#self:faceList()))
        self:syncCarousel(true);self:refresh()
    end
    function S:selectItem(item)
        if item.uid then C.select(self.draft,item)else self.draft.face=item.face end
        self:markDirty();self.edit_mode="complications";self.slot_picker=nil;self:refresh()
    end
    -------------------------------------------------------------- carousel
    function S:syncCarousel(animated)
        local c=self.carousel;if not c or not self.spacing then return end
        local target=((self.browser_index or 1)-1)*self.spacing
        if animated and self:animated()then c:settle(target)else c:scrollTo(target,false)end
    end
    function S:stepCarousel(dt,instant)
        local c=self.carousel;if not c or self.tab~="Galerie"then return false end
        if instant and not c.dragging then
            if c:moving()then c:settle();c.offset=c.spring.target;c.settling=false end
            return false
        end
        local moving=c:step(dt)
        if not moving and not c.dragging and self.spacing then
            local i=math.floor(c.offset/self.spacing+.5)+1
            if i~=self.browser_index then self.browser_index=i;self.content_dirty=true end
        end
        return moving
    end
    function S:carouselChanged()self.frame_dirty=true end
    function S:carouselSettle()
        local c=self.carousel;if not c or not self.spacing then return end
        local target=c.spring.target
        self.browser_index=U.clamp(math.floor(target/self.spacing+.5)+1,1,math.max(1,#self:faceList()))
        self.content_dirty=true
        if not self:animated()then c.offset=target;c.settling=false end
    end
    function S:carouselFling(dir)
        local n=#self:faceList()
        self.browser_index=U.clamp((self.browser_index or 1)+dir,1,math.max(1,n))
        if self.carousel and self.spacing then self:syncCarousel(true)end
        self.content_dirty=true;self:request()
    end
    -------------------------------------------------------------- gallery
    function S:galleryView()
        local k,kit,w,p=self.k,self.kit,self.w,self.pad;local W=w-2*p;local vh=self.bottom-self.top
        local list=self:faceList();local n=#list
        self.browser_index=U.clamp(self.browser_index or 1,1,math.max(1,n))
        local seg_y,seg_h=10*k,46*k
        local cy=seg_y+seg_h+20*k
        local reserve=(vh>520*k and 190 or 160)*k
        local ph=math.max(120*k,vh-cy-reserve);local pw=math.min(W*.64,ph*758/1024);ph=math.floor(pw*1024/758);pw=math.floor(pw)
        self.spacing=pw+22*k
        if not self.carousel then
            self.carousel=Motion.scroller{omega=15,zeta=.84,snap=function(projected,velocity,offset)
                local sp=self.spacing;local i=offset/sp
                local target=math.floor(projected/sp+.5)
                -- A flick always moves at least one card, never more than three.
                if math.abs(velocity)>350 then target=velocity>0 and math.max(target,math.floor(i)+1)or math.min(target,math.ceil(i)-1)end
                target=U.clamp(target,math.floor(i+.5)-3,math.floor(i+.5)+3)
                return target*sp
            end}
            self.carousel.offset=(self.browser_index-1)*self.spacing
        end
        self.carousel:setBounds(0,math.max(0,(n-1)*self.spacing))
        if not self.carousel:moving()then self.carousel.offset=(self.browser_index-1)*self.spacing end
        local item=list[self.browser_index]
        local view={height=vh}
        local info_y=cy+ph+18*k
        view.draw=function(bb)
            -- Collection / catalogue switch with a gliding indicator.
            local at=self.catalog and 2 or 1
            self.cat_spring=self.cat_spring or Motion.spring(at,{omega=22,zeta=.8,eps=.004})
            self.cat_spring:set(at);if not self:animated()then self.cat_spring:jump(at)end
            local segitems={{label="Mes cadrans",icon="gallery"},{label="Catalogue",icon="plus"}}
            local function seg(b,r)kit:segmented(b,r.x,r.y,r.w,r.h,segitems,self.cat_spring.x)end
            local box=self:region(p,seg_y,W,seg_h,nil,{paint=seg,info=true});seg(bb,box)
            self:glide(box,self.cat_spring)
            for i=1,2 do
                self:region(p+(i-1)*W/2,seg_y,W/2,seg_h,function()
                    local cat=i==2;if cat==(self.catalog==true)then return end
                    self.catalog=cat;self.browser_index=1;self.cat_spring:set(i)
                    if self.carousel then self.carousel:scrollTo(0,false)end
                    self:beginTransition(cat and 1 or -1);self:refresh()
                end,{radius=seg_h/2,segment=i})
            end
            if not item then
                Icon.draw(bb,"gallery",w/2-24*k,cy+ph/2-60*k,48*k,Kit.line)
                kit:text(bb,"Votre collection est vide",w/2,cy+ph/2,Kit.size.heading,0,"center",W,true)
                kit:text(bb,"Ouvrez le catalogue pour choisir un cadran.",w/2,cy+ph/2+34*k,Kit.size.small,Kit.muted,"center",W)
                return
            end
            -- Actions follow the card under the finger.
            local by=vh-62*k;local bh=50*k
            if self.catalog then
                local bw=(W-12*k)/2
                kit:button(bb,p,by,bw,bh,"Importer",{style="secondary",icon="import"})
                self:region(p,by,bw,bh,function()self:importClock()end,{radius=bh/2,action="import"})
                kit:button(bb,p+bw+12*k,by,bw,bh,"Ajouter",{style="primary",icon="plus"})
                self:region(p+bw+12*k,by,bw,bh,function()local it=self:faceList()[self.browser_index];if it then self:addFace(self.app:face(it.face))end end,{radius=bh/2,action="add"})
            else
                local cs=bh;local gap=10*k;local bw=(W-2*cs-3*gap)/2
                kit:iconButton(bb,p,by,cs,"more")
                self:region(p,by,cs,cs,function()self:moreSheet()end,{radius=cs/2,action="more"})
                kit:button(bb,p+cs+gap,by,bw,bh,"Modifier",{style="secondary",icon="edit"})
                self:region(p+cs+gap,by,bw,bh,function()local it=self:faceList()[self.browser_index];if it then self:selectItem(it);self:switchTab("Composer")end end,{radius=bh/2,action="edit"})
                kit:button(bb,p+cs+2*gap+bw,by,bw,bh,"Utiliser",{style="primary",icon="check"})
                self:region(p+cs+2*gap+bw,by,bw,bh,function()local it=self:faceList()[self.browser_index];if it then self:selectItem(it);self:apply()end end,{radius=bh/2,action="use"})
                kit:iconButton(bb,p+W-cs,by,cs,"play",{filled=true})
                self:region(p+W-cs,by,cs,cs,function()
                    local it=self:faceList()[self.browser_index];if not it then return end
                    self:selectItem(it);self:launchClock(self.card_box)
                end,{radius=cs/2,action="play"})
            end
        end
        -- Cards, dots and title are drawn per frame from cached layers.
        view.overlay=function(f,dx,dy,transitioning)
            if not item then self.carousel_box=nil;return end
            local off=self.carousel.offset;local sp=self.spacing
            local x0=w/2-pw/2+dx;local y0=cy+dy
            local first=math.max(1,math.floor(off/sp)-1);local last=math.min(n,math.ceil(off/sp)+2)
            for i=first,last do
                local x=x0+(i-1)*sp-off
                if x+pw>-sp and x<w+sp then
                    local c=self:card(list[i],pw,ph)
                    local dist=math.min(1,math.abs((i-1)*sp-off)/sp)
                    local lift=math.floor((1-dist)*6*k)
                    D.round(f,x+3*k,y0+6*k-lift,pw,ph,14*k,Kit.shade)
                    if c and c.scene and c.scene.frame then self.blit(f,c.scene.frame,x,y0-lift,0,0,pw,ph)end
                    if dist>.02 then self.shade(f,x,y0-lift,pw,ph,.55*dist,false)end
                    D.roundBorder(f,x-1,y0-1-lift,pw+2,ph+2,12*k,dist<.5 and 0 or Kit.line,math.max(2,(dist<.5 and 2 or 1.5)*k))
                    if not transitioning and math.abs(x-x0)<sp*.6 then
                        self.card_box={x=x,y=y0-lift,w=pw,h=ph}
                        local it=list[i]
                        self:region(x,y0-lift,pw,ph,function()
                            if self.catalog then self:addFace(self.app:face(it.face))
                            else self:selectItem(it);self:switchTab("Composer")end
                        end,{radius=12*k,card=i,hold=function()if not self.catalog then self:moreSheet()end end})
                    elseif not transitioning then
                        self:region(math.max(0,x),y0,math.min(pw,w-math.max(0,x)),ph,function()
                            self.browser_index=i;self:syncCarousel(true);self.content_dirty=true;self:request()
                        end,{card=i})
                    end
                end
            end
            self.carousel_box={x=0,y=y0,w=w,h=ph}
            local at=off/sp+1
            kit:dots(f,w/2+dx,info_y+dy,n,at)
            local idx=U.clamp(math.floor(at+.5),1,n)
            if self.title_index~=idx or not self.title_layer or self.title_catalog~=self.catalog then
                if self.title_layer then self.title_layer:free()end
                local it=list[idx];local ok,face=pcall(self.app.face,self.app,it.face)
                local tl=self.newBB(W,62*k)
                kit:text(tl,it.title or(ok and face.name)or "",W/2,4*k,Kit.size.heading,0,"center",W,true)
                local sub=ok and(self.catalog and(face.category or face.subtitle or "")or(face.name..(it.uid and(" · "..(STYLE_LABELS[it.style]or "Plein"))or "")))or ""
                if not self.catalog and self.draft.active_id==it.uid then sub="Active · "..sub end
                kit:text(tl,sub,W/2,34*k,Kit.size.small,Kit.muted,"center",W)
                self.title_layer=tl;self.title_index=idx;self.title_catalog=self.catalog
            end
            self.blit(f,self.title_layer,p+dx,info_y+14*k+dy,0,0,W,62*k)
        end
        return view
    end
    function S:moreSheet()
        local list=self:faceList();local item=list[self.browser_index];if not item then return end
        local f=self.app:face(item.face);local k,kit=self.k,self.kit
        local actions={
            {"copy","Dupliquer",function()
                local v,e=C.add(self.draft,f,item);self.status=e or "Variante ajoutée"
                if v then self.browser_index=#self.draft.collection;self:markDirty();self:syncCarousel(true)end;self:refresh()
            end},
            {"rename","Renommer",function()
                self:input("Nom de cette variante",item.title,function(value)
                    if #value>0 and #value<=80 then item.title=value;self:markDirty()else self.status="Nom de 1 à 80 octets"end;self:clearFaces();self:refresh()
                end)
            end},
            {"play","Afficher en plein écran",function()self:selectItem(item);self:launchClock(self.card_box)end},
            {"trash","Retirer de mes cadrans",function()
                if #self.draft.collection<=1 then self.status="Conserver au moins un cadran";self:refresh();return end
                self:confirmSheet("Retirer « "..(item.title or f.name).." » ?","Le modèle reste disponible dans le catalogue.","Retirer",function()
                    table.remove(self.draft.collection,self.browser_index)
                    if self.draft.active_id==item.uid then C.select(self.draft,self.draft.collection[1])end
                    self.browser_index=U.clamp(self.browser_index,1,#self.draft.collection)
                    self:markDirty();self:syncCarousel(false);self:refresh()
                end,true)
            end,true},
        }
        local rh=60*k
        self:openSheet{title=item.title or f.name,subtitle=f.name,content_h=#actions*rh+8*k,draw=function(bb,w)
            local p=self.pad
            for i,a in ipairs(actions)do
                local y=(i-1)*rh
                if i>1 then D.rect(bb,p+52*k,y,w-2*p-52*k,1,Kit.line)end
                D.circle(bb,p+22*k,y+rh/2,20*k,Kit.wash);Icon.draw(bb,a[1],p+11*k,y+rh/2-11*k,22*k,0)
                kit:text(bb,a[2],p+56*k,y+rh/2-12*k,Kit.size.body,0,"left",w-2*p-70*k,a[4])
                self:region(p,y,w-2*p,rh,function()self:closeSheet();a[3]()end,{action=a[1]})
            end
        end}
    end
    function S:addFace(face)
        local item,e=C.add(self.draft,face);self.status=e or "Cadran ajouté — touchez un module"
        if item then
            self:markDirty();self.catalog=false;self.browser_index=#self.draft.collection;self.edit_mode="complications"
            if self.carousel then self.carousel:scrollTo((self.browser_index-1)*(self.spacing or 0),false)end
            self:switchTab("Composer");return
        end
        self:refresh()
    end
    function S:importClock()
        self:input("Fichier .clock — chemin complet","/mnt/onboard/",function(path)
            local f,e=self.app:import(path);self.status=f and "Importé dans le catalogue"or tostring(e)
            if f then self.catalog=true;self.browser_index=#self.app.faces;self:syncCarousel(false)end;self:refresh()
        end)
    end
    function S:editInstance()
        local item=C.current(self.draft)
        if not item then item=C.add(self.draft,self.app:face(self.draft.face));self:markDirty()end
        return item
    end
    -------------------------------------------------------------- composer v2
    function S:facePreview(bb,x,y,w,h,interactive)
        local ratio=self.app.device.screen:getWidth()/self.app.device.screen:getHeight()
        if self.draft.rotation~="follow"then ratio=tonumber(self.draft.rotation)%2==1 and 1024/758 or 758/1024 end
        local pw=math.floor(math.min(w,h*ratio));local ph=math.floor(pw/ratio);local px=math.floor(x+(w-pw)/2);local py=math.floor(y+(h-ph)/2)
        if not self.preview then self.preview=Scene.new(self.app,self.app:face(self.draft.face),self.draft,pw,ph);self.preview:render(os.time())end
        D.round(bb,px+3*self.k,py+6*self.k,pw,ph,12*self.k,Kit.shade)
        self.preview:paintTo(bb,px,py);D.roundBorder(bb,px-1,py-1,pw+2,ph+2,10*self.k,0,2)
        self.preview_box={x=px,y=py+self.top-self.scroll:value(),w=pw,h=ph}
        self.slot_rects={}
        if interactive then
            local face=self.app:face(self.draft.face);local layout=face.layouts[pw>ph and "landscape"or "portrait"]
            local k=self.k
            for _,slot in ipairs(face.slots)do local b=layout.slots[slot.id];local sx,sy,sw,sh=px+b[1]*pw,py+b[2]*ph,b[3]*pw,b[4]*ph
                D.roundBorder(bb,sx-4,sy-4,sw+8,sh+8,8*k,255,5);D.roundBorder(bb,sx-3,sy-3,sw+6,sh+6,7*k,0,2)
                local badge=math.min(13*k,sh*.3)
                D.circle(bb,sx+sw,sy,badge+2,255);D.circle(bb,sx+sw,sy,badge,0)
                D.line(bb,sx+sw-badge*.5,sy,sx+sw+badge*.5,sy,255,2);D.line(bb,sx+sw,sy-badge*.5,sx+sw,sy+badge*.5,255,2)
                self.slot_rects[slot.id]={x=sx,y=sy+self.top-self.scroll:value(),w=sw,h=sh}
                self:region(sx,sy,sw,sh,function()self.slot_picker=slot.id;self.picker_page=1;self:refresh()end,{slot_id=slot.id,radius=7*k})
            end
        end
    end
    function S:composerView()
        local face=self.app:face(self.draft.face)
        if face.schema_version~=2 then
            if self.sheet and self.sheet.kind=="picker"then self:closeSheet(true)end
            return self:legacyComposer()
        end
        local item=self:editInstance();local k,kit,w,p=self.k,self.kit,self.w,self.pad;local W=w-2*p;local vh=self.bottom-self.top
        local mode=self.edit_mode or "complications"
        if self.slot_picker and not self.sheet then self:complicationSheet(face,item)
        elseif not self.slot_picker and self.sheet and self.sheet.kind=="picker"then self:closeSheet(true)end
        local at=1;for i,m in ipairs(MODES)do if m[1]==mode then at=i end end
        self.mode_spring=self.mode_spring or Motion.spring(at,{omega=22,zeta=.8,eps=.004})
        self.mode_spring:set(at);if not self:animated()then self.mode_spring:jump(at)end
        local seg_y,seg_h=10*k,46*k
        local function segment(bb)
            local items={};for i,m in ipairs(MODES)do items[i]={label=m[2],icon=m[3]}end
            local function seg(b,r)kit:segmented(b,r.x,r.y,r.w,r.h,items,self.mode_spring.x)end
            local box=self:region(p,seg_y,W,seg_h,nil,{paint=seg,info=true});seg(bb,box)
            for i,m in ipairs(MODES)do
                self:region(p+(i-1)*W/3,seg_y,W/3,seg_h,function()self:setEditMode(m[1])end,{radius=seg_h/2,mode=m[1]})
            end
            self:glide(box,self.mode_spring)
        end
        local y0=seg_y+seg_h+18*k
        if mode=="options"then
            local rows={
                {"rename","Nom de la variante","action",icon="rename",value=item.title,callback=function()
                    self:input("Nom de cette variante",item.title,function(value)if #value>0 and #value<=80 then item.title=value;self:markDirty()else self.status="Nom de 1 à 80 octets"end;self:refresh()end)
                end},
                {"export","Exporter en .clock","action",icon="export",callback=function()
                    U.mkdir(self.app.data_dir.."/exports")
                    self:input("Exporter ce cadran .clock",self.app.data_dir.."/exports/"..item.face.."-"..item.uid..".clock",function(path)
                        local file,e=load("packages/export").write(self.app,self.draft,path);self.status=file and "Cadran exporté"or tostring(e);self:refresh()
                    end)
                end},
            }
            local fmt={{"rotation","Orientation","choice"},{"format","Format de l’heure","choice"},{"locale","Langue","choice"},{"date_format","Date","choice"}}
            local ui={{"ui_scale","Taille de l’interface",85,140,5,"%"}}
            local function h(list)local s=24*k;for _,r in ipairs(list)do s=s+self:rowHeight(r)end;return s+22*k end
            return {height=y0+h(rows)+h(fmt)+h(ui)+90*k,draw=function(bb)
                segment(bb);local y=y0
                y=y+self:group(bb,"Variante",rows,p,y,W)+22*k
                y=y+self:group(bb,"Heure et date",fmt,p,y,W)+22*k
                self:group(bb,"Lisibilité",ui,p,y,W)
            end}
        end
        local view={height=vh}
        view.draw=function(bb)
            segment(bb)
            if mode=="complications"then
                local ph=vh-y0-56*k
                self:facePreview(bb,p,y0,W,ph,true)
                kit:text(bb,"Touchez un module + pour changer son contenu",w/2,y0+ph+16*k,Kit.size.small,Kit.muted,"center",W)
            else
                local ph=vh-y0-150*k
                self:facePreview(bb,p,y0,W,ph,false)
                local by=y0+ph+18*k;local gap=10*k;local count=#face.styles;local cw=(W-(count-1)*gap)/count
                for i,style in ipairs(face.styles)do
                    local x=p+(i-1)*(cw+gap);local active=item.style==style
                    D.round(bb,x,by,cw,54*k,16*k,active and 0 or 255)
                    if not active then D.roundBorder(bb,x,by,cw,54*k,16*k,Kit.line,math.max(1,1.5*k))end
                    local ink=active and 255 or 0
                    D.text(bb,"12",x+cw*.27,by+9*k,32*k,ink,"center",cw*.4,style=="fin"and "tfont"or "cfont",style~="fin",style=="contour"and 1 or 0)
                    kit:text(bb,STYLE_LABELS[style]or style,x+cw*.5,by+17*k,Kit.size.small,ink,"left",cw*.47,active)
                    self:region(x,by,cw,54*k,function()item.style=style;self:markDirty();self:clearFaces();self:refresh()end,{style_id=style,radius=16*k})
                end
                local ay=by+68*k
                local looks={{"paper","Papier","sun"},{"ink","Encre","drop"},{"follow","Auto","auto"}}
                local at2=1;for i,v in ipairs(looks)do if item.appearance==v[1]then at2=i end end
                local items={};for i,v in ipairs(looks)do items[i]={label=v[2],icon=v[3]}end
                kit:segmented(bb,p,ay,W,46*k,items,at2)
                for i,v in ipairs(looks)do
                    self:region(p+(i-1)*W/3,ay,W/3,46*k,function()item.appearance=v[1];self:markDirty();self:clearFaces();self:refresh()end,{appearance=v[1],radius=23*k})
                end
            end
        end
        view.overlay=function(f,dx,dy)self:drawFly(f)end
        return view
    end
    function S:setEditMode(mode)
        local current=self.edit_mode or "complications"
        if mode==current then return end
        local a,b=1,1;for i,m in ipairs(MODES)do if m[1]==current then a=i end;if m[1]==mode then b=i end end
        self:beginTransition(b>a and 1 or -1)
        self.edit_mode=mode;self.page=1;self.scroll:scrollTo(0,false);self:refresh()
    end
    function S:swipeHorizontal(dir)
        if self.tab~="Composer"then return false end
        local ok,face=pcall(self.app.face,self.app,self.draft.face)
        if not ok or face.schema_version~=2 then return false end
        local n=2;for i,m in ipairs(MODES)do if m[1]==(self.edit_mode or "complications")then n=i end end
        local target=MODES[n+dir]
        if target then self:setEditMode(target[1])
        else local tabs={"Galerie","Composer","Veille","Diagnostic"};self:switchTab(tabs[2+dir],dir)end
        return true
    end
    -- Complication sheet: live renders of every compatible content.
    function S:complicationSheet(face,item)
        local spec;for _,v in ipairs(face.slots)do if v.id==self.slot_picker then spec=v end end
        if not spec then self.slot_picker=nil;return end
        local config=C.slot(item,face,spec.id)
        local k,kit=self.k,self.kit;local gap=12*k
        local cols=2;local rows=math.ceil(#spec.allowed/cols)
        local ch=math.floor(math.min(150*k,(self.h*.62-80*k)/math.max(1,rows)));local extra=config.provider=="world"and 66*k or 30*k
        local slot_id=spec.id
        self:openSheet{kind="picker",title=spec.label,subtitle="Données locales · aucun accès réseau",
            content_h=rows*(ch+gap)+extra,draw=function(bb,w)
            local p=self.pad;local cw=(w-2*p-gap)/cols
            for i,provider in ipairs(spec.allowed)do
                local x=p+(i-1)%cols*(cw+gap);local y=math.floor((i-1)/cols)*(ch+gap)
                local active=provider==config.provider
                -- Use the exact complication renderer and slot family for previews.
                local fake=U.copy(face);fake.texture=nil;fake.slots={U.copy(spec)};fake.slots[1].default=provider
                fake.layouts={portrait={blocks={},slots={[spec.id]={.06,.06,.88,.88}}},landscape={blocks={},slots={[spec.id]={.06,.06,.88,.88}}}}
                local s=U.copy(self.draft);local o=C.current(s);o.slots[spec.id]={provider=provider,zone=config.zone};o.appearance="paper"
                local sh=math.max(1,math.floor(ch-36*k));local pw=math.floor(cw-16*k)
                D.round(bb,x,y,cw,ch,18*k,255)
                local scene=Scene.new(self.app,fake,s,pw,sh)
                if pcall(scene.render,scene,os.time())then scene:paintTo(bb,x+8*k,y+4*k)end;scene:free()
                if provider=="none"then Icon.draw(bb,"close",x+cw/2-15*k,y+sh/2-11*k,30*k,Kit.muted)end
                D.roundBorder(bb,x,y,cw,ch,18*k,active and 0 or Kit.line,active and math.max(3,2.5*k)or math.max(1,1.5*k))
                kit:text(bb,C.names[provider],x+cw/2,y+ch-30*k,Kit.size.small,0,"center",cw-40*k,true)
                if active then D.circle(bb,x+cw-20*k,y+20*k,11*k,0);Icon.draw(bb,"check",x+cw-28*k,y+12*k,16*k,255)end
                self:region(x,y,cw,ch,function(r)
                    item.slots[slot_id]={provider=provider,zone=config.zone};self:markDirty();self.slot_picker=nil
                    self:flyTo(r,slot_id)
                    self:closeSheet();self:refresh()
                end,{provider=provider,radius=18*k})
            end
            if config.provider=="world"then
                local y=rows*(ch+gap)+4*k;local zone=config.zone
                kit:button(bb,p,y,w-2*p,50*k,"Fuseau : "..zone,{style="soft",icon="globe"})
                self:region(p,y,w-2*p,50*k,function()
                    for i,z in ipairs(C.zones)do if z==zone then zone=C.zones[i%#C.zones+1];break end end
                    item.slots[slot_id]={provider="world",zone=zone};self:markDirty();self:buildSheet();self.preview=nil;self:refresh()
                end,{zone=zone})
            end
        end,on_close=function()self.slot_picker=nil end}
    end
    S.complicationPicker=S.complicationSheet
    -- A ghost frame flies from the chosen card to its slot, then pulses.
    function S:flyTo(from,slot_id)
        if not self:animated()then return end
        local to=self.slot_rects and self.slot_rects[slot_id];if not to then return end
        local tw=Motion.tween(0,1,.46,"inOutCubic",Motion.now())
        local fly={from={x=from.x,y=from.y,w=from.w,h=from.h},to=to,e=0}
        self.fly=fly
        self:animate(function(now,instant)
            if self.fly~=fly then return false end
            local t=instant and 1.6 or(now-tw.start)/tw.duration
            fly.e=Motion.ease.inOutCubic(math.min(1,t));fly.pulse=t>1 and math.min(1,(t-1)/.6)or nil
            if t>=1.6 then self.fly=nil;return false end
            return true
        end)
    end
    function S:drawFly(f)
        local fl=self.fly;if not fl then return end
        local a,b=fl.from,fl.to;local e=fl.e
        if not fl.pulse then
            local x,y=Motion.lerp(a.x,b.x,e),Motion.lerp(a.y,b.y,e)
            local w,h=Motion.lerp(a.w,b.w,e),Motion.lerp(a.h,b.h,e)
            D.roundBorder(f,x,y,w,h,12*self.k,0,math.max(3,3*self.k))
        else
            local grow=8*self.k*fl.pulse
            D.roundBorder(f,b.x-grow,b.y-grow,b.w+2*grow,b.h+2*grow,10*self.k,math.floor(255*fl.pulse),math.max(2,3*self.k*(1-fl.pulse)))
        end
    end
end
return M
