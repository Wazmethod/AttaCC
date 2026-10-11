local config = require("lib.config")

local M = {}

local function hasType(name, expected)
    if not name or not peripheral.isPresent(name) then return false end
    local types = { peripheral.getType(name) }
    for _, t in ipairs(types) do
        if t == expected then return true end
    end
    return false
end

local function resolve(section, expected)
    section = type(section) == "table" and section or {}
    if section.enabled == false then
        return { enabled = false, present = false, state = "disabled" }
    end

    local configured = section.peripheral
    if configured and configured ~= "" and configured ~= "auto" then
        if not peripheral.isPresent(configured) then
            return {
                enabled = true, present = false, state = "missing",
                configured = configured, expected = expected,
                detail = "configured peripheral is not present",
            }
        end
        if not hasType(configured, expected) then
            return {
                enabled = true, present = false, state = "mismatch",
                configured = configured, expected = expected,
                detail = "configured peripheral has the wrong type",
            }
        end
        return {
            enabled = true, present = true, state = "active",
            configured = configured, name = configured, expected = expected,
        }
    end

    local p = peripheral.find(expected)
    if not p then
        return {
            enabled = true, present = false, state = "missing",
            configured = "auto", expected = expected,
            detail = "no matching peripheral present",
        }
    end

    return {
        enabled = true, present = true, state = "active",
        configured = "auto", name = peripheral.getName(p), expected = expected,
    }
end

function M.console()
    return resolve(config.workstation and config.workstation.console, "terminal")
end

function M.display()
    return resolve(config.workstation and config.workstation.display, "monitor")
end

function M.all()
    return { console = M.console(), display = M.display() }
end

return M
