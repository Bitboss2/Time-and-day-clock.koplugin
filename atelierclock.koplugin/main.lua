-- Independent implementation. No global package.path or dofile replacement.
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$")
local loaded = {}
local function load(name)
    if not loaded[name] then
        local chunk = assert(loadfile(root .. "/" .. name .. ".lua"))
        loaded[name] = chunk(load)
    end
    return loaded[name]
end
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Plugin = WidgetContainer:extend{ name = "atelierclock", is_doc_only = false }

function Plugin:init()
    local App = load("app")
    -- Plugins are instantiated separately in ReaderUI and FileManager. The service
    -- owns resources across those instances; UI registration belongs to each one.
    local service = package.loaded["atelierclock.service"]
    if not service then
        service = App.new(root, load)
        package.loaded["atelierclock.service"] = service
    end
    self.app = service
    self.ui.menu:registerToMainMenu(self)
    self.app:attach(self.ui)
    self:onDispatcherRegisterActions()
end

function Plugin:addToMainMenu(items)
    items.atelierclock = {
        text = "Atelier Clock", sorting_hint = "more_tools",
        callback = function() self.app:open() end,
    }
    self.app.integration:menu(items)
end

function Plugin:onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("atelierclock_open", {
        category = "none", event = "AtelierClockOpen", title = "Atelier Clock : atelier", general = true,
    })
    Dispatcher:registerAction("atelierclock_launch", {
        category = "none", event = "AtelierClockLaunch", title = "Atelier Clock : afficher", general = true,
    })
end
function Plugin:onAtelierClockOpen() self.app:open(); return true end
function Plugin:onAtelierClockLaunch() self.app:launch(); return true end
function Plugin:onResume() self.app:resume() end
function Plugin:onOutOfScreenSaver() self.app:stop() end
function Plugin:onCloseDocument() self.app:stop() end
function Plugin:onUnexpectedWakeupLimit()
    self.app:stop("limite de réveils KOReader")
    self.app.notice="KOReader signale des échecs de suspension : réveils de l'horloge désactivés pour cette session."
end
function Plugin:onClose() self.app:stop() end
return Plugin
