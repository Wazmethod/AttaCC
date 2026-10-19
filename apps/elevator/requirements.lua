-- Logical signals, independent from CC sides and Create Redstone Link frequencies.
-- Configure physical sides/relays with ioctl init: elevator.<role>.
return {
    call_top={type="redstone",direction="input",required=true,
        description="TOP floor call (Create Redstone Link receiver)"},
    call_bottom={type="redstone",direction="input",required=true,
        description="BOTTOM floor call (Create Redstone Link receiver)"},
    call_cabin={type="redstone",direction="input",required=true,
        description="CABIN toggle call (works when the carriage is stationary)"},
    at_top={type="redstone",direction="input",required=true,
        description="TOP fixed Create Redstone Contact, paired with carriage contact"},
    at_bottom={type="redstone",direction="input",required=true,
        description="BOTTOM fixed Create Redstone Contact, paired with carriage contact"},
    clutch={type="redstone",direction="output",required=true,readOutput=true,
        description="Create Clutch: powered = stop, unpowered = move"},
    gearshift={type="redstone",direction="output",required=true,readOutput=true,
        description="Create Gearshift: powered = reverse"}
}
