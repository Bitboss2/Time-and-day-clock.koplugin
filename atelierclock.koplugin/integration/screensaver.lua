local I={}
I.mode="atelierclock"
function I.new(app) return setmetatable({app=app}, {__index=I}) end
function I:menu(items)
    local root=items.screensaver and items.screensaver.sub_item_table
    if type(root)~="table" then return false end
    local function find(t)
        local count=0
        for _,v in ipairs(t) do
            if v.atelierclock_option then return t end
            if v.radio and v.callback and v.checked_func then count=count+1 end
        end
        if count>=3 then return t end
        for _,v in ipairs(t) do if type(v.sub_item_table)=="table" then local found=find(v.sub_item_table);if found then return found end end end
    end
    local target=find(root)
    if not target then self.app.notice="Structure du menu de veille non reconnue.";return false end
    for _,v in ipairs(target) do if v.atelierclock_option then return true end end
    table.insert(target,1,{
        atelierclock_option=true,text="Horloge Atelier",radio=true,
        checked_func=function() return G_reader_settings:readSetting("screensaver_type")==I.mode end,
        callback=function() self:select() end,
    })
    self.menu_ok=true;return true
end
function I:select()
    local prev=G_reader_settings:readSetting("screensaver_type","disable")
    if prev~=I.mode then G_reader_settings:saveSetting("atelierclock_previous_screensaver",prev) end
    G_reader_settings:saveSetting("screensaver_type",I.mode)
end
function I:disable()
    self.app:stop()
    if G_reader_settings:readSetting("screensaver_type")==I.mode then
        local prev=G_reader_settings:readSetting("atelierclock_previous_screensaver","disable")
        G_reader_settings:saveSetting("screensaver_type",prev~=I.mode and prev or "disable")
    end
end
function I:install()
    local ss=require("ui/screensaver");self.ss=ss
    if self.wrapper then return end
    local original=ss.show;self.original=original
    local app=self.app
    self.wrapper=function(screensaver)
        local chosen=screensaver.screensaver_type or G_reader_settings:readSetting("screensaver_type")
        if chosen~=I.mode then return original(screensaver) end
        -- Keep poweroff/reboot presentation under KOReader's control.
        if screensaver.prefix and screensaver.prefix~="" then
            screensaver.screensaver_type="disable";return original(screensaver)
        end
        local ok,err=pcall(function()
            if not screensaver.ui then return end
            if screensaver.screensaver_lock_widget then
                app.ui:close(screensaver.screensaver_lock_widget);screensaver.screensaver_lock_widget=nil
            end
            if screensaver.screensaver_widget then
                app.ui:close(screensaver.screensaver_widget);screensaver.screensaver_widget=nil
            end
            app:stop()
            app.metrics={}
            app.last_session=nil
            app.paused_warning=nil
            screensaver.screensaver_type=I.mode
            local screen=app.device.screen
            local rotation=screen:getRotationMode()
            local original_dimensions={w=screen:getWidth(),h=screen:getHeight()}
            local s=app.settings.data
            if s.rotation~="follow" then screen:setRotationMode(tonumber(s.rotation)) end
            app.session={rotation=rotation,started=os.time(),user_resumed=false,capacity_start=app:capacity()}
            app.kobo:beginSession()
            app.device.orig_rotation_mode=rotation
            app.device.screen_saver_mode=true
            local content=app:content(true)
            local Wrapper=require("ui/widget/screensaverwidget")
            local host=Wrapper:new{widget=content,covers_fullscreen=true}
            host.modal=true;host.dithered=true
            local close=host.onCloseWidget
            host.onCloseWidget=function(w,...)
                app:stop()
                return close(w,...)
            end
            screensaver.screensaver_widget=host
            app.host=host;app.clock=content
            app.ui:setIgnoreTouchInput(false)
            if app.device:isTouchDevice() and G_reader_settings:readSetting("screensaver_delay")=="gesture" then
                local Lock=require("ui/widget/screensaverlockwidget")
                screensaver.screensaver_lock_widget=Lock:new{ui=screensaver.ui,orig_dimen=screen:getRotationMode()~=rotation and original_dimensions or nil}
            end
            app.ui:show(host,"full")
            if screensaver.screensaver_lock_widget then app.ui:show(screensaver.screensaver_lock_widget) end
            local capacity=app:capacity()
            if capacity and s.low_battery>0 and capacity<=s.low_battery then
                app.notice="Batterie basse : aucun réveil programmé."
                app.paused_warning="BATTERIE BASSE / HEURE FIGÉE";content:update()
            else
                local armed,e=app.scheduler:start(s)
                if not armed then app.notice=e;app.paused_warning="RTC INDISPONIBLE / HEURE FIGÉE";content:update()
                elseif app.kindle then app.kindle:after() end
            end
        end)
        if not ok then
            app.notice="Échec de l'écran de veille : "..tostring(err)
            app:stop()
            if screensaver.screensaver_widget then app.ui:close(screensaver.screensaver_widget);screensaver.screensaver_widget=nil end
            screensaver.screensaver_type="disable"
            return original(screensaver)
        end
    end
    ss.show=self.wrapper
end
return I
