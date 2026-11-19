-- Observe the native RTC write result without programming the same alarm twice.
-- WakeupMgr:addTask/removeTasks discard that result. Hooks are scoped to one
-- synchronous operation and restored even when a driver call throws.
local A={}
local function change(mgr,fn)
    local original=mgr.setWakeupAlarm
    if type(original)~="function"then return pcall(fn)end
    local old=(mgr._task_queue or {})[1];local epoch,result
    local wrapper=function(device,at,...)
        local value=original(device,at,...);epoch=at;result=value;return value
    end
    mgr.setWakeupAlarm=wrapper
    local good,err=pcall(fn)
    if mgr.setWakeupAlarm==wrapper then mgr.setWakeupAlarm=original end
    if not good then return nil,tostring(err)end
    local first=(mgr._task_queue or {})[1]
    if first then
        if epoch==first.epoch then
            if not result then return nil,"le pilote RTC a refusé l'alarme"end
        elseif not old or old.epoch~=first.epoch then
            -- Compatibility with managers which bypass setWakeupAlarm.
            local ok,value=pcall(mgr.setWakeupAlarm,mgr,first.epoch)
            if not ok or not value then return nil,"le pilote RTC a refusé l'alarme"end
        end
    end
    return true
end
function A.add(mgr,seconds,callback)
    return change(mgr,function()mgr:addTask(seconds,callback)end)
end
function A.remove(mgr,callback)
    return change(mgr,function()mgr:removeTasks(nil,callback)end)
end
return A
