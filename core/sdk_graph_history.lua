-- Shared short graph history for Master and Pocket.
-- SDK snapshots transmit only the latest sample; clients build the visible trace.
local M={}

function M.ingest(history,graphs,receivedAt)
    history=history or {}
    for _,graph in ipairs(type(graphs)=="table" and graphs or {}) do
        if type(graph)=="table" and type(graph.id)=="string" then
            local samples=type(graph.samples)=="table" and graph.samples or {}
            local latest=samples[#samples]
            local value=type(latest)=="table" and latest.value or nil
            if type(value)=="number" and value==value
                and value~=math.huge and value~=-math.huge then
                local stamp=tonumber(latest.timestamp) or receivedAt
                if type(stamp)=="number" and stamp==stamp then
                    local series=history[graph.id] or {}
                    local previous=series[#series]
                    if not previous or stamp>previous.timestamp then
                        series[#series+1]={timestamp=stamp,value=value}
                    elseif stamp==previous.timestamp then
                        previous.value=value
                    end
                    local window=tonumber(graph.timeWindow)
                    if window and window>0 then
                        local cutoff=(series[#series].timestamp)-(window*1000)
                        while #series>1 and series[1].timestamp<cutoff do
                            table.remove(series,1)
                        end
                    end
                    while #series>120 do table.remove(series,1) end
                    history[graph.id]=series
                end
            end
        end
    end
    return history
end

function M.exports(graphs,history)
    local result={}
    history=history or {}
    for _,graph in ipairs(type(graphs)=="table" and graphs or {}) do
        if type(graph)=="table" and type(graph.id)=="string" then
            local copy={}
            for key,value in pairs(graph) do copy[key]=value end
            copy.samples=history[graph.id] or {}
            result[#result+1]=copy
        end
    end
    return result
end

return M
