-- Generic wire representation of an AttaCC SDK application.
-- Descriptor remains authoritative; ui compatibility is generated centrally.
local M={}
-- Telemetry wire precision is presentation-oriented; application calculations
-- and local control logic retain their original numeric values.
local function wireNumber(value)
    if type(value)~="number" then return value end
    if value~=value or value==math.huge or value==-math.huge then return nil end
    if value>=0 then return math.floor(value*100+0.5)/100 end
    return math.ceil(value*100-0.5)/100
end
function M.frame(descriptor,machine,network,timestamp)
    if type(descriptor)~="table" or descriptor.schema~="attacc.sdk.app.v1"
        or type(descriptor.id)~="string" or descriptor.id=="" then return nil,"invalid SDK descriptor" end
    if type(machine)~="string" or machine=="" then return nil,"machine identity required" end
    if type(network)~="string" or network=="" then return nil,"network required" end
    local safe={schema=descriptor.schema,id=descriptor.id,title=descriptor.title,data={},graphs={},controls={},views={}}
    -- Never silently omit exported declarations. Keep wire bounds but publish
    -- the number of omitted entries so clients can diagnose incomplete views.
    local limits={data=64,graphs=64,controls=64,views=16}
    local truncated={}
    for kind,limit in pairs(limits) do
        local entries=descriptor[kind]
        if entries~=nil and type(entries)~="table" then
            return nil,"invalid SDK export: "..kind
        end
        if entries and #entries>limit then
            truncated[kind]={total=#entries,exported=limit,omitted=#entries-limit}
        end
    end
    -- Reject malformed entries instead of crashing partway through a snapshot.
    for kind,limit in pairs(limits) do
        local entries=descriptor[kind] or {}
        for i=1,math.min(#entries,limit) do
            local item=entries[i]
            if type(item)~="table" or type(item.id)~="string"
                or item.id=="" then
                return nil,"invalid SDK "..kind.." export at index "..tostring(i)
            end
        end
    end
    if next(truncated) then safe.exportWarnings={truncated=truncated} end
    for i,item in ipairs(descriptor.data or {}) do
        if i>64 then break end
        safe.data[#safe.data+1]={id=item.id,label=item.label,unit=item.unit,value=wireNumber(item.value),category=item.category,
            trueLabel=item.trueLabel,falseLabel=item.falseLabel}
    end
    for i,item in ipairs(descriptor.graphs or {}) do
        if i>64 then break end
        local samples=type(item.samples)=="table" and item.samples or {}
        local recent=samples[#samples]
        if type(recent)~="table" then recent=nil end
        safe.graphs[#safe.graphs+1]={id=item.id,label=item.label,unit=item.unit,category=item.category,
            min=item.min,max=item.max,resolution=item.resolution,timeWindow=item.timeWindow,
            samples=recent and {{timestamp=recent.timestamp,
                value=wireNumber(recent.value)}} or {}}
    end
    for i,item in ipairs(descriptor.views or {}) do
        if i>16 then break end
        safe.views[#safe.views+1]={id=item.id,label=item.label,layout=item.layout,
            data=item.data,controls=item.controls,graphs=item.graphs}
    end
    for i,item in ipairs(descriptor.controls or {}) do
        if i>64 then break end
        safe.controls[#safe.controls+1]={id=item.id,label=item.label,enabled=item.enabled,
            confirm=item.confirm,remote=item.remote,category=item.category,
            state=item.state,trueLabel=item.trueLabel,falseLabel=item.falseLabel,
            trueControl=item.trueControl,falseControl=item.falseControl,
            uiHidden=item.uiHidden==true,toggle=item.toggle==true}
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
    if frame.machine=="" or frame.network=="" then
        return nil,"invalid snapshot identity"
    end
    for _,kind in ipairs({"data","graphs","controls","views"}) do
        if d[kind]~=nil and type(d[kind])~="table" then
            return nil,"invalid snapshot "..kind
        end
    end
    local metrics,graphs,controls={},{},{}
    local values={}
    for _,item in ipairs(type(d.data)=="table" and d.data or {}) do
        if type(item)=="table" and type(item.id)=="string" then
            metrics[#metrics+1]={id=item.id,label=item.label or item.id,
                value=item.value,unit=item.unit,category=item.category}
            values[item.id]=item.value
        end
    end
    for _,item in ipairs(type(d.graphs)=="table" and d.graphs or {}) do
        if type(item)=="table" and type(item.id)=="string" then
            local recent=type(item.samples)=="table" and item.samples[#item.samples] or nil
            graphs[#graphs+1]={id=item.id,label=item.label or item.id,
                value=values[item.id],unit=item.unit,category=item.category}
            if values[item.id]==nil then graphs[#graphs].value=recent and recent.value end
        end
    end
    for _,item in ipairs(type(d.controls)=="table" and d.controls or {}) do
        if type(item)=="table" and item.remote==true and item.enabled~=false
            and item.uiHidden~=true then
            controls[#controls+1]={command=item.id,label=item.label or item.id,
                confirm=item.confirm==true,category=item.category,
                state=item.state,toggle=item.toggle==true,
                trueLabel=item.trueLabel,falseLabel=item.falseLabel}
        end
    end
    local categories={data={},graphs={},controls={}}
    for _,kind in ipairs({"data","graphs","controls"}) do
        local seen={}
        local items=kind=="data" and metrics or kind=="graphs" and graphs or controls
        for _,item in ipairs(items) do
            local name=type(item.category)=="string" and item.category~=""
                and item.category or "general"
            if not seen[name] then
                seen[name]=true
                categories[kind][#categories[kind]+1]={
                    id=name,title=name,order=#categories[kind]+1
                }
            end
        end
    end
    return {
        type="module_telemetry",module=d.id,machine=frame.machine,
        network=frame.network,timestamp=frame.timestamp,
        sdk=frame,exportWarnings=d.exportWarnings,
        ui={kind="controller",app={id=d.id,module=d.id,machine=frame.machine,
            title=d.title or d.id,kind="machine"},
            title=d.title or d.id,metrics=metrics,graphs=graphs,
            controls=controls,categories=categories},
    }
end
return M
