-- SteamPlant SDK configuration defaults. Hardware bindings belong to /etc/io.lua.
-- Override deployment configuration through SDK facilities, not application code.
return {
    display={viewMode="views",textSummary=true},
    motor={direction=1},
    sensors={rpm={multiplier=-1}},
    bootState={main="engaged",alternator="engaged",gen="cut",motorRPM=0},
    procedure={
        motorRPM=64,minRPM=32,stableMs=2000,timeoutMs=45000,
        transferDelayMs=750,autoRestartDelayMs=1500,verifyRunningMs=8000,
        maxAutoAttempts=3,retryDelayMs=5000,
    },
    detection={
        offlineRpm=0.5,offlineCapacity=1,onlineRpm=16,onlineCapacity=100,
        offlineConfirmMs=5000,recoveryConfirmMs=2000,
    },
}
