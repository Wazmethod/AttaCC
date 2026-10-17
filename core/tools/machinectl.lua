-- Compatibility alias. Machine operations now live in systemctl.
print("machinectl is deprecated; use systemctl.")
return shell.run("systemctl.lua", ...)
