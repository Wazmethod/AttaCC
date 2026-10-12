local modules = require("lib.modules")
local machineInfo = require("lib.machine")
local runtime = require("lib.runtime")

modules.syncRuntime()

local machine = machineInfo.get()
local snap = runtime.snapshot()
local states = snap.services or {}

local names = {}
local seen = {}

for _, name in ipairs(modules.names()) do
    seen[name] = true
    table.insert(names, name)
end

for _, name in ipairs(machine.modules or {}) do
    if name ~= "workstation.display" and name ~= "workstation.console" and not seen[name] then
        seen[name] = true
        table.insert(names, name)
    end
end

for key in pairs(states) do
    local name = key:match("^module:(.+)$")
    if name and name ~= "workstation.display" and name ~= "workstation.console" and not seen[name] then
        seen[name] = true
        table.insert(names, name)
    end
end

table.sort(names)

if #names == 0 then
    print("No modules installed or observed.")
    return
end

print(string.format("%-32s %-12s %s", "MODULE", "STATE", "DETAIL"))

for _, name in ipairs(names) do
    local status = modules.status(name)
    local entry = states["module:" .. name]

    local state = "declared"
    local detail = "declared by machine/runtime"

    if status then
        state = status.state or "loaded"
        detail = status.detail or status.description or ""
    elseif entry then
        state = tostring(entry.status or "unknown")
        detail = entry.detail or entry.error or ""
    end

    print(string.format("%-32s %-12s %s",
        name .. ".mod",
        tostring(state),
        tostring(detail or "")))
end
