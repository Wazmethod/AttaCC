-- CC Infrastructure process view (multishell tabs)
if not multishell then
    print("PID  PROGRAM")
    print("1    " .. tostring(shell.getRunningProgram() or "shell"))
    return
end

local current = multishell.getCurrent and multishell.getCurrent() or nil
local focus = multishell.getFocus and multishell.getFocus() or nil

print(string.format("%-4s %-1s %-1s %s", "PID", "C", "F", "PROGRAM"))
for id = 1, multishell.getCount() do
    local title = multishell.getTitle(id) or ("tab-" .. tostring(id))
    print(string.format("%-4d %-1s %-1s %s",
        id,
        id == current and "*" or " ",
        id == focus and ">" or " ",
        tostring(title)))
end
