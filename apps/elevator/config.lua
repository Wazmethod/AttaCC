-- Small set of site options. Hardware bindings stay in /etc/io.lua.
return {
    motion={
        pollInterval=0.5,   -- Basic Bridge reads five inputs twice a second
        settleMs=250,      -- Gearshift settling before releasing the Clutch (ms)
        reverseForUp=false,
        timeoutSeconds=120,
        readOnly=false,    -- Set true to test buttons without motor commands
    },
    debug=false,           -- Show poll counter/age on the CC maintenance screen
    display={mode="auto",textScale=0.5},
}
