local config = require("lib.config")
local protocol = require("lib.protocol")
local machineInfo = require("lib.machine")
local nodes = require("lib.nodes")
local runtime = require("lib.runtime")
local bus = require("lib.bus")
local network = require("lib.network")
local devices = require("lib.devices")
local webcap = require("lib.webcap")
local storage = require("lib.storage_client")

local modem = protocol.findWirelessModem()
if not modem then
    runtime.log("app:workstation", "error", "wireless modem unavailable")
    error("Wireless modem unavailable")
end

local machine = machineInfo.get("workstation")
local nodeBus = nodes.new(modem, "workstation")
local net = network.new(config, machine)
local hitboxes = {}
local page = "home"
local consoleTab = nil
local storageTree = nil
local storageError = nil

local function tabAlive(id)
    if not id or not multishell or not multishell.getTitle then return false end
    local ok, title = pcall(multishell.getTitle, id)
    return ok and title ~= nil
end

local function focusTab(id)
    if not id then return end
    if multishell and multishell.setFocus then
        pcall(multishell.setFocus, id)
    elseif shell.switchTab then
        pcall(shell.switchTab, id)
    end
end

local function syncDevices()
    local status = devices.all()
    local item = status.console

    if item.enabled and item.present then
        runtime.set("module:core.console", "active", {
            device = item.name,
            configured = item.configured,
            detail = item.expected .. " peripheral ready",
        })
    elseif item.enabled then
        runtime.set("module:core.console", "inactive", {
            configured = item.configured,
            detail = item.detail,
        })
    else
        runtime.set("module:core.console", "disabled", { detail = "disabled by profile" })
    end

    local displayItem = status.display
    if displayItem.enabled and displayItem.present then
        runtime.set("module:core.display", "active", {
            device = displayItem.name,
            configured = displayItem.configured,
            detail = "display peripheral ready",
        })
    elseif displayItem.enabled then
        runtime.set("module:core.display", "inactive", {
            configured = displayItem.configured,
            detail = displayItem.detail,
        })
    else
        runtime.set("module:core.display", "disabled", { detail = "disabled by profile" })
    end

    return status
end

local status = syncDevices()

local function button(x, y, label, key, action, enabled)
    enabled = enabled ~= false
    term.setCursorPos(x, y)
    term.setBackgroundColor(enabled and colors.gray or colors.black)
    term.setTextColor(enabled and colors.white or colors.lightGray)
    write(" " .. label .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    table.insert(hitboxes, {
        x1 = x,
        x2 = x + #label + 1,
        y = y,
        key = key,
        action = action,
        enabled = enabled,
    })
end

local function header(title)
    hitboxes = {}
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 1)
    term.setTextColor(colors.cyan)
    write("ATTACC WORKSTATION")
    term.setTextColor(colors.gray)
    write("  /  " .. tostring(title))
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    write(tostring(machine.hostname))
    term.setTextColor(colors.gray)
    write("  " .. tostring(machine.network))
    term.setTextColor(colors.white)
end

local function statusLine(y, label, item)
    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    write(string.format("%-8s ", label))
    if item.enabled and item.present then
        term.setTextColor(colors.lime)
        write("ACTIVE")
        term.setTextColor(colors.gray)
        write("  " .. tostring(item.name))
    elseif item.enabled then
        term.setTextColor(colors.orange)
        write(string.upper(tostring(item.state or "inactive")))
        term.setTextColor(colors.gray)
        write("  " .. tostring(item.configured or ""))
    else
        term.setTextColor(colors.gray)
        write("DISABLED")
    end
    term.setTextColor(colors.white)
end

local function drawHome()
    header("HOME")
    statusLine(5, "Console", status.console)
    statusLine(6, "Display", status.display)

    local discovered = nodeBus:list()
    term.setCursorPos(2, 8)
    term.setTextColor(colors.lightGray)
    write("Network  ")
    term.setTextColor(colors.lime)
    write("ACTIVE")
    term.setTextColor(colors.gray)
    write("  " .. tostring(#discovered) .. " node(s)")
    term.setTextColor(colors.white)

    local cfg = require("lib.profile_store").storageConfig()
    local localServer = fs.exists("lib/storage_backend.lua")
    local storageStatus = localServer and "SERVER" or
        (cfg.enabled and cfg.targetMachine and "ACTIVE" or
        (cfg.enabled and "DEGRADED" or "INACTIVE"))
    term.setCursorPos(2, 9)
    term.setTextColor(colors.lightGray)
    write("Storage  ")
    term.setTextColor(storageStatus == "INACTIVE" and colors.gray
        or storageStatus == "DEGRADED" and colors.orange or colors.lime)
    write(storageStatus)
    term.setTextColor(colors.gray)
    if not localServer and cfg.targetMachine then write("  " .. tostring(cfg.targetMachine)) end
    term.setTextColor(colors.white)

    term.setCursorPos(2, 10)
    term.setTextColor(colors.yellow)
    write("TOOLS")
    term.setTextColor(colors.white)

    button(2, 12, "Console", keys.c, "console", status.console and status.console.present)
    button(14, 12, "Nodes", keys.n, "nodes")
    button(24, 12, "Storage", keys.s, "storage")
    button(36, 12, "Refresh", keys.r, "refresh")

    term.setCursorPos(2, 14)
    term.setTextColor(colors.gray)
    write("C/N/S/R  |  click a button")
    term.setTextColor(colors.white)
end

local function drawNodes()
    header("NETWORK NODES")
    local list = nodeBus:list()
    local _, h = term.getSize()
    local y = 5

    if #list == 0 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        write("(no nodes discovered)")
    else
        for _, node in ipairs(list) do
            if y >= h - 2 then break end
            term.setCursorPos(2, y)
            term.setTextColor(node.localNode and colors.lime or colors.white)
            write(tostring(node.hostname or node.key))
            term.setTextColor(colors.gray)
            write("  " .. tostring(node.role or "?") .. "  cc:" .. tostring(node.computerId or "?"))
            if node.conflict then
                term.setTextColor(colors.red)
                write("  IDENTITY CONFLICT")
            end
            y = y + 1
        end
    end

    button(2, h, "Back", keys.b, "home")
    button(12, h, "Refresh", keys.r, "refresh")
end

local function loadStorageTree()
    storageTree = nil
    storageError = nil

    local namespaces, err = storage.namespaces()
    if err then
        storageError = err
        return
    end

    local tree = {}
    for _, namespace in ipairs(namespaces or {}) do
        local keysForNamespace, listErr = storage.list(namespace)
        table.insert(tree, {
            namespace = namespace,
            keys = type(keysForNamespace) == "table" and keysForNamespace or {},
            error = listErr,
        })
    end
    storageTree = tree
end

local function drawStorage()
    header("STORAGE")
    local _, h = term.getSize()
    local y = 5

    if storageError then
        term.setCursorPos(2, y)
        term.setTextColor(colors.red)
        write("ERROR: " .. tostring(storageError))
    elseif not storageTree then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        write("Loading...")
    elseif #storageTree == 0 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        write("(no namespaces)")
    else
        for _, entry in ipairs(storageTree) do
            if y >= h - 2 then break end
            term.setCursorPos(2, y)
            term.setTextColor(colors.yellow)
            write(tostring(entry.namespace) .. "/")
            y = y + 1

            if entry.error then
                term.setCursorPos(4, y)
                term.setTextColor(colors.red)
                write("! " .. tostring(entry.error))
                y = y + 1
            elseif #entry.keys == 0 then
                term.setCursorPos(4, y)
                term.setTextColor(colors.gray)
                write("(empty)")
                y = y + 1
            else
                for _, key in ipairs(entry.keys) do
                    if y >= h - 2 then break end
                    term.setCursorPos(4, y)
                    term.setTextColor(colors.white)
                    write(tostring(key))
                    y = y + 1
                end
            end
        end
    end

    button(2, h, "Back", keys.b, "home")
    button(12, h, "Refresh", keys.r, "refresh")
end

local function redraw()
    if page == "nodes" then
        drawNodes()
    elseif page == "storage" then
        drawStorage()
    else
        drawHome()
    end
end

local function openConsole()
    if not (status.console and status.console.present) then return end

    if tabAlive(consoleTab) then
        focusTab(consoleTab)
        return
    end

    if not shell.openTab then return end
    consoleTab = shell.openTab("terminal", status.console.name, "shell")
    if consoleTab and multishell and multishell.setTitle then
        pcall(multishell.setTitle, consoleTab, "console:" .. tostring(status.console.name))
    end
    focusTab(consoleTab)
end

local function runAction(action)
    if action == "console" then
        openConsole()
    elseif action == "nodes" then
        page = "nodes"
    elseif action == "storage" then
        page = "storage"
        loadStorageTree()
    elseif action == "home" then
        page = "home"
    elseif action == "refresh" then
        status = syncDevices()
        nodeBus:tick()
        if page == "storage" then loadStorageTree() end
    end
end

local function keyAction(key)
    for _, h in ipairs(hitboxes) do
        if h.key == key and h.enabled then
            runAction(h.action)
            return
        end
    end
end

local function mouseAction(x, y)
    for _, h in ipairs(hitboxes) do
        if h.enabled and y == h.y and x >= h.x1 and x <= h.x2 then
            runAction(h.action)
            return
        end
    end
end

runtime.remove("module:workstation.display")
runtime.remove("module:workstation.console")
runtime.set("app:workstation", "active", {
    detail = "AttaCC workstation active",
})
runtime.log("app:workstation", "info",
    "AttaCC workstation online as " .. tostring(machine.hostname))

redraw()
local timer = os.startTimer(1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == bus.EVENT then
        bus.handle(event, p1, p2, p3)

    elseif event == "modem_message" then
        if net then net:handle(p2, p3, p4) end
        local action = nodeBus:handle(p2, p4)
        if action == "reboot" then
            sleep(0.15)
            os.reboot()
        end
        if page == "nodes" then redraw() end

    elseif event == "timer" and p1 == timer then
        nodeBus:tick()
        status = syncDevices()
        webcap.publish("workstation", {
            console = status.console,
            display = status.display,
            hostname = machine.hostname,
            nodes = #nodeBus:list(),
        })
        redraw()
        timer = os.startTimer(1)

    elseif event == "peripheral" or event == "peripheral_detach" then
        runtime.log("workstation", "info", event .. ": " .. tostring(p1))
        status = syncDevices()
        redraw()

    elseif event == "key" then
        keyAction(p1)
        redraw()

    elseif event == "mouse_click" then
        mouseAction(p2, p3)
        redraw()
    end
end
