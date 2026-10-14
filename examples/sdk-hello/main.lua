-- AttaCC SDK example: no modem or peripheral required.
local runtime = require("lib.runtime")
local bus = require("lib.bus")

local counter = 0
runtime.set("example", "ready", { message = "Example app started" })
runtime.log("example", "info", "App started")

local listener = bus.on("example.ping", function(payload)
    counter = counter + 1
    print("Ping #" .. counter .. ": " .. tostring(payload.message))
    runtime.log("example", "info", "Ping " .. counter)
end)

print("AttaCC SDK example")
print("Press P to send an event, Q to quit.")
while true do
    local event, key, p2, p3, p4 = os.pullEvent()
    if event == "key" then
        if key == keys.q then break end
        if key == keys.p then
            bus.emit("example.ping", { message = "Hello from CraftOS" })
        end
    else
        bus.handle(event, key, p2, p3)
    end
end

bus.off(listener)
runtime.set("example", "stopped", { message = "Exited normally" })
runtime.log("example", "info", "App stopped")
