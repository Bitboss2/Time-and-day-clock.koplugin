local load=...
local Scene=load("render/scene")
local Input=require("ui/widget/container/inputcontainer")
local Geom=require("ui/geometry")
local GestureRange=require("ui/gesturerange")
local Clock=Input:extend{covers_fullscreen=true}
function Clock:init()
    local screen=self.app.device.screen
    self.dimen=Geom:new{x=0,y=0,w=screen:getWidth(),h=screen:getHeight()}
    self.scene=Scene.new(self.app,self.app:face(),self.app.settings.data,self.dimen.w,self.dimen.h)
    self.scene:render()
    if not self.sleep then
        self.ges_events.Tap={GestureRange:new{ges="tap",range=self.dimen}}
        self.ges_events.Hold={GestureRange:new{ges="hold",range=self.dimen}}
        if self.app.device:hasKeys() then self.key_events.Close={{self.app.device.input.group.Any}} end
        self.timer=function()
            if self.closed then return end
            self:update();self.app.ui:scheduleIn(60-os.time()%60,self.timer)
        end
        self.app.ui:scheduleIn(60-os.time()%60,self.timer)
    end
end
function Clock:getSize() return self.dimen end
function Clock:paintTo(bb,x,y) self.scene:paintTo(bb,x,y) end
function Clock:update()
    local start=os.clock();local rect=self.scene:render(os.time())
    local elapsed=(os.clock()-start)*1000
    self.app.metrics.render_ms=math.floor(elapsed+0.5)
    self.app.metrics.render_total_ms=(self.app.metrics.render_total_ms or 0)+elapsed
    self.app.metrics.last=os.time()
    self.app.metrics.delta_scanned_pixels=self.scene.delta_scanned_pixels
    self.app.metrics.delta_fallbacks=self.scene.delta_fallbacks
    self.app.metrics.delta_skipped=self.scene.delta_skipped
    if rect and rect.w>0 and rect.h>0 then
        local full=false;local interval=self.app.settings.data.full_refresh
        if interval>0 and os.time()-(self.last_full or self.app.session and self.app.session.started or 0)>=interval*60 then full=true end
        if self.scene.image~=self.last_image and self.last_image and self.app.settings.data.image_full_refresh then full=true end
        self.last_image=self.scene.image
        if full then self.last_full=os.time() end
        local regions=self.scene.regions or {rect}
        -- Limit controller submissions; merging a large number of tiny windows
        -- may cost more than one bounding rectangle on older EPDCs.
        if #regions>4 then regions={rect}end
        local area=0
        if full then
            self.app.ui:setDirty(self.app.host or self,"full");area=self.dimen.w*self.dimen.h
        else for _,r in ipairs(regions)do if r.w>0 and r.h>0 then
            self.app.ui:setDirty(self.app.host or self,self.sleep and "ui"or "partial",Geom:new(r));area=area+r.w*r.h
        end end end
        self.app.metrics.refresh_percent=math.floor(area/(self.dimen.w*self.dimen.h)*1000+.5)/10
        if self.scene.coarse_regions and not full then
            local coarse=load("render/delta").area(self.scene.coarse_regions)
            self.app.metrics.coarse_refresh_percent=coarse/(self.dimen.w*self.dimen.h)*100
            self.app.metrics.requested_area_factor=area>0 and coarse/area or nil
        else
            self.app.metrics.coarse_refresh_percent=nil;self.app.metrics.requested_area_factor=nil
        end
        self.app.metrics.tiles_drawn=self.scene.draws
        self.app.metrics.refreshes=(self.app.metrics.refreshes or 0)+1
    end
end
function Clock:onClose()
    if self.sleep then return end
    self.app.ui:close(self);return true
end
Clock.onTap=Clock.onClose
function Clock:onHold()
    self.app.ui:close(self);self.app:open();return true
end
function Clock:onSuspend()
    if not self.sleep then self.app.ui:close(self) end
end
function Clock:onCloseWidget()
    if self.closed then return end
    self.closed=true
    if self.timer then self.app.ui:unschedule(self.timer) end
    self.scene:free()
    if not self.sleep then self.app:restoreManual() end
end
function Clock:free() self:onCloseWidget() end
return Clock
