-- Settings rows, Veille, Diagnostic and the legacy (v1) free editor.
-- Views return {height, draw(bb)} in content coordinates; long lists scroll
-- instead of being paginated.
local load=...
local U=load("core/util")
local D=load("render/draw")
local Kit=load("ui/kit")
local Icon=load("ui/icons")
local Motion=load("ui/motion")
local Controls=load("ui/controls")
local Settings=load("core/settings")
local Scene=load("render/scene")
local M={}
local names={time="Time",date="Date",battery="Battery",wifi="Wi-Fi",memory="Memory",world="World"}
local element_icons={time="clock",date="info",battery="battery",wifi="wave",memory="layers",world="globe"}
local sections={"Disposition","Typographie","Habillage","Informations","Images","Lisibilité"}
local symbols={Disposition="move",Typographie="text",Habillage="style",Informations="info",Images="image",Lisibilité="sliders"}
local labels={auto="Automatic",fluid="Fluid",classic="Classic",full="Full",reduced="Reduced"}
local intervals={{60,"1 min","Precise time"},{300,"5 min","Approximate time"},{600,"10 min","Approximate time"},{900,"15 min","Approximate time"},{0,"Static","Frozen when the reader sleeps"}}
M.labels=labels
local function choiceLabel(key,value)
    if key=="interval"then for _,v in ipairs(intervals)do if v[1]==value then return v[1]==0 and "Static"or "Every "..v[2]end end end
    if key=="display_fps"then return tostring(value).." Hz"end
    return labels[value]or Controls.labels[value]or tostring(value)
end
local function options(key)
    if key=="interval"then local r={};for _,v in ipairs(intervals)do r[#r+1]=v[1]end;return r end
    if key=="display_fps"then return {30,45,60}end
    return Settings.choices[key]or {}
end

function M.install(S)
    -------------------------------------------------------------- rows
    function S:rowHeight(row)
        local kind=row[3]
        if type(kind)=="number"then return 98*self.k end
        if kind=="info"then return 62*self.k end
        return 64*self.k
    end
    function S:knob(key)
        local a=self.knobs and self.knobs[key]
        if a then return a.t end
        return U.get(self.draft,key)and 1 or 0
    end
    function S:paintRow(bb,row,x,y,w,h,divider)
        local k,kit=self.k,self.kit;local key,label,kind=row[1],row[2],row[3];local p=16*k
        if divider then D.rect(bb,x+p,y,w-2*p,1,Kit.line)end
        if kind=="bool"then
            kit:text(bb,label,x+p,y+h/2-12*k,Kit.size.body,0,"left",w-p-96*k,false)
            kit:switch(bb,x+w-p-56*k,y+(h-32*k)/2,self:knob(key))
        elseif type(kind)=="number"then
            local a,b,step,unit=row[3],row[4],row[5],row[6];local value=U.get(self.draft,key)
            kit:text(bb,label,x+p,y+12*k,Kit.size.body,0,"left",w-p-150*k,false)
            kit:text(bb,string.format(step<1 and "%.1f %s"or "%.0f %s",value,unit),x+w-p,y+12*k,Kit.size.body,0,"right",140*k,true)
            local f=U.clamp((value-a)/(b-a),0,1);local sx,sw=x+p+44*k,w-2*p-88*k;local sy=y+66*k
            D.round(bb,sx,sy-3*k,sw,6*k,3*k,Kit.line);D.round(bb,sx,sy-3*k,math.max(6*k,sw*f),6*k,3*k,0)
            D.circle(bb,sx+sw*f,sy,12*k,0);D.circle(bb,sx+sw*f,sy,5*k,255)
            Icon.draw(bb,"minus",x+p,sy-11*k,22*k,0);Icon.draw(bb,"plus",x+w-p-22*k,sy-11*k,22*k,0)
        elseif kind=="info"then
            kit:text(bb,label,x+p,y+10*k,Kit.size.small,Kit.muted,"left",w-2*p)
            local v=row[4];if type(v)=="function"then local ok,r=pcall(v);v=ok and r or "—"end
            kit:text(bb,tostring(v or "—"),x+p,y+31*k,Kit.size.body,0,"left",w-2*p,true)
        elseif kind=="action"then
            if row.icon then Icon.draw(bb,row.icon,x+p,y+h/2-11*k,22*k,row.danger and 0 or 0)end
            kit:text(bb,label,x+p+(row.icon and 36*k or 0),y+h/2-12*k,Kit.size.body,0,"left",w-2*p-(row.icon and 36*k or 0)-(row.value and 150*k or 30*k),row.bold)
            if row.value then kit:text(bb,row.value,x+w-p-24*k,y+h/2-11*k,Kit.size.small,Kit.muted,"right",140*k)end
            Icon.draw(bb,row.chevron or "right",x+w-p-16*k,y+h/2-8*k,16*k,Kit.muted)
        else
            local value=U.get(self.draft,key)
            local desc=kind=="text"and(value~=""and tostring(value)or "Not set")or choiceLabel(key,value)
            kit:text(bb,label,x+p,y+h/2-12*k,Kit.size.body,0,"left",(w-2*p)*.55,false)
            kit:text(bb,desc,x+w-p-24*k,y+h/2-11*k,Kit.size.small,Kit.muted,"right",(w-2*p)*.42)
            Icon.draw(bb,kind=="text"and "rename"or "right",x+w-p-16*k,y+h/2-8*k,16*k,Kit.muted)
        end
    end
    -- Grouped rows inside one rounded card; returns the consumed height.
    function S:group(bb,title,rows,x,y,w)
        local k=self.k;local top=y
        if title then self.kit:section(bb,title,x,y,w);y=y+24*k end
        local h=0;for _,r in ipairs(rows)do h=h+self:rowHeight(r)end
        self.kit:card(bb,x,y,w,h,{radius=18*k,shadow=false,stroke_color=Kit.line,stroke_width=math.max(1,1.5*k)})
        local yy=y
        for i,row in ipairs(rows)do
            local rh=self:rowHeight(row)
            self:paintRow(bb,row,x,yy,w,rh,i>1)
            self:rowRegion(row,x,yy,w,rh,i>1)
            yy=yy+rh
        end
        return yy-top
    end
    function S:rowRegion(row,x,y,w,h,divider)
        local k=self.k;local key,label,kind=row[1],row[2],row[3]
        local function paint(bb,r)self:paintRow(bb,row,r.x,r.y,r.w,r.h,divider)end
        -- Live repaints clear only the row interior: card strokes and rounded
        -- corners around grouped rows are never erased.
        local clear={x=x+10*k,y=y+4*k,w=w-20*k,h=h-8*k}
        if kind=="bool"then
            local r;r=self:region(x,y,w,h,function()
                local value=not U.get(self.draft,key)
                if row.onchange then return row.onchange(value)end
                if key=="fast_rtc"and value and not self.app.kobo.supported then self.status="Kobo Aura 2 only";self:refresh();return end
                U.set(self.draft,key,value);self:markDirty()
                self:animateKnob(key,value,r)
            end,{paint=paint,key=key,clear=clear})
        elseif type(kind)=="number"then
            local a,b,step=row[3],row[4],row[5]
            local function set(v)
                v=U.clamp(math.floor((v-a)/step+.5)*step+a,a,b)
                if math.abs(v-U.get(self.draft,key))<1e-9 then return end
                U.set(self.draft,key,v);self:markDirty()
            end
            local box
            local sx,sw=x+16*k+44*k,w-32*k-88*k
            box=self:region(x,y,w,h*.5,nil,{paint=paint,key=key,info=true,clear=clear})
            self:region(x,y+h*.5,48*k,h*.5,function()set(U.get(self.draft,key)-step);self:repaint(box);self:request()end,{key=key,step=-1})
            self:region(x+w-48*k,y+h*.5,48*k,h*.5,function()set(U.get(self.draft,key)+step);self:repaint(box);self:request()end,{key=key,step=1})
            self:region(sx,y+h*.5,sw,h*.5,nil,{slider=function(px)set(a+U.clamp((px-sx)/sw,0,1)*(b-a));self:repaint(box);self:request()end,key=key})
            box.h=h -- repaint covers the whole row
        elseif kind=="info"then
            self:region(x,y,w,h,nil,{paint=paint,info=true,key=key,clear=clear})
        elseif kind=="action"then
            self:region(x,y,w,h,function()row.callback()end,{paint=paint,action=label})
        else
            self:region(x,y,w,h,function()
                if kind=="text"then self:input(label,U.get(self.draft,key),function(v)self:change(key,v)end);return end
                local list=options(key);local value=U.get(self.draft,key)
                if #list<=2 then for i,v in ipairs(list)do if v==value then self:change(key,list[i%#list+1]);return end end;return end
                local opts={};for _,v in ipairs(list)do opts[#opts+1]={value=v,label=choiceLabel(key,v)}end
                self:choiceSheet(label,opts,value,function(v)
                    if key=="rotation"and v~="follow"then
                        local ok=pcall(function()return tonumber(v)end);if not ok then return end
                    end
                    self:change(key,v)
                end)
            end,{paint=paint,key=key})
        end
    end
    function S:animateKnob(key,value,r)
        self.knobs=self.knobs or {}
        local target=r.content or r
        if not self:animated()then self.knobs[key]=nil;self:repaint(target);self:request();return end
        local tw=Motion.tween(value and 0 or 1,value and 1 or 0,.2,"outBack",Motion.now())
        local a={t=tw.from};self.knobs[key]=a
        self:animate(function(now,instant)
            if self.knobs[key]~=a or(target.gen and target.gen~=self.content_gen)then self.knobs[key]=nil;return false end
            a.t=instant and tw.to or tw:value(now)
            self:repaint(target)
            if instant or tw:done(now)then self.knobs[key]=nil;self:repaint(target);return false end
            return true
        end)
    end

    -------------------------------------------------------------- veille
    function S:powerView()
        local k,kit,w,p=self.k,self.kit,self.w,self.pad;local W=w-2*p
        local caps=load("power/capabilities").detect(self.app.device)
        local adv={}
        for _,r in ipairs(Controls.sections().Veille)do if r[1]~="interval"and r[1]~="fast_rtc"then adv[#adv+1]=r end end
        local wake={{"rtc","Scheduled wake-up","info",caps.label.." · "..caps.model}}
        wake[#wake+1]={"fast_rtc","Aura 2 priority wake-up","bool"}
        wake[#wake+1]={"optimize","Optimise for Aura 2","action",callback=function()
            if not self.app.kobo.supported then self.status="Kobo Aura 2 only";self:refresh();return end
            self.draft.fast_rtc=true;self.draft.reuse_suspend=true;self.draft.wake_margin=.1;self:markDirty()
            self.status="Aura 2 profile ready — Apply";self:refresh()
        end,icon="spark",bold=true}
        local function height(rows)local h=24*k;for _,r in ipairs(rows)do h=h+self:rowHeight(r)end;return h end
        local hero=124*k;local freq=24*k+52*k+34*k
        local total=12*k+hero+22*k+freq+22*k+height(wake)+22*k+height(adv)+60*k+90*k
        local view={height=total}
        local adv_y
        view.draw=function(bb)
            local y=12*k
            local on=G_reader_settings:readSetting("screensaver_type")=="atelierclock"
            kit:card(bb,p,y,W,hero,{radius=24*k,fill=on and 0 or 255})
            local ink=on and 255 or 0
            D.circle(bb,p+44*k,y+hero/2,26*k,on and 255 or Kit.wash)
            Icon.draw(bb,"moon",p+31*k,y+hero/2-13*k,26*k,0)
            kit:text(bb,"Clock on the sleep screen",p+86*k,y+30*k,Kit.size.heading,ink,"left",W-190*k,true)
            local sub=on and(self.draft.interval==0 and "On · static image"or "On · "..choiceLabel("interval",self.draft.interval):lower())or "KOReader sleep screen"
            kit:text(bb,sub,p+86*k,y+62*k,Kit.size.small,on and 220 or Kit.muted,"left",W-190*k)
            local sx=p+W-80*k
            D.round(bb,sx,y+hero/2-17*k,60*k,34*k,17*k,on and 255 or 255)
            D.roundBorder(bb,sx,y+hero/2-17*k,60*k,34*k,17*k,on and 255 or 0,math.max(2,1.5*k))
            D.circle(bb,sx+(on and 43 or 17)*k,y+hero/2,12*k,0)
            self:region(p,y,W,hero,function()
                if on then self.app.integration:disable()else self.app.integration:select()end
                self.status=on and "Previous sleep screen restored"or "Clock enabled for the sleep screen";self:refresh()
            end,{role="screensaver"})
            y=y+hero+22*k
            kit:section(bb,"Refresh",p,y,W);y=y+24*k
            local items={};local active=1
            for i,v in ipairs(intervals)do items[i]=v[2];if self.draft.interval==v[1]then active=i end end
            self.interval_spring=self.interval_spring or Motion.spring(active,{omega=22,zeta=.78,eps=.004})
            self.interval_spring:set(active);if not self:animated()then self.interval_spring:jump(active)end
            local seg_y=y;local sw=W/#items
            local function seg(b,r)kit:segmented(b,r.x,r.y,r.w,r.h,items,self.interval_spring.x)end
            local box=self:region(p,seg_y,W,52*k,nil,{paint=seg,info=true})
            seg(bb,box);self:glide(box,self.interval_spring)
            for i,v in ipairs(intervals)do
                self:region(p+(i-1)*sw,seg_y,sw,52*k,function()
                    U.set(self.draft,"interval",v[1]);self:markDirty();self.interval_spring:set(i)
                    -- Caption and hero subtitle are rebuilt; the pill keeps gliding.
                    self:refresh()
                end,{interval=v[1]})
            end
            y=y+52*k+8*k
            local hint=intervals[active][3]
            if caps.kind=="kindle"and self.draft.interval==60 then hint="Kindle: ±15 s · 5 min recommended"end
            if not caps.available then hint=caps.detail end
            kit:text(bb,hint,p+6*k,y,Kit.size.small,Kit.muted,"left",W);y=y+26*k+22*k
            y=y+self:group(bb,"Wake-up",wake,p,y,W)+22*k
            adv_y=y
            y=y+self:group(bb,"Advanced settings",adv,p,y,W)+14*k
            self:paragraph(bb,caps.detail.." Battery life must be measured on the reader.",p+6*k,y,W-12*k,Kit.size.small,3,Kit.muted)
            if self.power_detail then view.scroll_to=adv_y end
        end
        return view
    end

    -------------------------------------------------------------- diagnostic
    function S:displayRows()
        local info=self.display:info()
        local rows={
            {"engine_now","Active engine","info",function()
                local i=self.display:info();local r=i.rates or {}
                local live=self.display:isFluid()and r.publish and string.format(" · %.0f targets/s · %.0f scans/s",r.publish,r.scans or 0)or ""
                return i.label..live
            end},
            {"engine_detail","Profile","info",info.detail or "—"},
            {"display_engine","Display engine","choice"},
            {"display_fps","Target frame rate","choice"},
            {"display_rest","Clean at rest","bool"},
            {"motion","Animations","choice"},
            {"clean","Clean the screen","action",icon="wave",callback=function()
                if not self.display:clean()then self.app.ui:setDirty(self,"full")end
                self.status="Screen cleaned";self:refresh()
            end},
        }
        if self.display.state=="classic"and self.draft.display_engine~="classic"then
            rows[#rows+1]={"retry","Retry the fluid engine","action",icon="spark",callback=function()
                load("engine/display").resetCache();self.display.notice=nil;self.display:select()
                if self.display:wanted()then self.display:start();self.status="Checking the engine…"
                else self.status=self.display.profile.detail end
                self:refresh()
            end}
        end
        return rows
    end
    function S:detailRows()
        local a,p=self.app,self.app.scheduler
        local measure=a.kobo.measure:update()
        local function seconds(n)return n and string.format("%.3f s",n)or "Unknown"end
        local info=self.display:info();local r=info.rates or {}
        local d={{"Version",load("core/version")},{"Model",a.device.model or "Unknown"},{"Detected DPI",tostring(self.dpi)},
            {"Resolution",self.w.." × "..self.h},
            {"Display",info.label},{"Engine profile",info.detail or "—"},
            {"Targets / scans per second",r.publish and string.format("%.1f / %.1f",r.publish,r.scans or 0)or "Engine idle"},
            {"Engine CPU",r.cpu and string.format("%.0f %%",r.cpu)or "—"},
            {"Scheduled wake-up",load("power/capabilities").detect(a.device).label},
            {"Last render",a.metrics.last and os.date("%H:%M:%S",a.metrics.last)or "None"},
            {"Requested area",(a.metrics.refresh_percent or 0).." % of the screen"},
            {"Area reduction (not energy)",a.metrics.requested_area_factor and string.format("× %.2f",a.metrics.requested_area_factor)or "No comparison"},
            {"Render CPU time",(a.metrics.render_ms or 0).." ms"},
            {"Session battery",a.metrics.battery_drop_points and a.metrics.battery_drop_points.." points / "..math.floor((a.metrics.session_seconds or 0)/60).." min"or "Measuring"},
            {"Callback delay",p.stats.alarm_lag_s and p.stats.alarm_lag_s.." s"or "Unknown"},
            {"Recoveries",tostring(p.stats.recoveries or 0)},{"Consecutive render errors",tostring(p.stats.consecutive_errors or 0)},
            {"KOReader wake-up budget",tostring(a.device.unexpected_wakeup_count or 0)},
            {"Last mem call duration",seconds(measure.native_last_sleep_s)},
            {"Total time in mem",seconds(measure.sleep_s)},
            {"Sleep (kernel clocks)",measure.verified_sleep_percent and string.format("%.1f %%",measure.verified_sleep_percent)or "Unavailable"},
            {"Wake → sleep request",seconds(measure.wake_to_suspend_s)},
            {"Short/refused mem returns",tostring(a.kobo.short_returns or 0)},
            {"Close native retries",tostring(a.kobo.retry_count or 0)},
            {"RTC standby cycles",tostring(a.kobo.settle.data.cycles or 0)},
            {"RTC standby sleep",seconds(measure.standby_verified_sleep_s)},
            {"RTC standby state",a.kobo.settle.data.reason or(a.kobo.settle.confirmed and "FP9928 driver confirmed"or "No confirmed FP9928 refusal")},
            {"Reused preparations",tostring(a.kobo.direct_used or 0)},
            {"Fallbacks after too short sleep",tostring(a.kobo.direct_fallbacks or 0)},
            {"Return to sleep",a.kobo.direct_reason or "No cycle measured"}}
        local rows={};for i,v in ipairs(d)do rows[i]={"detail"..i,v[1],"info",v[2]}end
        return rows
    end
    function S:diagnosticView()
        local k,kit,w,p=self.k,self.kit,self.w,self.pad;local W=w-2*p
        local a,sch=self.app,self.app.scheduler
        local disp=self:displayRows()
        local tools={
            {"details",self.diagnostic_detail and "Hide details"or "Technical details","action",icon="pulse",chevron=self.diagnostic_detail and "up"or "down",callback=function()
                self.diagnostic_detail=not self.diagnostic_detail;self:refresh()
            end},
            {"export","Export diagnostics","action",icon="export",callback=function()self:exportDiagnostic()end},
            {"profile","Profile — import / export","action",icon="file",callback=function()self:profile()end},
        }
        local details=self.diagnostic_detail and self:detailRows()or {}
        local function height(rows)if #rows==0 then return 0 end;local h=24*k;for _,r in ipairs(rows)do h=h+self:rowHeight(r)end;return h+22*k end
        local hero=136*k;local tiles=104*k;local next_h=80*k
        local total=12*k+hero+18*k+tiles+18*k+next_h+22*k+height(disp)+height(tools)+height(details)+90*k
        local view={height=total}
        view.draw=function(bb)
            local y=12*k
            kit:card(bb,p,y,W,hero,{radius=24*k})
            local capacity=a:capacity()
            kit:gauge(bb,p+70*k,y+hero/2,46*k,capacity and capacity/100,capacity and capacity.."%"or "—","battery")
            kit:text(bb,sch.active and "Clock active"or "Clock idle",p+136*k,y+26*k,Kit.size.heading,0,"left",W-150*k,true)
            self:paragraph(bb,a.notice or self.display.notice or "Measurements of the current session.",p+136*k,y+60*k,W-150*k,Kit.size.small,3,Kit.muted)
            y=y+hero+18*k
            -- Counters glide up to their value when the tab opens.
            local gap=12*k;local cw=(W-gap)/2
            local stats={{sch.stats.cycles or 0,"updates"},{sch.stats.recoveries or 0,"recoveries"}}
            self.count=self.count or {t=1}
            for i,st in ipairs(stats)do
                local x=p+(i-1)*(cw+gap)
                local function paint(b,r)
                    kit:card(b,r.x,r.y,r.w,r.h-6*k,{radius=20*k,shadow=false,stroke_color=Kit.line})
                    local value=math.floor(st[1]*Motion.ease.outQuint(self.count.t)+.5)
                    kit:text(b,tostring(value),r.x+r.w/2,r.y+14*k,Kit.size.display,0,"center",r.w-20*k,true)
                    kit:text(b,st[2],r.x+r.w/2,r.y+62*k,Kit.size.small,Kit.muted,"center",r.w-20*k)
                end
                local r=self:region(x,y,cw,tiles,nil,{paint=paint,info=true,counter=i})
                paint(bb,r)
            end
            y=y+tiles+18*k
            kit:card(bb,p,y,W,next_h,{radius=20*k,shadow=false,stroke_color=Kit.line})
            Icon.draw(bb,"clock",p+18*k,y+next_h/2-13*k,26*k,0)
            kit:text(bb,"Next update",p+60*k,y+14*k,Kit.size.small,Kit.muted,"left",W-80*k)
            kit:text(bb,sch.stats.next and os.date("%H:%M:%S",sch.stats.next)or "No alarm scheduled",p+60*k,y+38*k,Kit.size.heading,0,"left",W-80*k,true)
            y=y+next_h+22*k
            local live_y=y+24*k
            y=y+self:group(bb,"Display",disp,p,y,W)+22*k
            for _,r in ipairs(self.cregions)do if r.key=="engine_now"then self.live_region=r end end
            y=y+self:group(bb,"Tools",tools,p,y,W)+22*k
            if #details>0 then
                local dy=y;y=y+self:group(bb,"Technical details",details,p,y,W)+22*k
                if self.diagnostic_detail and self.scroll_details then view.scroll_to=dy;self.scroll_details=nil end
            end
            local _=live_y
        end
        if self.count_tab~=self.tab then
            self.count_tab=self.tab;self.count={t=self:animated()and 0 or 1}
            if self:animated()then
                local tw=Motion.tween(0,1,.9,"linear",Motion.now()+.12)
                self:animate(function(now,instant)
                    if self.tab~="Diagnostic"then return false end
                    self.count.t=instant and 1 or tw:value(now)
                    for _,r in ipairs(self.cregions or {})do if r.counter then self:repaint(r)end end
                    return not(instant or tw:done(now))
                end)
            end
        end
        return view
    end
    function S:exportDiagnostic()
        local ok,e=load("power/report").write(self.app,"diagnostic.json",true)
        self.status=ok and "Diagnostics saved"or tostring(e);self:refresh()
    end
    function S:profile()
        self:input("Path of the JSON profile or old Lua file",self.app.data_dir.."/profile.json",function(path)
            local b=U.read(path,131072)
            if b then local ok,r,message=pcall(function()
                if path:match("%.lua$")then local L=load("core/legacy");return L.convert(L.parse(b),self.draft)end
                return Settings.validate(require("json").decode(b))
            end)
                if ok then self.draft=r;self:markDirty();self.status=message or "Profile imported"else self.status=tostring(r)end
            else local ok,e=U.write(path,require("json").encode(self.draft));self.status=ok and "Profile exported"or tostring(e)end
            self:refresh()
        end)
    end

    -------------------------------------------------------------- legacy v1 editor
    function S:previewAt(bb,x,y,w,h,interactive)
        local r=self.draft.rotation=="follow"and self.app.device.screen:getRotationMode()or tonumber(self.draft.rotation)
        local aspect=r%2==1 and 1024/758 or 758/1024;local rw=math.min(w,h*aspect);local rh=rw/aspect
        x=x+(w-rw)/2;y=y+(h-rh)/2;w=math.floor(rw);h=math.floor(rh)
        if not self.preview then
            self.preview=Scene.new(self.app,self.app:face(self.draft.face),self.draft,w,h)
            local ok,e=pcall(self.preview.render,self.preview,os.time());if not ok then self.status=tostring(e)end
        end
        D.round(bb,x+3*self.k,y+5*self.k,w,h,10*self.k,Kit.shade)
        if self.preview.frame then self.preview:paintTo(bb,x,y)end;D.roundBorder(bb,x-1,y-1,w+2,h+2,8*self.k,0,2)
        self.preview_box={x=x,y=y+self.top-self.scroll:value(),w=w,h=h}
        if interactive then
            self:region(x,y,w,h,function()self.element_selector=true;self:refresh()end)
            for _,v in pairs(self.preview.old)do if names[v.source]and v.type~="progress"and v.type~="rule"then
                local rect=v.rect
                if v.source==self.element then
                    D.roundBorder(bb,x+rect.x-6,y+rect.y-6,rect.w+12,rect.h+12,8,255,4)
                    D.roundBorder(bb,x+rect.x-4,y+rect.y-4,rect.w+8,rect.h+8,6,0,2)
                    D.circle(bb,x+rect.x+rect.w+4,y+rect.y+rect.h+4,6,0)
                end
                self:region(x+rect.x,y+rect.y,rect.w,math.max(rect.h,30*self.k),function()self.element=v.source;self:refresh()end,{element=v.source})
            end end
        end
    end
    function S:elementSheet()
        local opts={};for _,source in ipairs({"time","date","battery","wifi","memory","world"})do opts[#opts+1]={value=source,label=names[source],icon=element_icons[source]}end
        self:choiceSheet("Element to edit",opts,self.element,function(v)self.element=v;self:refresh()end)
        self.sheet.on_close=function()self.element_selector=false end
    end
    function S:legacyComposer()
        local k,kit,w,p=self.k,self.kit,self.w,self.pad;local W=w-2*p;local vh=self.bottom-self.top
        if self.element_selector and not self.sheet then self:elementSheet()end
        if self.section~="Aperçu"then
            local rows=Controls.sections(self.element,self.draft.units)[self.section]
            if self.section=="Lisibilité"then rows={{"ui_scale","Interface size",85,140,5,"%"},{"scale","Face scale",40,150,5,"%"}}end
            local head={{"element","Element: "..names[self.element],"action",icon=element_icons[self.element],callback=function()self.element_selector=true;self:refresh()end,bold=true}}
            local h=12*k;for _,r in ipairs(rows)do h=h+self:rowHeight(r)end
            return {height=12*k+64*k+22*k+24*k+h+120*k,draw=function(bb)
                local y=12*k
                y=y+self:group(bb,nil,head,p,y,W)+22*k
                self:group(bb,Controls.section_names[self.section]or self.section,rows,p,y,W)
            end}
        end
        return {height=vh,draw=function(bb)
            local y=12*k
            local ph=math.min(vh*.52,300*k);local pw=W*.56
            self:previewAt(bb,p,y,pw,ph,true)
            local right=p+pw+16*k;local rw=w-right-p
            kit:text(bb,self.app:face(self.draft.face).name,right,y+6*k,Kit.size.heading,0,"left",rw,true)
            self:paragraph(bb,"Tap an element, then drag it on the preview.",right,y+40*k,rw,Kit.size.small,4,Kit.muted)
            local by=y+ph-108*k
            kit:button(bb,right,by,rw,46*k,names[self.element],{style="secondary",icon=element_icons[self.element],size=Kit.size.small})
            self:region(right,by,rw,46*k,function()self.element_selector=true;self:refresh()end,{radius=23*k})
            kit:button(bb,right,by+56*k,rw,46*k,"Show",{style="primary",icon="play",size=Kit.size.small})
            self:region(right,by+56*k,rw,46*k,function()self:launchClock(self.preview_box)end,{radius=23*k})
            y=y+ph+22*k
            kit:section(bb,"Face settings",p,y,W);y=y+24*k
            local gap=12*k;local cw=(W-2*gap)/3
            local th=math.max(64*k,math.min(96*k,(vh-y-80*k-gap)/2))
            for i,name in ipairs(sections)do
                local x=p+(i-1)%3*(cw+gap);local yy=y+math.floor((i-1)/3)*(th+gap)
                kit:card(bb,x,yy,cw,th,{radius=18*k,shadow=false,stroke_color=Kit.line})
                Icon.draw(bb,symbols[name],x+cw/2-13*k,yy+th/2-28*k,26*k,0)
                kit:text(bb,Controls.section_names[name]or name,x+cw/2,yy+th/2+8*k,Kit.size.small,0,"center",cw-10*k,true)
                self:region(x,yy,cw,th,function()self.section=name;self.page=1;self.scroll:scrollTo(0,false);self:refresh()end,{section=name,radius=18*k})
            end
        end}
    end
    local names_ref=names
    function S:canvasGesture(start,ges)
        if self.tab~="Composer"or self.section~="Aperçu"or not self.preview_box then return false end
        local ok,face=pcall(self.app.face,self.app,self.draft.face)
        if not ok or face.schema_version==2 then return false end
        if not(start.x>=self.preview_box.x and start.x<=self.preview_box.x+self.preview_box.w and start.y>=self.preview_box.y and start.y<=self.preview_box.y+self.preview_box.h)then return false end
        if self.preview then for _,v in pairs(self.preview.old)do
            if names_ref[v.source]and v.type~="progress"and v.type~="rule"then
                local r=v.rect;local bx,by=self.preview_box.x+r.x,self.preview_box.y+r.y
                if start.x>=bx and start.x<=bx+r.w and start.y>=by and start.y<=by+r.h then self.element=v.source;break end
            end
        end end
        local e=self.draft[self.element];self.canvas_drag={box=U.copy(self.preview_box),sx=start.x,sy=start.y,x=e.x,y=e.y}
        return true
    end
    function S:canvasPan(ges,p)
        local d=self.canvas_drag;if not d then return end
        local rel=ges.relative;local dx=rel and rel.x or p.x-d.sx;local dy=rel and rel.y or p.y-d.sy
        local face=self.app:face(self.draft.face)
        local ratio=math.min(d.box.w/face.canvas.width,d.box.h/face.canvas.height)
        local ex=self.draft.units=="percent"and dx/d.box.w*100 or dx/ratio
        local ey=self.draft.units=="percent"and dy/d.box.h*100 or dy/ratio
        self.draft[self.element].x=U.clamp(U.round(d.x+ex),-2000,2000);self.draft[self.element].y=U.clamp(U.round(d.y+ey),-2000,2000)
        self.draft.auto_layout=false;self:markDirty()
        if self.preview then self.preview:free();self.preview=nil end
        self.content_dirty=true;self.frame_dirty=true
    end
    function S:canvasRelease()self.canvas_drag=nil;self:refresh()end
    function S:backView()
        if self.element_selector then self.element_selector=false;self:refresh();return true end
        if self.tab=="Composer"and self.section~="Aperçu"then
            local ok,face=pcall(self.app.face,self.app,self.draft.face)
            if ok and face.schema_version~=2 then self.section="Aperçu";self.page=1;self:refresh();return true end
        end
        return false
    end
end
return M
