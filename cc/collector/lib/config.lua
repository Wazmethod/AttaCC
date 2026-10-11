local M = {}

M.machine = {
    role = "collector",
    name = "steam-collector",
    label = "STEAM COLLECTOR",
    modules = { "steamplant.collector", "collector.display" },
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

M.localDisplay = {
    enabled = true,

    -- nil: use the first attached/networked monitor.
    -- Set an exact peripheral name when several collector displays exist.
    monitorName = nil,
}

M.display = {
    -- "text"       : reliable CC:Tweaked monitor mode (recommended for angled monitors)
    -- "auto"       : CC:Graphics when available, otherwise text
    -- "ccgraphics" : require CC:Graphics
    preferred = "text",
    graphicsMode = 1,

    -- Force 0.5 before graphics-mode geometry is read.
    forceTextScale = true,
    textScale = 0.5,

    -- "normal"   : standard flat Advanced Monitor
    -- "angled3"  : 1x3 angled monitor; outer wing X axes are mirrored
    -- "mirror_x" : mirror the whole touch surface
    touchProfile = "angled3",

    -- Native text-mode pages shown as a compact side menu.
    textPages = {
        "control",
        "data",
        "logs",
    },

    -- Allow switching from text mode to the CC:Graphics dashboard.
    -- The return-to-text button is intentionally placed in the centre segment
    -- so it remains usable on angled monitors where graphics touch only works
    -- reliably in the centre.
    graphicsToggle = true,

    -- Tabs are ordered. Remove any entry you do not want on the graphics interface.
    -- Valid values: dashboard, graphs, events, machines, debug
    tabs = {
        "dashboard",
        "graphs",
        "events",
        -- "machines",
        -- "debug",
    },

    -- Event filtering is local to this interface only.
    eventFilter = {
        -- nil/empty table = allow every value for that field.
        levels = {
            critical = true,
            warning = true,
            success = true,
            info = true,
        },

        -- Examples: module_event, plant_event.
        -- Leave empty to accept all event types.
        types = {},

        -- Optional exact event-code filter, for example:
        -- codes = { COLLECT_ERROR = true, AUTO_START = true }
        codes = {},
    },
}

M.redstone = {
    -- auto: use a redstone_relay when one is available, otherwise direct computer redstone.
    -- relay: require a CC:Tweaked Redstone Relay.
    -- direct: force the built-in redstone API.
    mode = "auto",

    -- Optional peripheral name when several relays exist on the wired network,
    -- for example "redstone_relay_0". Leave nil to use the first relay found.
    relayName = nil,

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
