-- AttaCC SDK v1.1 preview: an elevator UI descriptor (no hardware needed).
local attacc = require("lib.attacc")
local app = attacc.app("elevator", { title = "Elevator" })
local floor = 1
local moving = false

app:data("floor", {label = "Current floor", read = function() return floor end})
app:data("moving", {label = "Moving", read = function() return moving end})
for n = 1, 3 do
    app:control("floor_" .. n, {
        label = "Go to " .. n,
        run = function()
            moving = true
            floor = n
            moving = false
            app:log("info", "Arrived at floor " .. n)
            app:publish()
        end
    })
end
app:view("main", {
    label = "Lift control", data = {"floor", "moving"},
    controls = {"floor_1", "floor_2", "floor_3"}
})

local ok, err = app:publish()
if not ok then printError(err) end
app:status("ready", "Elevator simulator ready")
print("AttaCC elevator demo: 1/2/3 = floor; q = quit")
while true do
    local event, key, a, b = os.pullEvent()
    if event == "key" then
        if key == keys.q then break end
        if key == keys.one then app:invoke("floor_1") end
        if key == keys.two then app:invoke("floor_2") end
        if key == keys.three then app:invoke("floor_3") end
    else
        app:handle(event, key, a, b)
    end
end
app:close()
