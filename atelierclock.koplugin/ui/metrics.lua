-- Physical legibility and viewport layout are separate concerns. Do not infer
-- font size exclusively from the framebuffer resolution.
local M={}
function M.density(screen)
    if screen.getDPI then
        local ok,dpi=pcall(screen.getDPI,screen)
        if ok and type(dpi)=="number" and dpi>=72 and dpi<=800 then return dpi/160,dpi end
    end
    if screen.scaleByDPI then
        local ok,px=pcall(screen.scaleByDPI,screen,160)
        if ok and type(px)=="number" and px>0 then return px/160,px end
    end
    return 1,160
end
function M.ui(screen,w,h,percent)
    local density,dpi=M.density(screen)
    local desired=density*(percent or 100)/100
    -- Reflow at small viewports; avoid zooming an entire fixed page until its
    -- text and targets become tiny. The floor keeps four navigation targets.
    return math.min(desired,w/390,h/460),dpi
end
function M.scene(screen,w,h)
    local sw,sh=screen:getWidth(),screen:getHeight()
    local reduction=math.min(w/sw,h/sh)
    local density=M.density(screen)
    return density*reduction
end
return M
