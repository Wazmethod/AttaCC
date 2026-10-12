local okRuntime, runtime = pcall(require, "lib.runtime")

if not multishell then
    print("PID  PROGRAM")
    print("1    " .. tostring(shell.getRunningProgram() or "shell"))
    return
end

local current = multishell.getCurrent and multishell.getCurrent() or nil
local focus = multishell.getFocus and multishell.getFocus() or nil
local byPid = {}

if okRuntime and runtime then
    local snap = runtime.snapshot()
    for key, entry in pairs(snap.services or {}) do
        local service = key:match("^service:(.+)$")
        local pid = entry and tonumber(entry.pid)
        if service and pid then
            byPid[pid] = byPid[pid] or {}
            table.insert(byPid[pid], service .. ".service")
        end
    end
    for _, names in pairs(byPid) do table.sort(names) end
end

print(string.format("%-4s %-1s %-1s %-18s %s", "PID", "C", "F", "PROGRAM", "SERVICES"))
for id = 1, multishell.getCount() do
    local title = multishell.getTitle(id) or ("tab-" .. tostring(id))
    local services = byPid[id] and table.concat(byPid[id], ",") or "-"
    print(string.format("%-4d %-1s %-1s %-18s %s",
        id,
        id == current and "*" or " ",
        id == focus and ">" or " ",
        tostring(title),
        services))
end
