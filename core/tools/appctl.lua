-- AttaCC SDK app launcher. Only SDK-native entries can run here.
local args={...}
local id=args[1]
if not id or not id:match("^[%w_%-]+$") then
    print("Usage: appctl <app-id>")
    return
end
local loader=require("lib.app_loader")
local app,err=loader.load(id)
if not app then error("SDK application load failed: "..tostring(err)) end
if type(app)~="table" or app.id~=id or type(app.run)~="function" then
    error("apps/"..id.."/main.lua must return an AttaCC SDK app")
end
local ok,reason=app:run()
if not ok then error("SDK app stopped: "..tostring(reason)) end
