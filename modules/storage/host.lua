local args = { ... }
local quiet = args[1] == "--quiet"

local config = require("lib.config")
local protocol = require("lib.protocol")
local runtime = require("lib.runtime")
local networkStore = require("lib.network_store")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local store = networkStore.new(modem, config)
local hitboxes = {}

local function refreshState()
    local stats = store:stats()
    local state = stats.available and "active" or "degraded"
    runtime.set("module:network.storage", state, {
        backend = stats.backend,
        drive = stats.drive,
        diskId = stats.diskId,
        file = stats.file,
        detail = stats.error or (
            tostring(stats.backend or "?") .. " backend, "
            .. tostring(stats.namespaces or 0) .. " namespace(s), "
            .. tostring(stats.keys or 0) .. " key(s)"
        ),
    })
    return stats
end

local function button(x,y,label,action)
    term.setCursorPos(x,y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    write(" "..label.." ")
    term.setBackgroundColor(colors.black)
    table.insert(hitboxes,{
        x1=x,x2=x+#label+1,y=y,action=action
    })
end

local function draw()
    if quiet then return end
    local stats=refreshState()
    hitboxes={}

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(2,1)
    term.setTextColor(colors.cyan)
    write("ATTACC STORAGE")

    term.setCursorPos(2,3)
    term.setTextColor(colors.lightGray)
    write("Backend    ")
    term.setTextColor(colors.white)
    write(tostring(stats.backend or "?"))

    term.setCursorPos(2,4)
    term.setTextColor(colors.lightGray)
    write("State      ")
    term.setTextColor(stats.available and colors.lime or colors.orange)
    write(stats.available and "ACTIVE" or "DEGRADED")

    term.setCursorPos(2,5)
    term.setTextColor(colors.lightGray)
    write("Namespaces ")
    term.setTextColor(colors.white)
    write(tostring(stats.namespaces or 0))

    term.setCursorPos(2,6)
    term.setTextColor(colors.lightGray)
    write("Keys       ")
    term.setTextColor(colors.white)
    write(tostring(stats.keys or 0).." / "..tostring(stats.maxKeys or "?"))

    term.setCursorPos(2,7)
    term.setTextColor(colors.lightGray)
    write("File       ")
    term.setTextColor(colors.white)
    write(tostring(stats.file or "-"))

    if stats.drive then
        term.setCursorPos(2,8)
        term.setTextColor(colors.lightGray)
        write("Drive      ")
        term.setTextColor(colors.white)
        write(tostring(stats.drive))
    end

    if stats.error then
        term.setCursorPos(2,10)
        term.setTextColor(colors.orange)
        write("WARN  "..tostring(stats.error):sub(1,60))
    end

    term.setCursorPos(2,12)
    term.setTextColor(colors.yellow)
    write("MAINTENANCE")

    button(2,14,"Tree","tree")
    button(11,14,"Check","check")
    button(21,14,"Backup","backup")
    button(32,14,"Config","config")
    button(43,14,"Refresh","refresh")

    term.setTextColor(colors.white)
end

local function launchTool(...)
    local argv={...}
    if multishell and multishell.launch then
        local env={}
        setmetatable(env,{__index=_ENV})
        local id=multishell.launch(env,"storagectl.lua",table.unpack(argv))
        if id and multishell.setTitle then
            pcall(multishell.setTitle,id,"storage-"..tostring(argv[1] or "tool"))
        end
        if id and multishell.setFocus then pcall(multishell.setFocus,id) end
        return
    end
    shell.run("storagectl.lua",table.unpack(argv))
end

local function action(name)
    if name=="tree" then launchTool("tree")
    elseif name=="check" then launchTool("check")
    elseif name=="backup" then launchTool("backup")
    elseif name=="config" then
        if shell.openTab then
            local id=shell.openTab("storagectl.lua","configure")
            if id and multishell and multishell.setTitle then
                pcall(multishell.setTitle,id,"storage-config")
            end
            if id and multishell and multishell.setFocus then pcall(multishell.setFocus,id) end
        else
            shell.run("storagectl.lua","configure")
        end
    elseif name=="refresh" then
        draw()
    end
end

local stats=refreshState()
if not quiet then draw() end

local timer=os.startTimer(1)

while true do
    local event,p1,p2,p3,p4=os.pullEvent()

    if event=="modem_message" then
        store:handle(p2,p4)

    elseif event=="disk" or event=="disk_eject"
        or event=="peripheral" or event=="peripheral_detach"
    then
        refreshState()
        draw()

    elseif event=="mouse_click" and not quiet then
        for _,box in ipairs(hitboxes) do
            if p3==box.y and p2>=box.x1 and p2<=box.x2 then
                action(box.action)
                break
            end
        end

    elseif event=="key" and not quiet then
        if p1==keys.r then action("refresh")
        elseif p1==keys.t then action("tree")
        elseif p1==keys.c then action("check")
        elseif p1==keys.b then action("backup")
        end

    elseif event=="timer" and p1==timer then
        refreshState()
        draw()
        timer=os.startTimer(1)
    end
end
