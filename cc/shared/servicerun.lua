local args = { ... }

local binary = args[1]
local serviceCsv = args[2] or ""

-- Backward compatibility with the previous servicerun <service> <binary> form.
if binary and not tostring(binary):match("%.lua$") and args[2] and tostring(args[2]):match("%.lua$") then
    local oldService = binary
    binary = args[2]
    serviceCsv = oldService
end

if not binary or binary == "" then
    error("servicerun: binary required")
end

local services = {}
for name in tostring(serviceCsv):gmatch("[^,]+") do
    if name ~= "" then table.insert(services, name) end
end
if #services == 0 then table.insert(services, "unknown") end

local okRuntime, runtime = pcall(require, "lib.runtime")
local stopped = false
local finished = false
local failed = false
local failure = nil

local function forServices(fn)
    for _, name in ipairs(services) do fn(name) end
end

local function log(level, message)
    if okRuntime and runtime and runtime.log then
        forServices(function(name)
            runtime.log("service:" .. tostring(name), level, message)
        end)
    end
end

local function state(status, detail)
    if not (okRuntime and runtime and runtime.set) then return end
    local pid = multishell and multishell.getCurrent and multishell.getCurrent() or nil
    forServices(function(name)
        runtime.set("service:" .. tostring(name), status, {
            detail = detail,
            binary = binary,
            process = true,
            pid = pid,
            services = services,
        })
    end)
end

local function runBinary()
    state("active", "process running: " .. tostring(binary))
    log("info", "process start: " .. tostring(binary))

    local ok, err = pcall(function()
        local result = shell.run(binary)
        if result == false then error("binary returned failure") end
    end)

    finished = true
    if not ok then
        failed = true
        failure = tostring(err)
        state("failed", failure)
        log("error", "process failed: " .. failure)
        printError(failure)
    else
        state("exited", "process exited: " .. tostring(binary))
        log("info", "process exited: " .. tostring(binary))
    end
end

local function heartbeat()
    while not finished and not stopped do
        state("active", "process running: " .. tostring(binary))
        sleep(0.5)
    end
end

local function waitForStop()
    while true do
        local event, target = os.pullEventRaw()
        if event == "infra_service_stop"
            and (target == binary or target == "*" or target == nil)
        then
            stopped = true
            state("stopping", "stop requested")
            log("info", "process stop requested: " .. tostring(binary))
            return
        end
    end
end

parallel.waitForAny(runBinary, heartbeat, waitForStop)

if stopped and not failed then
    state("inactive", "process stopped")
end
