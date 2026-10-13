local migrations = require("lib.migrations")
local args = { ... }
local verbose = args[1] ~= "--quiet"

local ok, result = migrations.run({ verbose = verbose })
if not ok then error(result) end

if not verbose then
    print("Migration complete.")
end
