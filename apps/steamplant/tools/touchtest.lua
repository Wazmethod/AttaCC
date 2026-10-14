local config = require("lib.config")

local target = ...
local mon = nil
local name = nil

if target and target ~= "" then
    if not peripheral.isPresent(target) or peripheral.getType(target) ~= "monitor" then
        error("Monitor not found: " .. tostring(target))
    end
    mon = peripheral.wrap(target)
    name = target
else
    mon = peripheral.find("monitor")
    if mon then name = peripheral.getName(mon) end
end

if not mon then error("No monitor found") end

pcall(mon.setTextScale, 0.5)
pcall(mon.setGraphicsMode, false)
mon.setBackgroundColor(colors.black)
mon.setTextColor(colors.white)
mon.clear()
mon.setCursorPos(1,1)
mon.write("TOUCH TEST")

print("Monitor: " .. tostring(name))
print("Configured touchProfile: " .. tostring(config.display and config.display.touchProfile or "normal"))
print("Touch LEFT / CENTER / RIGHT. Ctrl+T to stop.")
print("Every received monitor_touch event will be logged below.")

local count = 0
while true do
    local e, side, x, y = os.pullEvent()
    if e == "monitor_touch" and side == name then
        count = count + 1
        print(string.format("%03d  side=%s  x=%s  y=%s", count, tostring(side), tostring(x), tostring(y)))

        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.clear()
        mon.setCursorPos(1,1)
        mon.write("TOUCH #" .. tostring(count))
        mon.setCursorPos(1,2)
        mon.write("x=" .. tostring(x) .. " y=" .. tostring(y))
    end
end
