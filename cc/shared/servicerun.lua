local args = { ... }
local serviceName = args[1] or "unknown"
local binary = args[2]

if not binary or binary == "" then
    error("servicerun: binary required")
end

local okRuntime, runtime = pcall(require, "lib.runtime")

local function log(level, message)
    if okRuntime and runtime and runtime.log then
        runtime.log("service:" .. tostring(serviceName), level, message)
    end
end

local function runBinary()
    log("info", "process start: " .. tostring(binary))
    local ok, err = pcall(function()
        local result = shell.run(binary)
        if result == false then error("binary returned failure") end
    end)
    if not ok then
        log("error", "process failed: " .. tostring(err))
        printError(tostring(err))
    else
        log("info", "process exited: " .. tostring(binary))
    end
end

local function waitForStop()
    while true do
        local event, target = os.pullEventRaw()
        if event == "infra_service_stop" and target == binary then
            log("info", "process stop requested: " .. tostring(binary))
            return
        end
    end
end

parallel.waitForAny(runBinary, waitForStop)
