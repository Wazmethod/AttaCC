local function runMaster()
    shell.run("main.lua")
end

local function runWebBridge()
    shell.run("webbridge.lua")
end

if fs.exists("web.local.lua") then
    parallel.waitForAny(runMaster, runWebBridge)
else
    runMaster()
end
