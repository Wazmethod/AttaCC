-- AttaCC SDK v1.1 preview: declarative app state and controls.
-- No CraftOS event loop, remote action authentication or rendering is hidden.
local runtime = require("lib.runtime")
local bus = require("lib.bus")
local webcap = require("lib.webcap")
local M = {}

local function validId(value)
    return type(value) == "string" and value:match("^[%w_%-]+$") ~= nil
end

function M.app(id, options)
    if not validId(id) then error("AttaCC app id must be letters, numbers, _ or -", 2) end
    options = options or {}
    local app = {
        id = id, title = options.title or id, dataItems = {}, dataOrder = {},
        controls = {}, controlOrder = {}, views = {}, viewOrder = {}, listeners = {}
    }

    -- Single public entry point for apps: framework services stay behind this facade.
    function app:config(path, fallback)
        local facade=require("lib.sdk_facade")
        if type(path)=="table" then return facade.configure(self,path) end
        return facade.value(self,path,fallback)
    end
    function app:state(key, value)
        local store=require("lib.sdk_state")
        if value==nil then return store.read(self.id,key) end
        return store.write(self.id,key,value)
    end
    function app:requirements(items)
        return require("lib.sdk_facade").requirements(self,items)
    end
    function app:device(role)
        return require("lib.sdk_facade").device(self,role)
    end
    function app:output(role)
        local device,err=self:device(role)
        if not device then return nil,err end
        local declaration=self.hardware[role]
        if declaration.direction=="input" then return nil,"input-only role" end
        return {set=function(_,value,fallback) return device:write(value,fallback) end,
            get=function(_,fallback) return device:read(fallback) end,
            available=function() return device:available() end}
    end
    function app:require(name)
        return require("lib.sdk_facade").dependency(self,name)
    end
    function app:checkDependencies()
        return require("lib.sdk_facade").checkDependencies(self)
    end
    function app:lifecycle(options)
        if type(options)~="table" then error("lifecycle options must be a table",2) end
        self.lifecycleOptions=options
        return self
    end
    -- Network snapshot subscriptions are dispatched by the SDK host.
    -- Application code never needs to open modem channels or pull events.
    -- SDK-native named network events: apps never manage modem channels.
    -- Public SDK control-plane APIs. Hardware networking stays in sdk_host.
    function app:webCommand(request,callback)
        if not self.webCommandGate then return false,"SDK Web commands unavailable" end
        return self.webCommandGate:execute(request,callback)
    end
    function app:webSend(message)
        if not self.webTransport then return false,"SDK WebSocket unavailable" end
        return self.webTransport:send(message)
    end
    function app:onWebMessage(callback)
        if type(callback)~="function" then error("Web message handler required",2) end
        self.webListeners=self.webListeners or {}
        table.insert(self.webListeners,callback)
        return self
    end
    function app:receiveWebMessage(message)
        if type(message)~="table" then return false,"invalid Web message" end
        for _,callback in ipairs(self.webListeners or {}) do
            local ok,err=pcall(callback,message)
            if not ok then self:log("error","Web message: "..tostring(err)) end
        end
        return true
    end
    function app:webStatus()
        if not self.webTransport then return "inactive","SDK WebSocket unavailable" end
        return self.webTransport.state,self.webTransport.error
    end
    function app:deferAfterAck(callback)
        if type(callback)~="function" then return false,"callback required" end
        if not self._sdkExecutingRemote then return false,"not a remote command" end
        self._sdkAfterAck=self._sdkAfterAck or {}
        table.insert(self._sdkAfterAck,callback)
        return true
    end
    function app:storageRequest(target,action,namespace,key,value,callback)
        return require("lib.sdk_storage").request(self,target,action,namespace,key,value,callback)
    end
    function app:remoteCommand(machine,appId,control,args,callback)
        if not self.remoteClient then return false,"SDK remote client unavailable" end
        return self.remoteClient:request(machine,appId,control,args,callback)
    end
    function app:nodes()
        if not self.nodeDiscovery then return {} end
        return self.nodeDiscovery:list()
    end
    function app:node(key)
        if not self.nodeDiscovery then return nil end
        return self.nodeDiscovery:get(key)
    end
    function app:onNetwork(topic,callback)
        if type(topic)~="string" or (topic~="*" and not topic:match("^[%w_.%-]+$"))
            or type(callback)~="function" then error("invalid network subscription",2) end
        self.networkSubscriptions=self.networkSubscriptions or {}
        self.networkSubscriptions[topic]=self.networkSubscriptions[topic] or {}
        table.insert(self.networkSubscriptions[topic],callback)
        return self
    end
    function app:publishNetwork(topic,payload)
        if not self.networkTransport then return false,"SDK network unavailable" end
        return self.networkTransport:publishEvent(topic,payload)
    end
    function app:receiveNetwork(frame)
        if type(frame)~="table" or frame.type~="attacc.sdk.event.v1"
            or type(frame.topic)~="string" then return false,"invalid event" end
        for _,topic in ipairs({frame.topic,"*"}) do
            for _,callback in ipairs((self.networkSubscriptions or {})[topic] or {}) do
                local ok,err=pcall(callback,frame.payload,frame)
                if not ok then self:log("error","network listener: "..tostring(err)) end
            end
        end
        return true
    end
    function app:onSnapshot(callback)
        if type(callback)~="function" then error("snapshot callback required",2) end
        self.snapshotListeners=self.snapshotListeners or {}
        self.snapshotListeners[#self.snapshotListeners+1]=callback
        return self
    end
    function app:receiveSnapshot(frame)
        if type(frame)~="table" or frame.type~="attacc.sdk.snapshot.v1"
            or type(frame.descriptor)~="table"
            or frame.descriptor.schema~="attacc.sdk.app.v1"
            or type(frame.machine)~="string" or type(frame.network)~="string" then
            return false,"invalid snapshot"
        end
        for _,callback in ipairs(self.snapshotListeners or {}) do
            local ok,err=pcall(callback,frame)
            if not ok then self:log("error","snapshot listener: "..tostring(err)) end
        end
        return true
    end
    function app:run(options)
        return require("lib.sdk_host").run(self,options or self.lifecycleOptions)
    end

    function app:data(key, definition)
        if not validId(key) then error("invalid data id", 2) end
        definition = definition or {}
        if type(definition) ~= "table" then error("data definition must be a table", 2) end
        if not self.dataItems[key] then table.insert(self.dataOrder, key) end
        self.dataItems[key] = {
            id = key, label = definition.label or key, unit = definition.unit,
            value = definition.value, read = definition.read,
            category = definition.category or "general",
            trueLabel=definition.trueLabel, falseLabel=definition.falseLabel
        }
        if definition.read ~= nil and type(definition.read) ~= "function" then error("data read must be a function", 2) end
        return self
    end

    function app:set(key, value)
        local item = self.dataItems[key]
        if not item then return false, "unknown data: " .. tostring(key) end
        item.value = value
        return true
    end

    function app:control(key, definition)
        if not validId(key) then error("invalid control id", 2) end
        if type(definition) ~= "table" or type(definition.run) ~= "function" then
            error("control definition needs a run function", 2)
        end
        if definition.enabled ~= nil and type(definition.enabled) ~= "boolean" and type(definition.enabled) ~= "function" then
            error("control enabled must be a boolean or function", 2)
        end
        if not self.controls[key] then table.insert(self.controlOrder, key) end
        if definition.requires ~= nil and type(definition.requires) ~= "table" then
            error("control requires must be a list of I/O roles", 2)
        end
        local requires = {}
        for _, role in ipairs(definition.requires or {}) do
            if not validId(role) then error("invalid required I/O role", 2) end
            requires[#requires + 1] = role
        end
        self.controls[key] = {
            id = key, label = definition.label or key, run = definition.run,
            description = definition.description,
            enabled = definition.enabled, confirm = definition.confirm == true,
            remote = definition.remote == true, requires = requires,
            monitor = definition.monitor == true, navigation = definition.navigation == true, state = definition.state,
            category = definition.category or "general",
            trueLabel=definition.trueLabel,falseLabel=definition.falseLabel,
            trueControl=definition.trueControl,falseControl=definition.falseControl,
            uiHidden=definition.uiHidden==true,toggle=definition.toggle==true
        }
        return self
    end

    function app:view(key, definition)
        if not validId(key) then error("invalid view id", 2) end
        if type(definition) ~= "table" then error("view definition must be a table", 2) end
        if not self.views[key] then table.insert(self.viewOrder, key) end
        self.views[key] = {
            id = key, label = definition.label or key, layout = definition.layout or "dashboard",
            data = definition.data or {}, controls = definition.controls or {},
            graphs = definition.graphs or {}, children = definition.children, minWidth = definition.minWidth, minHeight = definition.minHeight,
            category = definition.category or "main", categoryLabel = definition.categoryLabel,
            subcategory = definition.subcategory, persistent = definition.persistent == true,
            parent = definition.parent, panelTitle = definition.panelTitle, controlTitle = definition.controlTitle,
            metricLabels = definition.metricLabels, widgets = definition.widgets,
            exportGroups = definition.exportGroups,localExports=definition.localExports==true,
            navigation = definition.navigation, sourceNavigation = definition.sourceNavigation,
            dynamicRows = definition.dynamicRows == true,
            columns = definition.columns, cardHeight = definition.cardHeight,
            textOnly = definition.textOnly == true
        }
        return self
    end

    -- Hardware is resolved by lib.io_registry / ioctl, not by hard-coded CraftOS sides.
    -- Technical pages belong to the app, including when launched by a preset.
    -- They are exported as views and keep a stable technical category.
    function app:technical(key, definition)
        if not validId(key) then error("invalid technical view id", 2) end
        if type(definition) ~= "table" then error("technical view must be a table", 2) end
        local view = {}
        for k,v in pairs(definition) do view[k]=v end
        view.label = view.label or "Technical"
        view.category = "maintenance"
        view.textOnly = true
        view.persistent = true
        self:view(key, view)
        return self
    end

    -- Dedicated CraftOS terminal interface, distinct from monitor views.
    function app:maintenance(key, definition)
        if not validId(key) then error("invalid maintenance id", 2) end
        if type(definition) ~= "table" then error("maintenance definition must be a table", 2) end
        self.maintenanceDefinition = definition
        self.maintenanceId = key
        self.maintenancePage = 1
        return self
    end

    function app:maintenanceSnapshot()
        local definition=self.maintenanceDefinition or {}
        local function read(value, fallback)
            if type(value)=="function" then
                local ok,result=pcall(value)
                if ok then return result end
                runtime.log("app:"..self.id,"error","maintenance provider: "..tostring(result))
                return fallback
            end
            return value or fallback
        end
        local statuses,tools,requirements={}, {}, {}
        for _,entry in ipairs(definition.status or {}) do
            statuses[#statuses+1]={id=entry.id,label=entry.label or entry.id,
                value=read(entry.read or entry.value,"UNKNOWN"),detail=read(entry.detail)}
        end
        for _,id in ipairs(definition.tools or {}) do
            local key=type(id)=="table" and id.id or id
            local action=self.controls[key]
            if action then
                local enabled=read(action.enabled,true)
                tools[#tools+1]={id=key,label=action.label,enabled=enabled~=false}
            end
        end
        local provided={}
        for _,entry in ipairs(definition.requirements or {}) do
            provided[entry.id]=true
            requirements[#requirements+1]={id=entry.id,label=entry.label or entry.id,
                status=read(entry.status,"UNKNOWN"),detail=read(entry.detail),
                required=entry.required==true}
        end
        local discovered=self:hardwareStatus()
        for _,entry in ipairs(discovered) do
            if not provided[entry.id] then requirements[#requirements+1]=entry end
        end
        local logs=runtime.logs(tonumber(definition.logLimit) or 5,"app:"..self.id)
        return {title=definition.title or self.title,status=statuses,
            tools=tools,requirements=requirements,logs=logs or {}}
    end

    function app:drawMaintenance(target, options)
        local ui=require("lib.maintenance_ui")
        options=options or {}
        options.page=options.page or self.maintenancePage or 1
        local result=ui.render(target,self:maintenanceSnapshot(),options)
        if result.ok then self.maintenancePage=result.page end
        return result
    end

    function app:maintenanceTouch(result,x,y)
        if not result or not result.ok then return false,"maintenance unavailable" end
        local id=require("lib.maintenance_ui").hit(result,x,y)
        if id=="maintenance.previous" or id=="maintenance.next" then
            local step=id=="maintenance.next" and 1 or -1
            self.maintenancePage=math.max(1,math.min(result.pageCount,result.page+step))
            return true,"page_changed"
        end
        if not id then return false,"no maintenance action here" end
        return self:invoke(id)
    end

    function app:showView(key)
        if not self.views[key] then return false, "unknown view: " .. tostring(key) end
        self.activeView=key
        self.displayPage=1
        return true
    end

    function app:io(key, definition)
        if not validId(key) then error("invalid I/O role", 2) end
        if type(definition) ~= "table" then error("I/O definition must be a table", 2) end
        if type(definition.type) ~= "string" or definition.type == "" then
            error("I/O requirement needs a peripheral type", 2)
        end
        local direction = definition.direction or "input"
        if direction ~= "input" and direction ~= "output" and direction ~= "inout" then
            error("I/O direction must be input, output or inout", 2)
        end
        if (definition.invert or definition.readOutput) and definition.type ~= "redstone" then
            error("invert/readOutput are reserved for redstone requirements", 2)
        end
        self.hardware = self.hardware or {}
        self.hardware[key] = {
            type = definition.type, direction = definition.direction or "input",
            required = definition.required == true, label = definition.label or key,
            invert = definition.invert == true, readOutput = definition.readOutput == true
        }
        return self
    end

    -- Validate application-declared hardware roles against the existing ioctl bindings.
    -- This is read-only: ioctl init remains responsible for configuring /etc/io.lua.
    -- The SDK and ioctl must agree on auto-selection, ambiguity and disabled roles.
    -- Resolve from the common I/O registry instead of maintaining a second
    -- hardware discovery algorithm here.
    function app:hardwareStatus()
        local registry = require("lib.io_registry")
        local results, ready = {}, true
        for key, role in pairs(self.hardware or {}) do
            local qualified = self.id .. "." .. key
            local device, err, physical = registry.resolve(qualified, role)
            local present = device ~= nil
            if role.required and not present then ready = false end
            results[#results + 1] = {
                id = key,
                label = role.label or key,
                required = role.required == true,
                status = present and "OK" or "MISSING",
                detail = present and (physical or "available") or err,
            }
        end
        table.sort(results, function(left, right) return left.id < right.id end)
        return results, ready
    end

    function app:call(role, method, ...)
        if not (self.hardware or {})[role] then return nil, "undeclared I/O role: " .. tostring(role) end
        return require("lib.io_registry").call(self.id .. "." .. role, method, ...)
    end

    function app:read(key, fallback)
        if not (self.hardware or {})[key] then return nil, "undeclared I/O role: " .. tostring(key) end
        local io = require("lib.io_registry")
        return io.read(self.id.."."..key, fallback)
    end

    function app:write(key, value, fallback)
        if not (self.hardware or {})[key] then return false, "undeclared I/O role: " .. tostring(key) end
        local io = require("lib.io_registry")
        return io.write(self.id.."."..key, value, fallback)
    end

    -- Advanced applications may retain their current text and graphics backends.
    -- Display owns selection/fallback; the app owns the backend's layout.
    function app:toast(message,kind)
        self.displayToast={message=tostring(message or ""),kind=kind or "info",expires=os.clock()+4}
    end

    function app:renderer(options)
        return require("lib.display").renderer(options)
    end

    -- Generic SDK views render in text mode until a standard graphics backend exists.
    -- Optional monitor failure does not stop the application.
    -- One declarative view contract for text and CC:Graphics.
    function app:draw(target, options)
        options = options or {}
        local resolved = target or term.current()
        self.displayPage = self.displayPage or 1
        self.displayMode = self.displayMode or "auto"
        local textOk, textRenderer = pcall(require, "lib.display_sdk")
        if not textOk then return nil, "module.display is not installed" end
        local graphicOk, graphicRenderer = pcall(require, "lib.display_sdk_graphics")
        local graphicsSupported = graphicOk
            and type(resolved.setGraphicsMode) == "function"
            and type(resolved.drawPixels) == "function"
            and type(resolved.setPixel) == "function"
        local settings = {}
        for k,v in pairs(options) do settings[k] = v end
        settings.viewMode = self:config("display.viewMode","exports")
        settings.exportCategory = self.displayExportCategory or "data"
        settings.exportItem = self.displayExportItem
        settings.pendingControl = self.monitorPendingControl and self.monitorPendingControl.id
        if self.remoteDisplayReady then
            local okReady,ready=pcall(self.remoteDisplayReady)
            settings.remoteControlReady=okReady and ready==true
            if self.monitorPendingControl and self.monitorPendingControl.source
                and self.remoteDisplayIdentity then
                local okIdentity,identity=pcall(self.remoteDisplayIdentity)
                if not okIdentity or identity~=self.monitorPendingControl.source then
                    settings.pendingControl=nil
                end
            end
        end
        settings.toast = self.displayToast and os.clock()<self.displayToast.expires
            and self.displayToast or nil
        settings.view = settings.view or self.activeView or self.viewOrder[1]
        self.activeView=settings.view
        settings.page = settings.page or self.displayPage
        settings.scrollOffset = settings.scrollOffset or self.bannerOffset or 0
        -- Configured backend is the startup preference; a UI toggle is an
        -- explicit session override (including when configured "text").
        local preferred = self.displayMode~="auto"
            and self.displayMode or (settings.backend or "auto")
        settings.graphicsAvailable = graphicsSupported and settings.terminalOnly~=true
        local activeView=self.views[settings.view]
        local useGraphics = graphicsSupported and settings.terminalOnly ~= true and preferred ~= "text"
            and not (activeView and activeView.textOnly)
        local result
        if useGraphics then
            local ok, rendered = pcall(graphicRenderer.render, resolved, self:descriptor(), settings)
            if ok and rendered and rendered.ok then
                result = rendered
                self.lastGraphicsFallback=nil
            else
                local reason=(ok and rendered and rendered.warning) or (ok and "renderer rejected" or tostring(rendered))
                if self.lastGraphicsFallback~=reason then
                    runtime.log("app:" .. self.id, "warning",
                        "graphics unavailable ("..tostring(reason).."), using text")
                    self.lastGraphicsFallback=reason
                end
            end
        end
        if not result then
            if type(resolved.setGraphicsMode) == "function" then
                pcall(resolved.setGraphicsMode, false)
            end
            settings.backend = "text"
            local ok, rendered = pcall(textRenderer.render, resolved, self:descriptor(), settings)
            if not ok then return nil, tostring(rendered) end
            result = rendered
            result.backend = "text"
        end
        if result.ok then self.displayPage = result.page end
        if result.warning == "resolution_too_low" then
            local warning = tostring(result.width) .. "x" .. tostring(result.height)
            if self.lastDisplayWarning ~= warning then
                runtime.log("app:" .. self.id, "warning", "display too small (" .. warning .. ")")
                self.lastDisplayWarning = warning
            end
        else
            self.lastDisplayWarning = nil
        end
        result.options = settings
        result.target = resolved
        result.graphicsAvailable = graphicsSupported and settings.terminalOnly ~= true
        return result
    end

    -- Called by a CraftOS timer/event loop to advance scrolling banners.
    function app:tick()
        self.bannerOffset=(self.bannerOffset or 0)+1
        return self.bannerOffset
    end

    function app:touch(result, x, y)
        if not result or not result.ok then return false, "display unavailable" end
        local rendererName = result.backend == "ccgraphics"
            and "lib.display_sdk_graphics" or "lib.display_sdk"
        local ok, renderer = pcall(require, rendererName)
        if not ok then return false, "display renderer unavailable" end
        local id = renderer.hit(result, x, y)
        if not id then return false, "no control at position" end
        if id=="display.control.cancel" then
            self.monitorPendingControl=nil
            return true,"control_cancelled"
        end
        if type(id)=="string" and id:sub(1,23)=="display.control.remote." then
            if type(self.remoteDisplayHandler)~="function"
                or type(self.remoteDisplayReady)~="function"
                or type(self.remoteDisplayIdentity)~="function" then
                return false,"remote display unavailable"
            end
            local controlId=id:sub(24)
            if not validId(controlId) then return false,"invalid remote control ID" end
            local okReady,ready=pcall(self.remoteDisplayReady)
            if not okReady or ready~=true then
                self.monitorPendingControl=nil
                self:toast("REMOTE CONTROL LOCKED","error")
                return false,"remote control locked"
            end
            local okSource,source=pcall(self.remoteDisplayIdentity)
            if not okSource or type(source)~="string" or source=="" then
                return false,"remote source unavailable"
            end
            local key="remote."..controlId
            local current=os.clock()
            local pending=self.monitorPendingControl
            if self:config("display.confirmControls",true)~=false
                and not (pending and pending.id==key and pending.source==source
                    and current-pending.time<=5) then
                self.monitorPendingControl={id=key,source=source,time=current}
                self:toast("PRESS AGAIN TO CONFIRM","info")
                return true,"control_confirmation_required"
            end
            self.monitorPendingControl=nil
            return self.remoteDisplayHandler(controlId,source)
        end
        if type(id)=="string" and id:sub(1,16)=="display.control." then
            local key=id:sub(17)
            local control=self.controls[key]
            if not control or control.monitor~=true then return false,"control not touch enabled" end
            local available=control.enabled~=false
            if available and type(control.enabled)=="function" then
                local okEnabled,enabled=pcall(control.enabled)
                available=okEnabled and enabled~=false
            end
            if not available then
                local reason=key:match("^reboot_machine_%d+$")
                    and "REBOOT NOT AUTHORIZED"
                    or "CONTROL UNAVAILABLE"
                self:toast(reason,"error")
                self.monitorPendingControl=nil
                return false,reason
            end
            if control.navigation==true and control.remote==false then return self:invoke(key) end
            local now=os.clock()
            local pending=self.monitorPendingControl
            if pending and pending.id==key and now-pending.time<=5 then
                self.monitorPendingControl=nil
                return self:invoke(key)
            end
            self.monitorPendingControl={id=key,time=now}
            if key:match("^reboot_machine_%d+$") then
                self:toast("CONFIRM REBOOT - PRESS AGAIN","info")
            else
                self:toast("PRESS AGAIN TO CONFIRM","info")
            end
            return true,"control_confirmation_required"
        end
        if type(id)=="string" and id:sub(1,15)=="display.export." then
            local kind=id:sub(16)
            if kind~="data" and kind~="graphs" and kind~="controls" then return false,"unknown export category" end
            self.displayExportCategory=kind
            self.displayExportItem=nil
            self.displayPage=1
            return true,"export_category_changed"
        end
        if type(id)=="string" and id:sub(1,13)=="display.item." then
            local kind,item=id:match("^display%.item%.([%w_]+)%.([%w_%-]+)$")
            if not kind or kind~=self.displayExportCategory then return false,"invalid export item" end
            local collection=kind=="data" and self.dataItems or kind=="graphs" and self.graphs or self.controls
            if not collection or not collection[item] then return false,"unknown export item" end
            self.displayExportItem=item
            self.displayPage=1
            return true,"export_item_changed"
        end
        if type(id)=="string" and id:sub(1,13)=="display.view." then
            return self:showView(id:sub(14))
        end
        if id == "display.previous" or id == "display.next" then
            local offset = id == "display.next" and 1 or -1
            self.displayPage = math.max(1, math.min(result.pageCount, result.page + offset))
            return true, "page_changed"
        end
        if id == "display.maintenance" then
            local selected
            for _,key in ipairs(self.viewOrder) do
                if self.views[key].category=="maintenance" then selected=key;break end
            end
            if not selected then return false, "no maintenance view" end
            self:showView(selected)
            return true, "maintenance_open"
        end
        if id == "display.home" then
            for _,key in ipairs(self.viewOrder) do
                if self.views[key].category~="maintenance" then
                    self:showView(key)
                    return true, "maintenance_closed"
                end
            end
            return false, "no main view"
        end
        if id == "display.toggle" then
            if not result.graphicsAvailable then return false, "graphics unavailable" end
            self.displayMode = result.backend == "text" and "ccgraphics" or "text"
            return true, "renderer_changed"
        end
        return self:invoke(id)
    end

    -- A graph is an exported series of numeric samples, independent of its renderer.
    function app:graph(key, definition)
        if not validId(key) then error("invalid graph id", 2) end
        if type(definition) ~= "table" then error("graph definition must be a table", 2) end
        self.graphs = self.graphs or {}
        self.graphOrder = self.graphOrder or {}
        if not self.graphs[key] then table.insert(self.graphOrder, key) end
        self.graphs[key] = {
            id=key, label=definition.label or key, unit=definition.unit,
            category=definition.category or "general",
            min=definition.min,max=definition.max,
            resolution=definition.resolution,timeWindow=definition.timeWindow,
            limit=math.max(2, math.min(tonumber(definition.limit) or 60, 300)),
            samples={}
        }
        return self
    end

    function app:sample(key, value, timestamp)
        local graph = self.graphs and self.graphs[key]
        if not graph then return false, "unknown graph: " .. tostring(key) end
        if type(value) ~= "number" then return false, "graph sample must be numeric" end
        local at = timestamp or os.epoch("utc")
        if type(at) ~= "number" or at ~= at then return false, "invalid sample timestamp" end
        if value ~= value or value == math.huge or value == -math.huge then return false, "invalid sample value" end
        local sample = {timestamp=at, value=value}
        table.insert(graph.samples, sample)
        while #graph.samples > graph.limit do table.remove(graph.samples, 1) end
        return true
    end

    -- A banner exposes a dynamic message that renderers may scroll.
    function app:banner(key, definition)
        if not validId(key) then error("invalid banner id", 2) end
        if type(definition) ~= "table" then error("banner definition must be a table", 2) end
        if definition.read ~= nil and type(definition.read) ~= "function" then
            error("banner read must be a function", 2)
        end
        self.banners = self.banners or {}
        self.bannerOrder = self.bannerOrder or {}
        if not self.banners[key] then table.insert(self.bannerOrder, key) end
        self.banners[key] = {
            id=key, value=definition.value, read=definition.read,
            label=definition.label or key, scroll=definition.scroll ~= false
        }
        return self
    end

    function app:bannerValue(key, value)
        local banner=self.banners and self.banners[key]
        if not banner then return false, "unknown banner: "..tostring(key) end
        banner.value=value
        return true
    end

    function app:values()
        local out = {}
        for _, key in ipairs(self.dataOrder) do
            local item = self.dataItems[key]
            local value = item.value
            if item.read then
                local ok, result = pcall(item.read)
                if ok then value = result
                else runtime.log("app:" .. self.id, "error", "data " .. key .. ": " .. tostring(result)) end
            end
            table.insert(out, {id = key, label = item.label, unit = item.unit, value = value, category = item.category,
                trueLabel=item.trueLabel,falseLabel=item.falseLabel})
        end
        return out
    end

    function app:descriptor()
        local controls, views, graphs, banners = {}, {}, {}, {}
        for _, key in ipairs(self.controlOrder) do
            local item = self.controls[key]
            local enabled = item.enabled
            if type(enabled) == "function" then
                local ok, result = pcall(enabled)
                enabled = ok and result ~= false
                if not ok then
                    enabled = false
                    runtime.log("app:" .. self.id, "error", "control " .. key .. " availability check failed: " .. tostring(result))
                end
            end
            if enabled ~= false then
                for _, roleKey in ipairs(item.requires or {}) do
                    local declaration = (self.hardware or {})[roleKey]
                    if not declaration then
                        enabled = false
                        break
                    end
                    local device = require("lib.io_registry").resolve(self.id .. "." .. roleKey, declaration)
                    if not device then enabled = false; break end
                end
            end
            table.insert(controls, {
                id = key, label = item.label, description = item.description,
                enabled = enabled ~= false, confirm = item.confirm, remote = item.remote,
                monitor = item.monitor == true, navigation = item.navigation == true,
                category = item.category,
                trueLabel=item.trueLabel,falseLabel=item.falseLabel,
                trueControl=item.trueControl,falseControl=item.falseControl,
                uiHidden=item.uiHidden==true,toggle=item.toggle==true,
                state = (function()
                    if type(item.state) ~= "function" then return nil end
                    local ok,value=pcall(item.state)
                    if ok then return tostring(value) end
                    return "UNKNOWN"
                end)(),
                requires = item.requires
            })
        end
        for _, key in ipairs(self.viewOrder) do table.insert(views, self.views[key]) end
        for _, key in ipairs(self.graphOrder or {}) do
            local graph=self.graphs[key]
            local samples = {}
            for _, sample in ipairs(graph.samples) do
                samples[#samples+1] = {timestamp=sample.timestamp, value=sample.value}
            end
            table.insert(graphs, {id=key,label=graph.label,unit=graph.unit,category=graph.category,
                min=graph.min,max=graph.max,resolution=graph.resolution,
                timeWindow=graph.timeWindow,samples=samples})
        end
        for _,key in ipairs(self.bannerOrder or {}) do
            local item=self.banners[key]
            local value=item.value
            if item.read then
                local ok,result=pcall(item.read)
                if ok then value=result
                else runtime.log("app:"..self.id,"error","banner "..key..": "..tostring(result)) end
            end
            if type(value) == "table" then
                value=textutils.serializeJSON(value)
            end
            table.insert(banners,{id=key,label=item.label,value=value,scroll=item.scroll})
        end
        -- Resolve dynamic values exactly once per descriptor. Local display and
        -- remote snapshots must see the same categorized collection.
        local data=self:values()
        -- Every SDK application exposes the same structured collections to the
        -- local renderer. Supervisors may replace individual groups with a
        -- selected remote machine's exports without losing the other groups.
        local exports={data=data,graphs=graphs,controls=controls}
        for kind,items in pairs(self.remoteExports or {}) do exports[kind]=items end
        return {
            schema = "attacc.sdk.app.v1", id = self.id, title = self.title,
            data = data, controls = controls, graphs = graphs, banners = banners, views = views,
            hardware = self.hardware or {}, textSummary = self.textSummary,
            remoteExports = exports,
        }
    end

    -- Local, read-only presentation of another SDK application's exports.
    -- These groups are derived at render time; no remote application UI is copied.
    -- Opt-in default dashboard. The application remains the sole owner of
    -- exported metrics and controls; display decides the responsive layout.
    -- Custom app:view() declarations stay supported and are never replaced
    -- unless explicitly requested by the application.
    function app:buildDashboard(options)
        options=options or {}
        local root=options.root or "dashboard"
        if not validId(root) then return false,"invalid dashboard root" end
        self.autoDashboard=true
        local views={
            {id=root,label=options.label or "DASHBOARD",
                exportGroups="data",localExports=true,widgets={},columns=2},
            {id=root.."_graphs",parent=root,label="GRAPHS",
                exportGroups="graphs",localExports=true,widgets={},columns=2},
            {id=root.."_controls",parent=root,label="CONTROLS",
                exportGroups="controls",localExports=true,widgets={},columns=2},
        }
        for _,view in ipairs(views) do
            if not validId(view.id) then return false,"invalid dashboard view id" end
            if not self.views[view.id] or options.replace==true then
                self:view(view.id,view)
            end
        end
        return true
    end

    function app:setRemoteExports(kind,items)
        self.remoteExports=self.remoteExports or {}
        self.remoteExports[kind]=type(items)=="table" and items or {}
        return self
    end

    function app:registerIO()
        return require("lib.io_declarations").publish(self.id,self.hardware or {})
    end

    function app:publish()
        local saved,saveError=self:registerIO()
        if not saved then return false,saveError end
        local descriptor = self:descriptor()
        local ok = webcap.publish(self.id, descriptor)
        if not ok then return false, "webcap publication failed" end
        -- Display is optional, and belongs to module.display.
        local loaded, display = pcall(require, "lib.display_api")
        if loaded then
            local published, err = display.publish(self.id, descriptor)
            if not published then return false, err end
        end
        return true
    end

    function app:invoke(key, ...)
        local item = self.controls[key]
        if not item then return false, "unknown control: " .. tostring(key) end
        -- Per-action hardware gates. Safety/abort actions can omit requires,
        -- keeping them callable even when a sensor becomes unavailable.
        for _, roleKey in ipairs(item.requires or {}) do
            local declaration = (self.hardware or {})[roleKey]
            if not declaration then return false, "undeclared I/O role: " .. roleKey end
            local _, err = require("lib.io_registry").resolve(self.id .. "." .. roleKey, declaration)
            if err then return false, "hardware " .. roleKey .. ": " .. err end
        end
        if item.enabled == false then return false, "control unavailable" end
        if type(item.enabled) == "function" then
            local available, enabled = pcall(item.enabled)
            if not available or enabled == false then return false, "control unavailable" end
        end
        local ok, value, detail = pcall(item.run, ...)
        if not ok then
            runtime.log("app:" .. self.id, "error", "control " .. key .. ": " .. tostring(value))
            return false, tostring(value)
        end
        if value == false then return false, detail or "control rejected" end
        return true, value
    end

    function app:on(topic, callback)
        local token, err = bus.on(topic, callback)
        if token then table.insert(self.listeners, token) end
        return token, err
    end

    function app:emit(topic, payload)
        return bus.emit(topic, payload)
    end

    function app:handle(...)
        return bus.handle(...)
    end

    function app:status(state, detail)
        return runtime.set("app:" .. self.id, state, { detail = detail })
    end

    function app:log(level, message)
        return runtime.log("app:" .. self.id, level, message)
    end

    function app:close()
        for _, token in ipairs(self.listeners) do bus.off(token) end
        self.listeners = {}
        local loaded, display = pcall(require, "lib.display_api")
        if loaded then display.clear(self.id) end
        webcap.clear(self.id)
        runtime.remove("app:" .. self.id)
    end

    return app
end

return M
