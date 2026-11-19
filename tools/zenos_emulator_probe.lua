-- Late user patch (koreader/patches/2-atelier-probe.lua) for the official KOReader
-- Linux SDL build, optionally with ZenOS in plugins/zenos.koplugin. It opens the
-- studio, sends real Gesture events through UIManager over the whole screen and
-- logs the window stack (flags [M]odal [T]oast [F]ullscreen), whether the studio
-- was closed (with the caller traceback) and whether a book was opened.
-- Run: HOME=<isolated> KO_MULTIUSER=1 SDL_VIDEO_DRIVER=dummy EMULATE_READER_W=758
--      EMULATE_READER_H=1024 EMULATE_READER_DPI=212 ATELIER_OUT=<dir> ./reader.lua <books>
local UI=require("ui/uimanager");local Event=require("ui/event");local Geom=require("ui/geometry")
local Device=require("device");local time=require("ui/time")
local out=os.getenv("ATELIER_OUT")
local function log(...)local t={};for i=1,select("#",...)do t[#t+1]=tostring((select(i,...)))end;local f=io.open(out.."/probe.log","a");f:write(table.concat(t," "),"\n");f:close()end
local function stack()
    local t={};for i,w in ipairs(UI._window_stack)do local x=w.widget;t[#t+1]=(x.name or x.id or "?")..(x.modal and "[M]" or "")..(x.toast and "[T]" or "")..(x.covers_fullscreen and "[F]" or "")end
    return table.concat(t," > ")
end
local function ges(kind,x,y,extra)
    local g={ges=kind,pos=Geom:new{x=x,y=y,w=0,h=0},time=time.now()}
    for k,v in pairs(extra or {})do g[k]=v end
    local ok,err=pcall(UI.sendEvent,UI,Event:new("Gesture",g))
    if not ok then log("  sendEvent error",kind,err)end
end
local step=0
local function run()
    local app=assert(package.loaded["atelierclock.service"],"service missing")
    local ReaderUI=require("apps/reader/readerui")
    log("before open:",stack())
    app:open();UI:forceRePaint()
    local st=app.editor
    st.name="atelier_studio"
    local orig=st.onCloseWidget
    st.onCloseWidget=function(self,...)log("STUDIO CLOSED BY:\n"..debug.traceback());return orig(self,...)end
    log("after open:",stack())
    local points={}; for y=120,1000,80 do for x=60,700,160 do points[#points+1]={x,y} end end
    local before_tab=nil
    for _,p in ipairs(points)do
        if st.sheet then st:closeSheet(true) end
        if p[2]<92 and p[1]>650 then goto continue end
        if st.closed then break end
        ges("touch",p[1],p[2]);ges("tap",p[1],p[2]);UI:forceRePaint()
        log("tap",p[1],p[2],"->",stack(),"tab=",st.tab,"closed=",tostring(st.closed),"reader=",tostring(ReaderUI.instance~=nil))
        ::continue::
    end
    if not st.closed then
        ges("touch",379,600);ges("pan",379,400,{start_pos=Geom:new{x=379,y=600,w=0,h=0},relative={x=0,y=-200}});ges("pan_release",379,400);UI:forceRePaint()
        log("pan ->",stack(),"closed=",tostring(st.closed),"reader=",tostring(ReaderUI.instance~=nil))
        ges("touch",600,500);ges("swipe",600,500,{direction="west",distance=300,end_pos=Geom:new{x=300,y=500,w=0,h=0}});UI:forceRePaint()
        log("swipe ->",stack(),"closed=",tostring(st.closed),"reader=",tostring(ReaderUI.instance~=nil))
        ges("touch",379,500);ges("hold",379,500);ges("hold_release",379,500);UI:forceRePaint()
        log("hold ->",stack(),"closed=",tostring(st.closed),"reader=",tostring(ReaderUI.instance~=nil))
    end
    Device.screen.bb:writePNG(out.."/screen.png")
end
UI:scheduleIn(6,function()
    local ok,err=xpcall(run,debug.traceback)
    if not ok then log("ERROR",err)end
    UI:scheduleIn(1,function()log("final:",stack());UI:quit()end)
end)
