-- Static hardware contract: available to ioctl before SteamPlant starts.
-- Method-level logical bindings are configured by ioctl or /etc/io.lua.
return {
    target = {type="create_target", required=true, description="Create Target control interface"},
    speedometer = {type="Create_Speedometer", required=true, description="Rotational speed sensor"},
    stressometer = {type="Create_Stressometer", required=true, description="Mechanical stress sensor"},
    motor = {type="electric_motor", required=true, direction="output", description="Generator electric motor"},
    accumulator = {type="modular_accumulator", required=true, description="Energy accumulator"},
    main_clutch = {type="redstone",required=true,direction="output",description="Main clutch output"},
    alternator_clutch = {type="redstone",required=true,direction="output",description="Alternator clutch output"},
    gen_clutch = {type="redstone",required=true,direction="output",description="Generator clutch output"},
    redstoneRelay = {type="redstone_relay", required=false, description="Optional redstone relay"},
}
