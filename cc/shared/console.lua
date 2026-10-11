-- CC Infrastructure workstation console launcher
-- Opens a CC: Terminals peripheral in a new multishell tab instead of
-- redirecting the caller's shell.

local args = { ... }
local requested = args[1]

local function terminalType(name)
    if not name or not peripheral.isPresent(name) then return false end
    local types = { peripheral.getType(name) }
    for _, t in ipairs(types) do
        if t == "terminal" then return true end
    end
    return false
end

local function configuredTerminal()
    local ok, config = pcall(require, "lib.config")
    if not ok or type(config) ~= "table" then return nil, true end

    local ws = config.workstation
    local c = ws and ws.console
    if type(c) ~= "table" then return nil, true end
    if c.enabled == false then return nil, false end

    local name = c.peripheral
    if name and name ~= "" and name ~= "auto" then return name, true end
    return nil, true
end

local configured, enabled = configuredTerminal()
if not enabled then
    error("Console disabled by workstation profile")
end

local terminalName = requested
if terminalName and configured and terminalName ~= configured then
    error("Terminal " .. tostring(terminalName)
        .. " does not match profile peripheral " .. tostring(configured))
end

if not terminalName then terminalName = configured end

if terminalName then
    if not peripheral.isPresent(terminalName) then
        error("Configured terminal not present: " .. tostring(terminalName))
    end
    if not terminalType(terminalName) then
        error(tostring(terminalName) .. " is not a CC: Terminals peripheral")
    end
else
    local p = peripheral.find("terminal")
    if p then terminalName = peripheral.getName(p) end
end

if not terminalName then
    error("No CC: Terminals peripheral present")
end

if not shell.openTab then
    error("Multishell is required to launch a non-blocking console")
end

local id = shell.openTab("terminal", terminalName, "shell")
if multishell and multishell.setTitle then
    pcall(multishell.setTitle, id, "console:" .. tostring(terminalName))
end

print("Console opened in tab " .. tostring(id) .. " on " .. tostring(terminalName))
