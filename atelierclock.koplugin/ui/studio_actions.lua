local load=...
local U=load("core/util")
local Input=require("ui/widget/container/inputcontainer")
local Studio=Input:extend{}
local DISPLAY={display_engine=true,display_fps=true,display_rest=true,motion=true}
function Studio:change(key,value,soft)
    U.set(self.draft,key,value);self:markDirty()
    if soft then self.frame_dirty=true;self:request()else self:refresh()end
end
function Studio:markDirty()
    if not self.dirty then self.dirty=true;self.layers.draft=nil end
    self.draft_spring:set(1);if not self:animated()then self.draft_spring:jump(1)end
end
function Studio:clearDirty()
    self.dirty=false;self.draft_spring:set(0);if not self:animated()then self.draft_spring:jump(0)end
end
-- Text entry is the one place where KOReader takes the screen back: the
-- fluid worker is stopped and the waveform restored first, then resumed.
function Studio:input(title,value,callback)
    local Dialog=require("ui/widget/inputdialog")
    local function show()
        local dialog
        local function done()
            self.app.ui:close(dialog)
            self.resume_action=self.resume_action or function()if not self.closed then self.display:resume()end end
            self.app.ui:unschedule(self.resume_action);self.app.ui:scheduleIn(.35,self.resume_action)
        end
        dialog=Dialog:new{
            title=title,input=tostring(value or ""),
            buttons={{
                {text="Annuler",id="close",callback=function()done()end},
                {text="Valider",is_enter_default=true,callback=function()
                    local v=dialog:getInputText();done();callback(v)
                end},
            }},
        }
        self.app.ui:show(dialog);dialog:onShowKeyboard()
    end
    if self.display and self.display.backend then
        self.display:release(function()self.frame_dirty=true;self.app.ui:setDirty(self,"full");show()end,true)
    else show()end
end
function Studio:confirm(title,callback,ok_text)
    self:confirmSheet(title,"",ok_text or "Activer",callback)
end
function Studio:apply()
    local before=U.copy(self.app.settings.data)
    local ok,e=self.app.settings:save(self.draft)
    self.status=ok and "Réglages enregistrés" or tostring(e)
    if ok then
        self.draft=U.copy(self.app.settings.data);self:clearDirty();self.app.image_lists={};self.app.valid_images={}
        self:layout()
        local engine=false
        for key in pairs(DISPLAY)do if before[key]~=self.draft[key]and key~="motion"and key~="display_rest"then engine=true end end
        if engine and self.display then
            self.display:release(function()
                if self.closed then return end
                self.display:select();self.display:start();self.frame_dirty=true;self.app.ui:setDirty(self,"full")
            end)
        end
    end
    self:refresh();return ok
end
function Studio:leave()
    local function close()
        if self.closed then return end
        self.display:close(function()self.app.ui:close(self,"full")end)
    end
    if self.dirty then
        self:confirmSheet("Abandonner le brouillon ?","Les modifications non appliquées seront perdues.","Abandonner",close,true)
    else close()end
end
function Studio:free() self:onCloseWidget() end
return Studio
