-- AttaCC native startup. No application bypasses the SDK launcher.
local function read(path)
    if not fs.exists(path) then return nil end
    local file=fs.open(path,"r")
    if not file then return nil end
    local raw=file.readAll()
    file.close()
    return raw and raw:match("^%s*(.-)%s*$")
end

local function report(level,message)
    local ok,runtime=pcall(require,"lib.runtime")
    if ok and type(runtime)=="table" then
        if type(runtime.log)=="function" then
            pcall(runtime.log,"startup",level,message)
        end
        if type(runtime.set)=="function" then
            pcall(runtime.set,"startup",level=="error" and "error" or "ready",
                {message=message})
        end
    end
end

-- Run the machine-level SDK agent even on computers with no application preset.
-- It owns runtime system controls; applications are optional consumers.
if fs.exists("node_agent.lua") then
    if shell.openTab then
        local tab=shell.openTab("node_agent.lua")
        if tab and multishell and multishell.setTitle then
            pcall(multishell.setTitle,tab,"node-runtime")
        end
    else
        print("AttaCC node agent requires multishell for unattended startup.")
        print("Run node_agent.lua manually when no application is active.")
    end
end

local preset=read("/etc/preset")
if type(preset)~="string" or not preset:match("^[%w_%-]+$") then
    report("info","No application preset; node runtime remains active")
    print("AttaCC: node runtime only (no application preset)")
    return
end

local ok,settings=pcall(dofile,"/etc/preset_app.lua")
if not ok or type(settings)~="table" or settings.preset~=preset
    or type(settings.sdkApp)~="string"
    or not settings.sdkApp:match("^[%w_%-]+$") then
    report("error","SDK preset configuration invalid")
    printError("AttaCC: invalid SDK preset configuration")
    return
end

local id=settings.sdkApp
if not fs.exists("appctl.lua") or not fs.exists("apps/"..id.."/main.lua") then
    report("error","SDK application files missing: "..id)
    printError("AttaCC: SDK application not installed: "..id)
    return
end

report("info","Starting SDK application: "..id)
-- The preset decides whether the app owns this terminal or a new multishell tab.
-- Old preset configurations retain the previous tab behavior until reactivated.
if settings.launchMode=="current" then
    local success=shell.run("appctl.lua",id)
    if not success then
        report("error","SDK application exited unsuccessfully: "..id)
        printError("AttaCC: SDK application failed: "..id)
    end
elseif shell.openTab then
    local tab=shell.openTab("appctl.lua",id)
    if not tab then
        report("error","Cannot open SDK application tab: "..id)
        printError("AttaCC: SDK application launch failed")
        return
    end
    if multishell and multishell.setTitle then
        pcall(multishell.setTitle,tab,id)
    end
    print("AttaCC SDK: "..id.." started in tab "..tostring(tab))
else
    local success=shell.run("appctl.lua",id)
    if not success then
        report("error","SDK application exited unsuccessfully: "..id)
        printError("AttaCC: SDK application failed: "..id)
    end
end
