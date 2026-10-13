local migrations = require("lib.migrations")
local args = { ... }
local command = args[1] or "run"

if command == "status" then
    local paths = require("lib.paths")
    local installed = 0
    if fs.exists(paths.schema) then
        local h = fs.open(paths.schema, "r")
        if h then
            local raw = h.readAll()
            h.close()
            local ok, data = pcall(textutils.unserializeJSON, raw)
            if ok and type(data) == "table" then installed = tonumber(data.version) or 0 end
        end
    end
    print("Filesystem schema : " .. tostring(installed))
    print("Current schema    : " .. tostring(migrations.currentVersion()))
    print(installed == migrations.currentVersion() and "State             : current" or "State             : migration required")
    return
end

local quiet = false
for _, value in ipairs(args) do
    if value == "--quiet" then quiet = true end
end

local ok, result = migrations.run({ verbose = not quiet })
if not ok then error(result) end

if quiet then
    print("Migration complete.")
end
