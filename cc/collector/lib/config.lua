local M = {}

M.machine = {
    role = "collector",
    name = "steam-collector",
    label = "STEAM COLLECTOR",
    modules = { "steamplant.collector" },
    tags = { "infra", "steamplant" },
}

M.channels = {
    telemetry = 4242,
    pocketStatus = 4243,
    control = 4245,
    ack = 4246,
    events = 4247,
    nodeControl = 4248,
    nodeAck = 4249,
    nodeStatus = 4250,
    moduleControl = 4251,
    moduleAck = 4252,
    moduleData = 4253,
    moduleEvents = 4254,
}

M.redstone = {
    mainClutch = "top",
    alternatorClutch = "left",
    genClutch = "right",
}

-- Fallback used only when no persisted output state exists yet.
-- Values are logical clutch states, not raw redstone levels.
M.bootState = {
    main = "engaged",
    alternator = "engaged",
    gen = "cut",
    motorRPM = 0,
}

M.procedure = {
    motorRPM = 64,
    minRPM = 32,
    stableMs = 2000,
    timeoutMs = 45000,
    transferDelayMs = 750,

    -- After a confirmed outage, ARMED auto-restart waits this long
    -- before launching the exact same startup procedure.
    autoRestartDelayMs = 1500,

    -- Once the mechanical transfer is complete, the boiler must physically
    -- reach RUNNING telemetry inside this window.
    verifyRunningMs = 8000,

    -- Automatic restart retries for one outage.
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
    -- 2 Hz is more than enough for this dashboard and avoids hammering
    -- CC:C Bridge/Create peripherals.
    collectorTick = 0.50,

    -- Master -> Pocket behaves as a continuous status stream.
    masterPushSeconds = 0.50,

    -- Do not call telemetry stale on a brief peripheral hiccup.
    collectorStaleMs = 6000,
    masterTimeoutMs = 12000,

    commandRetryMs = 350,
    commandMaxRetries = 5,
}

M.events = {
    historySize = 30,
}

return M
