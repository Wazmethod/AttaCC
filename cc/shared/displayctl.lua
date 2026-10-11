local display = require("lib.display_api")
local args = { ... }
local cmd = args[1] or "status"

if cmd == "status" then
    local s = display.status()
    print("Published : " .. tostring(s.published))
    print("Owner     : " .. tostring(s.owner or "(none)"))
    print("Updated   : " .. tostring(s.updatedAt or "(never)"))
    if s.descriptor then print(textutils.serialize(s.descriptor)) end
    return
end

if cmd == "clear" then
    local ok, err = display.clear(args[2])
    if not ok then error(err) end
    print("Display publication cleared.")
    return
end

if cmd == "demo" then
    display.publish("displayctl", {
        title = "CC INFRA DISPLAY",
        subtitle = "display module API",
        lines = {
            "Display is driven by a published descriptor.",
            "Business modules can replace this view.",
            "Use displayctl clear to return to fallback.",
        },
    })
    print("Demo view published.")
    return
end

print("displayctl status")
print("displayctl demo")
print("displayctl clear [owner]")
