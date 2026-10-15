-- Generic wire representation of an AttaCC SDK application.
-- Descriptor remains authoritative; ui compatibility is generated centrally.
local M={}
function M.frame(descriptor,machine,network,timestamp)
    if type(descriptor)~="table" or descriptor.schema~="attacc.sdk.app.v1"
        or type(descriptor.id)~="string" or descriptor.id=="" then return nil,"invalid SDK descriptor" end
    if type(machine)~="string" or machine=="" then return nil,"machine identity required" end
    if type(network)~="string" or network=="" then return nil,"network required" end
    local safe={schema=descriptor.schema,id=descriptor.id,title=descriptor.title,data={},graphs={},controls={}}
    for i,item in ipairs(descriptor.data or {}) do
        if i>64 then break end
        safe.data[#safe.data+1]={id=item.id,label=item.label,unit=item.unit,value=item.value}
    end
    for i,item in ipairs(descriptor.graphs or {}) do
        if i>64 then break end
        local samples=item.samples or {}
        safe.graphs[#safe.graphs+1]={id=item.id,label=item.label,unit=item.unit,
            samples=#samples>0 and {samples[#samples]} or {}}
    end
    for i,item in ipairs(descriptor.controls or {}) do
        if i>64 then break end
        safe.controls[#safe.controls+1]={id=item.id,label=item.label,enabled=item.enabled,
            confirm=item.confirm,remote=item.remote}
    end
    return {type="attacc.sdk.snapshot.v1",schema=descriptor.schema,
        module=descriptor.id,machine=machine,network=network,
        timestamp=timestamp or os.epoch("utc"),descriptor=safe}
end
function M.compat(frame)
    if type(frame)~="table" or frame.type~="attacc.sdk.snapshot.v1"
        or type(frame.descriptor)~="table" or frame.descriptor.schema~="attacc.sdk.app.v1"
        or type(frame.machine)~="string" or type(frame.network)~="string" then
        return nil,"invalid SDK snapshot"
    end
    local d=frame.descriptor
    if type(d.id)~="string" or d.id=="" then return nil,"invalid app id" end
    local metrics,graphs,controls={},{},{}
    local values={}
    for _,item in ipairs(type(d.data)=="table" and d.data or {}) do
        if type(item)=="table" and type(item.id)=="string" then
            metrics[#metrics+1]={id=item.id,label=item.label or item.id,
                value=item.value,unit=item.unit}
            values[item.id]=item.value
        end
    end
    for _,item in ipairs(type(d.graphs)=="table" and d.graphs or {}) do
        if type(item)=="table" and type(item.id)=="string" then
            local recent=type(item.samples)=="table" and item.samples[#item.samples] or nil
            graphs[#graphs+1]={id=item.id,label=item.label or item.id,
                value=values[item.id] or (recent and recent.value),unit=item.unit}
        end
    end
    for _,item in ipairs(type(d.controls)=="table" and d.controls or {}) do
        if type(item)=="table" and item.remote==true and item.enabled~=false then
            controls[#controls+1]={command=item.id,label=item.label or item.id,
                confirm=item.confirm==true}
        end
    end
    return {
        type="module_telemetry",module=d.id,machine=frame.machine,
        network=frame.network,timestamp=frame.timestamp,
        sdk=frame,
        ui={kind="controller",app={id=d.id,module=d.id,machine=frame.machine,
            title=d.title or d.id,kind="machine"},
            title=d.title or d.id,metrics=metrics,graphs=graphs,
            controls=controls,categories={data={{id="general",title="Data",order=1}},
                graphs={{id="general",title="Graphs",order=1}},
                controls={{id="general",title="Controls",order=1}}}},
    }
end
return M
