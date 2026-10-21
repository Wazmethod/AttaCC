-- Defaults only. Site bindings are selected using ioctl init -> /etc/io.lua.
-- Overwrite settings in /etc/attacc/apps/elevator/config.lua if required.
return {
    motion={
        reverseForUp=false,  -- set true if a powered Gearshift moves UP
        pollInterval=0.15, -- seconds; temporary 1.0 for motion-disconnected timer diagnosis
        readOnly=false, -- set true during timer tests: reject all movement requests
        settleMs=250,        -- pause between direction change and clutch release
        timeoutSeconds=120, -- modest timeout; prevents endless drive when no arrival
    },
    diagnostics={
        skipInputPolling=false, -- read-only A/B test only; retains boot input snapshot
    },
    display={mode="auto",textScale=0.5}
}
