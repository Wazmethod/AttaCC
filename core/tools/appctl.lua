-- Interactive SDK config editor. Values are written only to the app override,
-- never to package defaults or /etc/io.lua.
local argv={...}
if argv[1]=="config" then
    local id=argv[2]
    if type(id)~="string" or not id:match("^[%w_%-]+$") then
        error("Usage: appctl config <app-id>")
    end
    local app,err=require("lib.app_loader").load(id)
    if not app then error(tostring(err)) end
    local defaults=app.defaults or {}
    local file="/etc/attacc/apps/"..id.."/config.lua"
    local function readCurrent()
        if not fs.exists(file) then return {} end
        local ok,data=pcall(dofile,file)
        if not ok or type(data)~="table" then
            error("Cannot edit invalid existing configuration: "..file)
        end
        return data
    end
    local function get(root,key)
        local node=root
        for part in key:gmatch("[^%.]+") do
            if type(node)~="table" then return nil end
            node=node[part]
        end
        return node
    end
    local function set(root,key,value)
        local node=root
        local parts={}
        for part in key:gmatch("[^%.]+") do parts[#parts+1]=part end
        for i=1,#parts-1 do
            if type(node[parts[i]])~="table" then node[parts[i]]={} end
            node=node[parts[i]]
        end
        node[parts[#parts]]=value
    end
    local fields={}
    local function enumerate(node,prefix)
        for key,value in pairs(node) do
            if type(key)=="string" and key:match("^[%w_]+$") then
                local name=prefix=="" and key or prefix.."."..key
                if type(value)=="table" then enumerate(value,name)
                elseif type(value)=="number" or type(value)=="boolean" or type(value)=="string" then
                    fields[#fields+1]={key=name,kind=type(value)}
                end
            end
        end
    end
    enumerate(defaults,"")
    local current=readCurrent()
    local known={}
    for _,field in ipairs(fields) do known[field.key]=true end
    local additions={}
    enumerate(current,"")
    for _,field in ipairs(fields) do
        if not known[field.key] then additions[#additions+1]=field;known[field.key]=true end
    end
    fields={}
    enumerate(defaults,"")
    for _,field in ipairs(additions) do fields[#fields+1]=field end
    -- Application display options are SDK-standard even when absent from defaults.
    for _,field in ipairs({
        {key="display.mode",kind="string"},
        {key="display.textScale",kind="number"},
        {key="display.monitorName",kind="string"}
    }) do
        local found=false
        for _,existing in ipairs(fields) do if existing.key==field.key then found=true end end
        if not found then fields[#fields+1]=field end
    end
    table.sort(fields,function(a,b) return a.key<b.key end)
    while true do
        term.clear()
        term.setCursorPos(1,1)
        print("AttaCC config: "..id)
        print("Overrides: "..file)
        for i,field in ipairs(fields) do
            local value=get(current,field.key)
            local suffix=value~=nil and " *" or ""
            if value==nil then value=get(defaults,field.key) end
            if value==nil then value="(unset)" end
            print(("%d. %s = %s%s"):format(i,field.key,tostring(value),suffix))
        end
        print("Choose number, or Q to quit (reboot app to apply):")
        write("> ")
        local answer=read()
        if not answer or answer:lower()=="q" or answer=="" then break end
        local field=fields[tonumber(answer) or -1]
        if field then
            write("New value for "..field.key.." (blank cancels): ")
            local raw=read()
            if raw and raw~="" then
                local value,valid=raw,true
                if field.kind=="number" then value=tonumber(raw);valid=value~=nil
                elseif field.kind=="boolean" then
                    if raw=="true" then value=true
                    elseif raw=="false" then value=false
                    else valid=false end
                elseif field.key=="display.mode" then
                    valid=raw=="auto" or raw=="text" or raw=="graphics"
                elseif field.key=="display.textScale" then
                    valid=tonumber(raw)~=nil and tonumber(raw)>=0.5 and tonumber(raw)<=5
                        and tonumber(raw)*2%1==0
                end
                if not valid then printError("Invalid value");sleep(1.5)
                else
                    if field.key=="commissioning.allowOutputs" and value==true then
                        write("Outputs can actuate hardware. Type ENABLE to confirm: ")
                        if read()~="ENABLE" then valid=false end
                    end
                    if valid then
                        set(current,field.key,value)
                        local parent=fs.getDir(file)
                        if parent~="" and not fs.exists(parent) then fs.makeDir(parent) end
                        local tmp=file..".tmp"
                        local handle=assert(fs.open(tmp,"w"))
                        handle.write("return "..textutils.serialize(current).."\n")
                        handle.close()
                        if fs.exists(file) then fs.delete(file) end
                        fs.move(tmp,file)
                    end
                end
            end
        end
    end
    return
end
-- AttaCC SDK application launcher and read-only preflight.
local args={...}
local command,id
if args[1]=="check" then
    command="check"
    id=args[2]
else
    command="run"
    id=args[1]
end
if type(id)~="string" or not id:match("^[%w_%-]+$") then
    error("Usage: appctl check <app-id> | appctl <app-id>")
end
local loader=require("lib.app_loader")
local app,err=loader.load(id)
if not app then error("SDK application load failed: "..tostring(err)) end
if type(app)~="table" or app.id~=id or type(app.run)~="function" then
    error("apps/"..id.."/main.lua must return an AttaCC SDK app")
end
if command=="check" then
    print("AttaCC SDK preflight: "..id)
    local deps,missing=app:checkDependencies()
    if not deps then
        printError("Missing SDK dependencies: "..table.concat(missing,", "))
    else
        print("SDK dependencies: OK")
    end
    local status,ready=app:hardwareStatus()
    table.sort(status,function(a,b) return tostring(a.id)<tostring(b.id) end)
    for _,role in ipairs(status) do
        print(("%-22s %s"):format(tostring(role.id),tostring(role.status)))
    end
    if not ready then printError("Required hardware: NOT READY")
    else print("Required hardware: OK") end
    print("No application lifecycle started; no output commands sent.")
    if not deps or not ready then error("SDK preflight failed") end
    return
end
local ok,reason=app:run()
if not ok then error("SDK app stopped: "..tostring(reason)) end
