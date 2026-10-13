return {
    -- Examples:
    -- url = "ws://192.168.1.50:8080/ws/machine",
    -- url = "wss://steam.example.com/ws/machine",
    url = "wss://steam.example.com/ws/machine",

    -- Must match MACHINE_TOKEN in web/.env.
    machineToken = "CHANGE_ME",

    retrySeconds = 3,
}
