-- Static Pocket network identity snapshot, captured once at startup.
local M = {}
local snapshot = nil

function M.capture(machine)
    if snapshot then return snapshot end
    machine = machine or {}
    snapshot = {
        network = tostring(machine.network or "default"),
        hostname = tostring(machine.hostname or machine.name or "pocket"),
        key = tostring(machine.key or ("cc:" .. tostring(os.getComputerID()))),
        computerId = os.getComputerID(),
        role = tostring(machine.role or "pocket"),
    }
    return snapshot
end

function M.get()
    return snapshot or M.capture()
end

function M.print()
    local state = M.get()
    print("ATTACC POCKET / BOOT NETWORK")
    print("Host    : " .. state.hostname)
    print("Network : " .. state.network)
    print("Key     : " .. state.key)
    print("CC ID   : " .. tostring(state.computerId))
end

return M
