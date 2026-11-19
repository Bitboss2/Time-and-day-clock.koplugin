local load=...
local U=load("core/util")
local Settings=load("core/settings")
local App={}
function App.new(root,loader)
    local self=setmetatable({root=root,load=loader,metrics={},faces={},errors={},image_lists={},valid_images={}}, {__index=App})
    self.device=require("device");self.ui=require("ui/uimanager")
    local DataStorage=require("datastorage")
    self.data_dir=DataStorage:getSettingsDir().."/atelierclock"
    assert(U.mkdir(self.data_dir.."/cache"));assert(U.mkdir(self.data_dir.."/clocks"))
    self.settings=Settings.new(self.data_dir.."/settings.json")
    self.world=load("core/world").new(root)
    self.scheduler=load("power/scheduler").new{
        ui=self.ui,mgr=self.device.wakeup_mgr,
        minimum_lead=function()
            local base=math.ceil((tonumber(self.device.suspend_wait_timeout)or 1)+(self.settings.data.wake_margin or .3)+3)
            local grace=self.session and self.session.foreign_grace_until
            return math.max(base,grace and math.ceil(grace-os.time()+3)or 0)
        end,
        refresh=function()
            local capacity=self:capacity()
            if capacity and capacity<=self.settings.data.low_battery and self.settings.data.low_battery>0 then
                self.scheduler:stop();self.notice="Low battery: the clock is now static."
                self.paused_warning="battery"
                if self.clock then self.clock:update() end
                return
            end
            self.cycle_capacity=capacity
            if self.session then
                self.metrics.session_seconds=os.time()-self.session.started
                if self.session.capacity_start and capacity then
                    self.metrics.battery_start=self.session.capacity_start;self.metrics.battery_now=capacity
                    self.metrics.battery_drop_points=self.session.capacity_start-capacity
                end
            end
            if self.clock and self.session and not self.session.user_resumed then self.clock:update() end
            self.cycle_capacity=nil
        end,
        sleep=function(token,ok)
            if self.kindle.active then self.kindle:after()else self.kobo:sleep(token,ok)end
        end,
        failed=function(e)
            self.notice=e
            if not self.scheduler.active then
                self.paused_warning="stopped"
                if self.clock and not self.clock.closed then pcall(self.clock.update,self.clock)end
            end
        end,
    }
    self.integration=load("integration/screensaver").new(self)
    self.kobo=load("power/kobo").new(self)
    self.kindle=load("power/kindle").new(self)
    self:scan()
    local C=load("core/collection")
    if #self.settings.data.collection==0 and #self.faces>0 then
        local face=self:face();C.add(self.settings.data,face)
        self.settings:save(self.settings.data)
    end
    self.integration:install();self.kobo:install()
    return self
end
function App:attach(ui) self.context=ui end
function App:scan()
    local R=load("packages/reader");local lfs=require("libs/libkoreader-lfs")
    self.faces={};self.errors={};local ids={}
    for _,folder in ipairs({self.root.."/clocks",self.data_dir.."/clocks"}) do
        local files={}
        for name in lfs.dir(folder) do if name:match("%.clock$") then files[#files+1]=name end end
        table.sort(files)
        for _,name in ipairs(files) do
            local path=folder.."/"..name
            local ok,face=pcall(R.open,path,self.data_dir.."/cache")
            if ok and not ids[face.id] then self.faces[#self.faces+1]=face;ids[face.id]=true
            else self.errors[#self.errors+1]=name.." : "..(ok and "identifier already installed" or tostring(face)) end
        end
    end
    table.sort(self.faces,function(a,b)return (a.order or 100)<(b.order or 100) or (a.order or 100)==(b.order or 100) and a.id<b.id end)
end
function App:face(id)
    for _,f in ipairs(self.faces) do if f.id==(id or self.settings.data.face) then return f end end
    assert(self.faces[1],"No valid .clock face. Reinstall the complete plugin.")
    return self.faces[1]
end
function App:readingSnapshot()
    local result={};local ui=self.context
    if ui and ui.doc_settings and ui.doc_settings.readSetting then
        local ok=pcall(function()
            local props=ui.doc_settings:readSetting("doc_props")
            if type(props)=="table"and type(props.title)=="string"then result.title=props.title:sub(1,200)end
            local percent=ui.doc_settings:readSetting("percent_finished")
            if type(percent)=="number"and percent>=0 and percent<=1 then result.percent=percent end
        end)
    end
    return result
end
function App:capacity()
    local p=self.device:getPowerDevice()
    local ok,v=pcall(function()return p:getCapacity() end)
    return ok and type(v)=="number" and v>=0 and v<=100 and math.floor(v) or nil
end
function App:content(sleep)
    return load("ui/clock"):new{app=self,sleep=sleep}
end
function App:stop(reason)
    self.scheduler:stop(reason)
    if self.kindle then self.kindle:stop()end
    if self.session then
        self.kobo:endSession()
        local capacity=self:capacity()
        self.metrics.session_seconds=math.max(0,os.time()-self.session.started)
        if capacity and self.session.capacity_start then
            self.metrics.battery_start=self.session.capacity_start;self.metrics.battery_now=capacity
            self.metrics.battery_drop_points=self.session.capacity_start-capacity
        end
        self.session.user_resumed=true
        self.last_session={started=self.session.started,ended=os.time(),end_reason=reason or "session ended"}
        local saved,err=load("power/report").write(self,"last-session.json",false,reason or "session ended")
        if not saved then self.notice="Session diagnostics not saved: "..tostring(err)end
        local rotation=self.session.rotation
        self.session=nil
        if rotation~=nil then self.device.screen:setRotationMode(rotation) end
    end
end
function App:resume()
    -- Hardware RTC processing does not broadcast a user Resume in Kobo's normal
    -- suspend path. A Resume event is treated as explicit user ownership.
    if self.session then self.session.user_resumed=true end
    self:stop("user wake-up")
end
function App:open()
    if self.editor and not self.editor.closed then self.ui:close(self.editor) end
    self.editor=load("ui/studio"):new{app=self}
    self.ui:show(self.editor)
end
function App:restoreManual()
    local m=self.manual;if not m then return end;self.manual=nil
    self.device.screen:setRotationMode(m.rotation)
    if m.brightness~=nil then
        local p=self.device:getPowerDevice()
        if p and p.setIntensity then p:setIntensity(m.brightness) end
        if m.light_on==false and p and p.turnOffFrontlight then p:turnOffFrontlight() end
    end
end
function App:launch()
    self.paused_warning=nil
    local s=self.settings.data;local screen=self.device.screen;local p=self.device:getPowerDevice()
    if self.manual_clock and not self.manual_clock.closed then self.ui:close(self.manual_clock) end
    self.manual={rotation=screen:getRotationMode(),brightness=p and p.fl_intensity,light_on=p and p.isFrontlightOn and p:isFrontlightOn()}
    if s.rotation~="follow" then screen:setRotationMode(tonumber(s.rotation)) end
    if s.brightness>=0 and p then
        if s.brightness==0 and p.turnOffFrontlight then p:turnOffFrontlight()
        elseif p.setIntensity then p:setIntensity(s.brightness) end
    end
    self.manual_clock=self:content(false);self.ui:show(self.manual_clock)
end
function App:backgroundImage(s,landscape,now)
    if not s.image_enabled then return nil end
    local suffix=landscape and "landscape" or "portrait"
    if s.image_mode=="single" then
        local p=s["image_"..suffix];return p~="" and self:validImage(p) or nil
    end
    local folder=s["folder_"..suffix];if folder=="" then return nil end
    local list=self.image_lists[folder]
    if not list then
        list={};local lfs=require("libs/libkoreader-lfs")
        local ok=pcall(function()for name in lfs.dir(folder) do if name:lower():match("%.png$") then list[#list+1]=folder.."/"..name end end end)
        if not ok then self.notice="Image folder not accessible." end
        table.sort(list);self.image_lists[folder]=list
    end
    if #list==0 then return nil end
    return self:validImage(list[math.floor((now or os.time())/(s.image_interval*60))%#list+1])
end
function App:validImage(path)
    if self.valid_images[path]~=nil then return self.valid_images[path] and path or nil end
    local f=io.open(path,"rb")
    if not f then self.valid_images[path]=false;self.notice="Image not found: "..path;return nil end
    local size=f:seek("end");f:seek("set",0);local b=f:read(24);f:close()
    local ok=false
    if size and size<=16*1024*1024 and b and #b==24 and b:sub(1,8)=="\137PNG\13\10\26\10" then
        local function be(i)local a,c,d,e=b:byte(i,i+3);return ((a*256+c)*256+d)*256+e end
        local w,h=be(17),be(21);ok=w>0 and h>0 and w*h<=4000000
    end
    self.valid_images[path]=ok
    if not ok then self.notice="Invalid or too large PNG image: "..path end
    return ok and path or nil
end
function App:import(path)
    if type(path)~="string" or not path:match("%.clock$") then return nil,"Choose a .clock file" end
    local R=load("packages/reader")
    local ok,f=pcall(R.open,path,self.data_dir.."/cache")
    if not ok then return nil,tostring(f) end
    for _,face in ipairs(self.faces) do if face.id==f.id then return nil,"This face is already installed: "..f.id end end
    local bytes=U.read(path,16*1024*1024);if not bytes then return nil,"File not accessible" end
    local dest=self.data_dir.."/clocks/"..f.id..".clock"
    local written,e=U.write(dest..".tmp",bytes);if not written then return nil,e end
    local renamed,re=os.rename(dest..".tmp",dest);if not renamed then return nil,re end
    f.path=dest;self.faces[#self.faces+1]=f;return f
end
return App
