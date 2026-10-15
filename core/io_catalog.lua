-- Installed SDK I/O declarations, discoverable without starting applications.
-- Packages may ship lib/attacc_requirements_<app-id>.lua returning a roles map.
local M = {}
function M.all()
    local out = {}
    if not fs.exists("lib") then return out end
    for _, file in ipairs(fs.list("lib")) do
        local app = file:match("^attacc_requirements_([%w_%-]+)%.lua$")
        if app then
            local ok, roles = pcall(dofile, fs.combine("lib", file))
            if ok and type(roles) == "table" then
                for id, spec in pairs(roles) do
                    if type(id) == "string" and type(spec) == "table"
                        and type(spec.type) == "string" and spec.type ~= "" then
                        out[app .. "." .. id] = spec
                    end
                end
            end
        end
    end
    return out
end
return M
