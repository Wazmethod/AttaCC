-- Defaults only. Site bindings are selected using ioctl init -> /etc/io.lua.
-- Overwrite settings in /etc/attacc/apps/elevator/config.lua if required.
return {
    motion={
        reverseForUp=false,  -- set true if a powered Gearshift moves UP
        settleMs=250,        -- pause between direction change and clutch release
        timeoutSeconds=120, -- modest timeout; prevents endless drive when no arrival
    },
    display={mode="auto",textScale=0.5}
}
