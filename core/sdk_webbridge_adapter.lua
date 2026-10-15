-- Pure WebBridge wire adapter. No modem, CraftOS loop or WebSocket ownership.
local M={}
local function networkOf(frame,default)
    return frame.network or default
end
function M.snapshot(frame)
    local compat=require("lib.sdk_snapshot").compat(frame)
    if not compat then return nil end
    return {type="sdk_snapshot",network=frame.network,
        module=frame.module,machine=frame.machine,
        descriptor=frame.descriptor,data=compat,timestamp=frame.timestamp}
end
function M.modem(channel,message,channels,network)
    if type(message)~="table" then return nil end
    channels=channels or {}
    if (channel==(channels.telemetry or 4242) or channel==(channels.moduleData or 4253))
        and message.type=="module_telemetry" then
        return {type="telemetry",network=networkOf(message,network),
            module=message.module,machine=message.machine,data=message,
            timestamp=os.epoch("utc")}
    end
    if (channel==(channels.events or 4247) or channel==(channels.moduleEvents or 4254))
        and (message.type=="module_event" or message.type=="plant_event") then
        return {type="event",network=networkOf(message,network),
            module=message.module or "steamplant",machine=message.machine,
            level=message.level,code=message.code,message=message.message,
            timestamp=message.timestamp or os.epoch("utc")}
    end
    if channel==(channels.nodeStatus or 4250) and message.type=="node_status" then
        return {type="node_status",key=message.key,role=message.role,
            preset=message.preset or message.role,computerId=message.computerId,
            hostname=message.hostname or message.name,name=message.name,
            label=message.label,apps=message.apps or {},modules=message.modules,
            capabilities=message.capabilities or {},tags=message.tags,
            network=networkOf(message,network),runtime=message.runtime or {},
            system=message.system,physicalIdentity=message.physicalIdentity,
            timestamp=message.timestamp or os.epoch("utc")}
    end
    return nil
end
return M
