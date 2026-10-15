-- AttaCC SDK v1.1 preview: an elevator UI descriptor (no hardware needed).
local attacc = require("lib.attacc")
local app = attacc.app("elevator", { title = "Elevator" })
local floor = 1
local moving = false
local history = 0
app:graph("floor_history", {label="Floor history", unit="floor", limit=60})

app:data("floor", {label = "Current floor", read = function() return floor end})
app:data("moving", {label = "Moving", read = function() return moving end})
for n = 1, 3 do
    app:control("floor_" .. n, {
        label = "Go to " .. n,
        run = function()
            moving = true
            floor = n
            moving = false
            history = history + 1
            app:sample("floor_history", floor)
            app:log("info", "Arrived at floor " .. n)
            app:publish()
        end
    })
end
app:io("main_screen", { type = "monitor", required = false, label = "Elevator display" })
app:view("main", {
    label = "Lift control",
    minWidth = 18,
    minHeight = 7,
    children = {
        { type = "page", id = "home", label = "Overview", children = {
            { type = "section", label = "Current state", children = {
                { type = "data", id = "floor" }, { type = "data", id = "moving" }
            }},
            { type = "section", label = "Floor selection", children = {
                { type = "control", id = "floor_1" },
                { type = "control", id = "floor_2" },
                { type = "control", id = "floor_3" }
            }}
        }},
        { type = "page", id = "diagnostics", label = "Diagnostics", children = {
            { type = "data", id = "floor" }, { type = "data", id = "moving" },
            { type = "graph", id = "floor_history" }
        }}
    }
})

local ok, err = app:publish()
if not ok then printError(err) end
app:status("ready", "Elevator simulator ready")
local monitor = peripheral.find("monitor")
local target = monitor or term.current()
local result
local function redraw()
    result = app:draw(target, { view = "main" })
end
redraw()
print("Elevator: 1/2/3 floors, arrows = pages, q = exit")
while true do
    local event, key, a, b = os.pullEvent()
    if event == "key" then
        if key == keys.q then break end
        if key == keys.right then app.displayPage = math.min(result and result.pageCount or 1, (app.displayPage or 1)+1) end
        if key == keys.left then app.displayPage = math.max(1,(app.displayPage or 1)-1) end
        if key == keys.one then app:invoke("floor_1") end
        if key == keys.two then app:invoke("floor_2") end
        if key == keys.three then app:invoke("floor_3") end
        redraw()
    elseif event == "monitor_touch" and monitor and key == peripheral.getName(monitor) then
        app:touch(result, a, b)
        redraw()
    elseif event == "term_resize" or event == "monitor_resize" then
        redraw()
    else
        app:handle(event, key, a, b)
    end
end
app:close()
