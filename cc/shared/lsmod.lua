local machineInfo = require("lib.machine")
local runtime = require("lib.runtime")

local machine = machineInfo.get()
local snap = runtime.snapshot()
local states = snap.services or {}

local moduleDir = ".infra/modules"
local installed = {}

if fs.exists(moduleDir) and fs.isDir(moduleDir) then
    for _, fileName in ipairs(fs.list(moduleDir)) do
        if fileName:match("%.mod%.lua$") then
            local ok, def = pcall(dofile, fs.combine(moduleDir, fileName))
            if ok and type(def) == "table" then
                local name = def.name or fileName:gsub("%.mod%.lua$", "")
                installed[name] = def
            end
        end
    end
end

local declared = {}
for name in pairs(installed) do declared[name] = true end
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

    local status = "unknown"
    local detail = "declared, no runtime health report"

    if entry then
        status = tostring(entry.status or "unknown")
        detail = entry.detail or entry.error or entry.missingDependency or ""
    elseif installed[name] then
        status = "available"
        detail = installed[name].description or "installed module capability"
    elseif declared[name] then
        status = "declared"
    end

    print(string.format("%-32s %-10s %s", name .. ".mod", status, tostring(detail or "")))
end
