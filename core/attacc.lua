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
        if not self.controls[key] then table.insert(self.controlOrder, key) end
        self.controls[key] = {
            id = key, label = definition.label or key, run = definition.run,
            description = definition.description
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

    function app:draw(target, options)
        local ok, renderer = pcall(require, "lib.display_sdk")
        if not ok then return nil, "module.display is not installed" end
        local descriptor = self:descriptor()
        local result = renderer.render(target, descriptor, options)
        if result.warning == "resolution_too_low" then
            runtime.log("app:" .. self.id, "warning",
                "display too small (" .. result.width .. "x" .. result.height .. ")")
        end
        return result
    end

    function app:touch(result, x, y)
        local ok, renderer = pcall(require, "lib.display_sdk")
        if not ok then return false, "module.display is not installed" end
        local id = renderer.hit(result, x, y)
        if not id then return false, "no control at position" end
        return self:invoke(id)
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
        local controls, views = {}, {}
        for _, key in ipairs(self.controlOrder) do
            local item = self.controls[key]
            table.insert(controls, {id = key, label = item.label, description = item.description})
        end
        for _, key in ipairs(self.viewOrder) do table.insert(views, self.views[key]) end
        return {
            schema = "attacc.sdk.app.v1", id = self.id, title = self.title,
            data = self:values(), controls = controls, views = views,
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
