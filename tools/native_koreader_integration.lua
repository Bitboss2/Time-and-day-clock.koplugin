-- Late user patch for an isolated official KOReader SDL installation.
-- Uses real KOReader widgets, fonts, archive reader, BB and UIManager.
-- SDL/QEMU does not emulate Kobo RTC, EPDC, PMIC or suspend-to-RAM.
local UI=require("ui/uimanager")
local Device=require("device")
local Data=require("datastorage")
local out=assert(os.getenv("ATELIER_TEST_OUTPUT"))
local records={}
local function capture(name)
    UI:forceRePaint()
    assert(Device.screen.bb:writePNG(out.."/"..name..".png")~=false)
end
local function run()
    local app=assert(package.loaded["atelierclock.service"],"plugin service was not loaded by FileManager")
    local version=assert(app.load("core/version"))
    assert(version=="0.2.5-beta.9","wrong plugin build")
    assert(#app.faces==10 and #app.errors==0,"bundled clocks failed native extraction")
    assert(Device.screen:getWidth()==758 and Device.screen:getHeight()==1024)
    assert(Device.screen:getDPI()==212,"wrong test DPI")
    records[#records+1]={check="native_plugin_loading",clocks=#app.faces,arch=jit.arch,dpi=Device.screen:getDPI()}
    print("ATELIER_NATIVE: plugin loaded; ten clocks; arch="..jit.arch)
    app:open();capture("gallery")
    local st=app.editor
    st.tab="Composer";st.edit_mode="complications";st:refresh();capture("editor")
    local slot
    for _,r in ipairs(st.regions)do if r.slot_id then slot=r;break end end
    assert(slot,"native editor produced no complication targets")
    st:onTap(nil,{pos={x=slot.x+slot.w/2,y=slot.y+slot.h/2}})
    assert(st.slot_picker,"native complication tap was not dispatched")
    capture("complications")
    st.slot_picker=nil;st.tab="Veille";st:refresh();capture("power")
    st.tab="Diagnostic";st:refresh();capture("diagnostic")
    st:exportDiagnostic()
    local diagnostic=assert(io.open(Data:getSettingsDir().."/atelierclock/diagnostic.json","rb"),"diagnostic export missing")
    local exported=require("json").decode(diagnostic:read("*a"));diagnostic:close()
    assert(exported.version==version and exported.power.kernel_current.reason=="not_kobo")
    records[#records+1]={check="studio_navigation_complications_export",status="passed"}
    UI:close(st)
    local real_time=os.time
    for _,face in ipairs(app.faces)do
        app.settings.data.face=face.id
        local clock=app:content(true)
        UI:show(clock,"full")
        capture("face-"..face.id)
        local at=real_time();local before=clock.scene.draws
        os.time=function(t)if t then return real_time(t)end;return at+60 end
        local good,err=pcall(clock.update,clock)
        os.time=real_time
        assert(good,err);UI:forceRePaint()
        assert(clock.scene.draws>before,"no native minute update for "..face.id)
        records[#records+1]={check="native_face_minute",face=face.id,status="passed",cpu_ms=app.metrics.render_ms}
        UI:close(clock)
        print("ATELIER_NATIVE: rendered "..face.id)
    end
    Device.screen:setRotationMode(1)
    app:open();capture("gallery-landscape");UI:close(app.editor)
    Device.screen:setRotationMode(0)
    records[#records+1]={check="landscape_studio",status="passed"}
    local f=assert(io.open(out.."/result.json","wb"))
    f:write(require("json").encode({status="passed",runtime="official KOReader v2026.07.1 SDL3",
        architecture=jit.arch,processor=os.getenv("ATELIER_TEST_CPU")or "host",screen={758,1024,212},
        plugin_version=version,checks=records,kobo_hardware_emulated=false,energy_validated=false}));f:close()
    print("ATELIER_NATIVE: ALL PASSED")
    UI:quit()
end
UI:scheduleIn(1,function()
    local good,err=xpcall(run,debug.traceback)
    if not good then
        local f=assert(io.open(out.."/error.txt","wb"));f:write(err);f:close()
        print("ATELIER_NATIVE: FAILED\n"..err)
        UI:quit(1)
    end
end)
