local M = {}

M.channels = {
    telemetry = 4242,
    pocketStatus = 4243,
    control = 4245,
    ack = 4246,
    events = 4247,
}

M.redstone = {
    mainClutch = "top",
    alternatorClutch = "left",
    genClutch = "right",
}

M.procedure = {
    motorRPM = 64,
    minRPM = 32,
    stableMs = 2000,
    timeoutMs = 45000,
    transferDelayMs = 750,
    autoRestartDelayMs = 1500,
    verifyRunningMs = 8000,
    maxAutoAttempts = 3,
    retryDelayMs = 5000,
}

M.detection = {
    offlineRpm = 0.5,
    offlineCapacity = 1,
    onlineRpm = 16,
    onlineCapacity = 100,
    offlineConfirmMs = 5000,
    recoveryConfirmMs = 2000,
}

M.timing = {
    collectorTick = 0.50,
    masterPushSeconds = 0.50,
    collectorStaleMs = 6000,
    masterTimeoutMs = 12000,
    commandRetryMs = 350,
    commandMaxRetries = 5,
}

M.events = { historySize = 30 }

return M
