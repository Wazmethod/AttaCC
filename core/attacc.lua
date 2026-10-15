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

    function app:data(key, definition)
        if not validId(key) then error("invalid data id", 2) end
        definition = definition or {}
        if type(definition) ~= "table" then error("data definition must be a table", 2) end
        if not self.dataItems[key] then table.insert(self.dataOrder, key) end
        self.dataItems[key] = {
            id = key, label = definition.label or key, unit = definition.unit,
            value = definition.value, read = definition.read
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
        self.controls[key] = {
            id = key, label = definition.label or key, run = definition.run,
            description = definition.description,
            enabled = definition.enabled, confirm = definition.confirm == true,
            remote = definition.remote == true
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
            children = definition.children, minWidth = definition.minWidth, minHeight = definition.minHeight
        }
        return self
    end

    -- Hardware is resolved by lib.io_registry / ioctl, not by hard-coded CraftOS sides.
    function app:io(key, definition)
        if not validId(key) then error("invalid I/O role", 2) end
        if type(definition) ~= "table" then error("I/O definition must be a table", 2) end
        self.hardware = self.hardware or {}
        self.hardware[key] = {
            type = definition.type, direction = definition.direction or "input",
            required = definition.required == true, label = definition.label or key
        }
        return self
    end

    function app:read(key)
        local io = require("lib.io_registry")
        return io.read(key)
    end

    function app:write(key, value)
        local io = require("lib.io_registry")
        return io.write(key, value)
    end

    -- Advanced applications may retain their current text and graphics backends.
    -- Display owns selection/fallback; the app owns the backend's layout.
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
        settings.page = settings.page or self.displayPage
        local preferred = settings.backend or self.displayMode
        local useGraphics = graphicsSupported and preferred ~= "text"
        local result
        if useGraphics then
            local ok, rendered = pcall(graphicRenderer.render, resolved, self:descriptor(), settings)
            if ok and rendered and rendered.ok then
                result = rendered
            else
                runtime.log("app:" .. self.id, "warning", "graphics unavailable, using text")
                self.displayMode = "text"
            end
        end
        if not result then
            if type(resolved.setGraphicsMode) == "function" then
                pcall(resolved.setGraphicsMode, false)
            end
            settings.graphicsAvailable = graphicsSupported
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
        result.graphicsAvailable = graphicsSupported
        return result
    end

    function app:touch(result, x, y)
        if not result or not result.ok then return false, "display unavailable" end
        local rendererName = result.backend == "ccgraphics"
            and "lib.display_sdk_graphics" or "lib.display_sdk"
        local ok, renderer = pcall(require, rendererName)
        if not ok then return false, "display renderer unavailable" end
        local id = renderer.hit(result, x, y)
        if not id then return false, "no control at position" end
        if id == "display.previous" or id == "display.next" then
            local offset = id == "display.next" and 1 or -1
            self.displayPage = math.max(1, math.min(result.pageCount, result.page + offset))
            return true, "page_changed"
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
            table.insert(out, {id = key, label = item.label, unit = item.unit, value = value})
        end
        return out
    end

    function app:descriptor()
        local controls, views, graphs = {}, {}, {}
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
            table.insert(controls, {
                id = key, label = item.label, description = item.description,
                enabled = enabled ~= false, confirm = item.confirm, remote = item.remote
            })
        end
        for _, key in ipairs(self.viewOrder) do table.insert(views, self.views[key]) end
        for _, key in ipairs(self.graphOrder or {}) do
            local graph=self.graphs[key]
            local samples = {}
            for _, sample in ipairs(graph.samples) do
                samples[#samples+1] = {timestamp=sample.timestamp, value=sample.value}
            end
            table.insert(graphs, {id=key,label=graph.label,unit=graph.unit,samples=samples})
        end
        return {
            schema = "attacc.sdk.app.v1", id = self.id, title = self.title,
            data = self:values(), controls = controls, graphs = graphs, views = views,
            hardware = self.hardware or {},
        }
    end

    function app:publish()
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
        if item.enabled == false then return false, "control unavailable" end
        if type(item.enabled) == "function" then
            local available, enabled = pcall(item.enabled)
            if not available or enabled == false then return false, "control unavailable" end
        end
        local ok, value = pcall(item.run, ...)
        if not ok then
            runtime.log("app:" .. self.id, "error", "control " .. key .. ": " .. tostring(value))
            return false, tostring(value)
        end
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
