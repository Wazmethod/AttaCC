-- AttaCC local diagnostics, usable on normal and advanced CraftOS computers.
local args = {...}
local action = args[1]

local function help()
    print("AttaCC local diagnostics")
    print("Usage:")
    print("  logctl status             Show component status")
    print("  logctl tail [n] [name]    Show recent logs (default 30)")
    print("  logctl errors [n] [name]  Show warnings and errors")
    print("  logctl help               Show this help")
end

if not action or action == "help" or action == "--help" then help() return end
if action == "health" then
    print("Note: 'health' was renamed to 'status'.")
    action = "status"
end
if action ~= "tail" and action ~= "errors" and action ~= "status" then
    printError("Unknown logctl command: " .. tostring(action))
    help()
    return
end

local ok, runtime = pcall(require, "lib.runtime")
if not ok then printError("AttaCC runtime unavailable: " .. tostring(runtime)) return end

local useColor = term.isColor and term.isColor()
local function colored(value, color)
    if useColor then term.setTextColor(color) end
    write(tostring(value))
    if useColor then term.setTextColor(colors.white) end
end

local function stateColor(value)
    value = tostring(value or "unknown"):lower()
    if value == "ready" or value == "running" or value == "online" or value == "ok" then return colors.lime end
    if value == "error" or value == "failed" or value == "offline" then return colors.red end
    if value == "starting" or value == "warning" or value == "warn" or value == "degraded" then return colors.yellow end
    return colors.lightGray
end

if action == "status" then
    local state = runtime.snapshot()
    local names = {}
    for name in pairs(state.entries or {}) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then print("No runtime status entries.") return end
    for _, name in ipairs(names) do
        local entry = state.entries[name]
        colored(name, colors.cyan)
        write(": ")
        colored(entry.status or "unknown", stateColor(entry.status))
        if entry.message and entry.message ~= "" then write("  " .. tostring(entry.message)) end
        print()
    end
    return
end

local limit = math.min(200, math.max(1, tonumber(args[2]) or 30))
local component = args[3]
local entries = runtime.logs(limit, component)
local count = 0
for _, entry in ipairs(entries) do
    if action ~= "errors" or entry.level == "error" or entry.level == "warn" then
        local level = entry.level or "info"
        colored("[" .. tostring(entry.date or "?") .. "] ", colors.lightGray)
        colored(level, level == "error" and colors.red or level == "warn" and colors.yellow or colors.lightBlue)
        print(" " .. tostring(entry.component or "runtime") .. ": " .. tostring(entry.message or ""))
        count = count + 1
    end
end
if count == 0 then print("No matching log entries.") end
