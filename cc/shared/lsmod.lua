local machineInfo = require("lib.machine")
local runtime = require("lib.runtime")

local machine = machineInfo.get()
local snap = runtime.snapshot()
local states = snap.services or {}

local serviceBacked = {
    ["core.remote-shell"] = "remote-shell",
    ["network.storage"] = "storage",
}

local declared = {}
for _, name in ipairs(machine.modules or {}) do declared[name] = true end

for key in pairs(states) do
    local name = key:match("^module:(.+)$")
    if name and name ~= "workstation.display" then declared[name] = true end
end
declared["workstation.display"] = nil

local names = {}
for name in pairs(declared) do table.insert(names, name) end
table.sort(names)

if #names == 0 then
    print("No modules declared or observed.")
    return
end

print(string.format("%-32s %-10s %s", "MODULE", "STATE", "DETAIL"))
for _, name in ipairs(names) do
    local entry = states["module:" .. name]
    if not entry and serviceBacked[name] then
        entry = states["service:" .. serviceBacked[name]]
    end

    local status = "unknown"
    local detail = "declared, no runtime health report"

    if entry then
        status = tostring(entry.status or "unknown")
        detail = entry.detail or entry.error or entry.missingDependency or ""
    elseif declared[name] then
        status = "declared"
    end

    print(string.format("%-32s %-10s %s", name .. ".mod", status, tostring(detail or "")))
end
