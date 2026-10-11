-- CC Infrastructure external monitor console
local args = { ... }

local requested = args[1]
local scale = tonumber(args[2]) or 0.5

if scale < 0.5 then scale = 0.5 end
if scale > 5 then scale = 5 end

local monitor
local monitorName

if requested and requested ~= "" then
    if not peripheral.isPresent(requested) then
        error("Peripheral not found: " .. tostring(requested))
    end
    if peripheral.getType(requested) ~= "monitor" then
        error(tostring(requested) .. " is not a monitor")
    end
    monitor = peripheral.wrap(requested)
    monitorName = requested
else
    monitor = peripheral.find("monitor")
    if monitor then monitorName = peripheral.getName(monitor) end
end

if not monitor then
    error("No monitor found. Usage: console [monitor] [text-scale]")
end

pcall(function()
    if monitor.setGraphicsMode then monitor.setGraphicsMode(false) end
end)

if monitor.setTextScale then
    local ok, err = pcall(monitor.setTextScale, scale)
    if not ok then error("Unable to set monitor scale: " .. tostring(err)) end
end

local old = term.current()
local oldBlink = false
pcall(function() oldBlink = old.getCursorBlink() end)

local function restore()
    term.redirect(old)
    pcall(old.setCursorBlink, oldBlink)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

term.redirect(monitor)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

local w, h = term.getSize()
print("CC Infrastructure console")
print("Monitor : " .. tostring(monitorName))
print("Size    : " .. tostring(w) .. "x" .. tostring(h))
print("Scale   : " .. tostring(scale))
print("Type 'exit' to return to the computer terminal.")
print("")

local ok, err = pcall(function()
    shell.run("shell")
end)

restore()

if not ok then
    error(err)
end

print("External console closed: " .. tostring(monitorName))
