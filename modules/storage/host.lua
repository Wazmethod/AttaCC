local args = { ... }
local quiet = args[1] == "--quiet"

local config = require("lib.config")
local protocol = require("lib.protocol")
local runtime = require("lib.runtime")
local networkStore = require("lib.network_store")

local modem = protocol.findWirelessModem()
if not modem then error("Wireless modem introuvable") end

local store = networkStore.new(modem, config)

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

local stats = refreshState()
if not quiet then
    print("ATTACC STORAGE")
    print("Backend : " .. tostring(stats.backend or "?"))
    print("State   : " .. (stats.available and "ACTIVE" or "DEGRADED"))
    if stats.file then print("File    : " .. tostring(stats.file)) end
    if stats.error then print("Warning : " .. tostring(stats.error)) end
end

local timer = os.startTimer(1)

while true do
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        store:handle(p2, p4)

    elseif event == "disk" or event == "disk_eject"
        or event == "peripheral" or event == "peripheral_detach"
    then
        local nextStats = refreshState()
        if not quiet then
            term.setCursorPos(1, 4)
            term.clearLine()
            print("State   : " .. (nextStats.available and "ACTIVE" or "DEGRADED"))
            term.clearLine()
            if nextStats.file then print("File    : " .. tostring(nextStats.file))
            elseif nextStats.error then print("Warning : " .. tostring(nextStats.error)) end
        end

    elseif event == "timer" and p1 == timer then
        refreshState()
        timer = os.startTimer(1)
    end
end
