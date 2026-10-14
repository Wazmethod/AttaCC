-- AttaCC local log reader (no network dependency).
local ok, runtime = pcall(require, "lib.runtime")
if not ok then printError("AttaCC runtime unavailable: " .. tostring(runtime)) return end

local args = {...}
local action = args[1] or "tail"
if action ~= "tail" and action ~= "errors" and action ~= "health" then
    print("logctl [tail|errors|health] [count] [component]")
    return
end

if action == "health" then
    local state = runtime.snapshot()
    local names = {}
    for name in pairs(state.entries or {}) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then print("No runtime health entries.") return end
    for _, name in ipairs(names) do
        local entry = state.entries[name]
        print(string.format("%s: %s", name, tostring(entry.status or "unknown")))
    end
    return
end

local limit = math.min(200, math.max(1, tonumber(args[2]) or 30))
local component = args[3]
local entries = runtime.logs(limit, component)
local count = 0
for _, entry in ipairs(entries) do
    if action ~= "errors" or entry.level == "error" or entry.level == "warn" then
        print(string.format("[%s] %s %s: %s", entry.date or "?", entry.level or "info", entry.component or "runtime", entry.message or ""))
        count = count + 1
    end
end
if count == 0 then print("No matching log entries.") end
