local load=...
local U=load("core/util")
local R={}
function R.make(a,include_kernel,reason)
    local screen=a.device.screen
    return {version=load("core/version"),model=a.device.model,dpi=screen:getDPI(),
        resolution={screen:getWidth(),screen:getHeight()},settings=a.settings.data,
        rtc=a.scheduler.stats,metrics=a.metrics,errors=a.errors,notice=a.notice,unexpected_wakeups=a.device.unexpected_wakeup_count,
        last_suspend_time_s=load("power/measure").seconds(a.device.last_suspend_time),
        power=a.kobo:diagnostic(include_kernel),time=os.date("%Y-%m-%dT%H:%M:%S%z"),
        session=a.session and {started=a.session.started,ended=os.time(),end_reason=reason}or a.last_session,
        autonomy="not measured",fast_supported=a.kobo.supported,
        rtc_capability=load("power/capabilities").detect(a.device),kindle_recoveries=a.kindle and a.kindle.recoveries or 0,
        display=a.display_info,
        energy_target={factor=7,reference_version="0.2.0-beta.3",reference_drop_points=7,reference_minutes=337,
            maximum_points_per_hour=60/337,hardware_verified=false,area_factor_is_not_energy_factor=true}}
end
function R.write(a,name,include_kernel,reason)
    assert(name=="diagnostic.json"or name=="last-session.json")
    local good,result,err=pcall(function()
        local path=a.data_dir.."/"..name
        local bytes=require("json").encode(R.make(a,include_kernel,reason))
        local written,err=U.write(path..".tmp",bytes);if not written then return nil,err end
        return os.rename(path..".tmp",path)
    end)
    if not good then return nil,tostring(result)end
    return result,err
end
return R
