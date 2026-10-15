-- Installed SDK I/O declarations, discoverable without starting applications.
-- Packages may ship lib/attacc_requirements_<app-id>.lua returning a roles map.
local M = {}
function M.forApp(app)
    if type(app) ~= "string" or not app:match("^[%w_%-]+$") then return nil,"invalid application id" end
    local path=fs.combine("lib","attacc_requirements_"..app..".lua")
    if not fs.exists(path) then return nil,"requirements not installed for "..app end
    local ok,roles=pcall(dofile,path)
    if not ok or type(roles) ~= "table" then return nil,"invalid requirements for "..app end
    return roles
end
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
