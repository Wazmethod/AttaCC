-- AttaCC SDK application launcher and read-only preflight.
local args={...}
local command,id
if args[1]=="check" then
    command="check"
    id=args[2]
else
    command="run"
    id=args[1]
end
if type(id)~="string" or not id:match("^[%w_%-]+$") then
    error("Usage: appctl check <app-id> | appctl <app-id>")
end
local loader=require("lib.app_loader")
local app,err=loader.load(id)
if not app then error("SDK application load failed: "..tostring(err)) end
if type(app)~="table" or app.id~=id or type(app.run)~="function" then
    error("apps/"..id.."/main.lua must return an AttaCC SDK app")
end
if command=="check" then
    print("AttaCC SDK preflight: "..id)
    local deps,missing=app:checkDependencies()
    if not deps then
        printError("Missing SDK dependencies: "..table.concat(missing,", "))
    else
        print("SDK dependencies: OK")
    end
    local status,ready=app:hardwareStatus()
    table.sort(status,function(a,b) return tostring(a.id)<tostring(b.id) end)
    for _,role in ipairs(status) do
        print(("%-22s %s"):format(tostring(role.id),tostring(role.status)))
    end
    if not ready then printError("Required hardware: NOT READY")
    else print("Required hardware: OK") end
    print("No application lifecycle started; no output commands sent.")
    if not deps or not ready then error("SDK preflight failed") end
    return
end
local ok,reason=app:run()
if not ok then error("SDK app stopped: "..tostring(reason)) end
