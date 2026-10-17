-- Interactive SDK config editor. Values are written only to the app override,
-- never to package defaults or /etc/io.lua.
local argv={...}
if not argv[1] or argv[1]=="help" or argv[1]=="--help" then
    print("AttaCC appctl")
    print("  appctl <app-id>       Run application")
    print("  appctl check <id>     Check hardware and dependencies")
    print("  appctl config [id]    Interactive app configuration")
    print("  appctl config system  Machine-wide administration policy")
    print("  appctl help           Show this help")
    return
end
if argv[1]=="config" then
    local id=argv[2]
    if not id then
        local ids={}
        if fs.exists("apps") and fs.isDir("apps") then
            for _,candidate in ipairs(fs.list("apps")) do
                if candidate:match("^[%w_%-]+$")
                    and fs.exists(fs.combine("apps/"..candidate,"main.lua")) then
                    ids[#ids+1]=candidate
                end
            end
        end
        table.sort(ids)
        if #ids==1 then id=ids[1]
        elseif #ids>1 then
            print("Select an application:")
            for i,name in ipairs(ids) do print(i..". "..name) end
            write("> ")
            local choice=tonumber(read())
            id=choice and ids[choice] or nil
        end
    end
    if type(id)~="string" or not id:match("^[%w_%-]+$") then
        error("Usage: appctl config <app-id>")
    end
    local app,err
    local isSystem=id=="system"
    if isSystem then
        app={defaults=require("lib.sdk_system_config").defaults()}
    else
        app,err=require("lib.app_loader").load(id)
    end
    if not app then error(tostring(err)) end
    local defaults=app.defaults or {}
    local file=isSystem and "/etc/attacc/system.lua"
        or ("/etc/attacc/apps/"..id.."/config.lua")
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
    -- Legacy app-level admin keys are ignored by the runtime; edit them
    -- exclusively via 'appctl config system' to avoid misleading controls.
    if not isSystem then
        local filtered={}
        for _,field in ipairs(fields) do
            if field.key~="admin" and not field.key:match("^admin%.")
                and not field.key:match("^display%.touch")
                and field.key~="display.monitorName" and field.key~="display.textScale" then
                filtered[#filtered+1]=field
            end
        end
        fields=filtered
    end
    -- Standard application display options are not system administration.
    for _,field in ipairs(isSystem and {} or {
        {key="display.confirmControls",kind="boolean"},
        {key="display.mode",kind="string"},
        {key="display.viewMode",kind="string"}
    }) do
        local found=false
        for _,existing in ipairs(fields) do if existing.key==field.key then found=true end end
        if not found then fields[#fields+1]=field end
    end
    table.sort(fields,function(a,b) return a.key<b.key end)
    local groups={}
    local groupNames={}
    for _,field in ipairs(fields) do
        local group=field.key:match("^([^.]+)") or "general"
        if not groups[group] then
            groups[group]={}
            groupNames[#groupNames+1]=group
        end
        groups[group][#groups[group]+1]=field
    end
    table.sort(groupNames)
    local function pick(items,title)
        local page=1
        while true do
            local _,height=term.getSize()
            local limit=math.max(2,height-6)
            local total=math.max(1,math.ceil(#items/limit))
            page=math.max(1,math.min(total,page))
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1,1)
            print(title.."  ["..page.."/"..total.."]")
            print("N: next  P: previous  Q: back")
            local first=(page-1)*limit+1
            local last=math.min(#items,first+limit-1)
            for i=first,last do
                local item=items[i]
                local name=item.key or item
                local value=item.key and get(current,item.key)
                if value==nil and item.key then value=get(defaults,item.key) end
                local suffix=item.key and (" = "..tostring(value==nil and "(unset)" or value)) or ""
                print(tostring(i)..". "..name..suffix)
            end
            write("> ")
            local answer=read()
            if not answer then return nil end
            answer=answer:lower()
            if answer=="q" or answer=="" then return nil
            elseif answer=="n" then page=page+1
            elseif answer=="p" then page=page-1
            else
                local index=tonumber(answer)
                if index and items[index] then return items[index] end
            end
        end
    end
    local possible={
        ["admin.enabled"]="true or false; enables remote SDK administration for this machine",
        ["admin.actions.reboot"]="true or false; permits signed node reboot",
        ["display.confirmControls"]="true or false; double-tap remote actions (reboot always confirmed)",
        ["display.mode"]="auto, text, graphics",
        ["display.viewMode"]="views, exports",
        ["display.touchProfile"]="normal, angled3, angled3_swap, mirror_x",
        ["display.textScale"]="0.5 to 5 in steps of 0.5",
        ["display.touchFlipX"]="true, false",
        ["display.touchFlipY"]="true, false",
        ["display.touchInsetX"]="0 to 40 pixels inward (horizontal)",
        ["display.touchInsetY"]="0 to 20 pixels inward (vertical)",
        ["commissioning.allowOutputs"]="true, false (physical outputs)"
    }
    while true do
        local category=pick(groupNames,"AttaCC config / "..id)
        if not category then break end
        local chosen=pick(groups[category],"Config / "..id.." / "..category)
        if chosen then
            term.clear()
            term.setCursorPos(1,1)
            local allowed=possible[chosen.key]
            print("Setting: "..chosen.key)
            print("Current: "..tostring((function() local v=get(current,chosen.key); if v==nil then v=get(defaults,chosen.key) end; if v==nil then return "(unset)" end;return v end)()))
            if allowed then print("Allowed: "..allowed) end
            if chosen.kind=="boolean" then
                print("1. Enabled (true)")
                print("2. Disabled (false)")
                print("Enter 1 or 2 (blank cancels)")
            end
            write("New value (blank cancels): ")
            local raw=read()
            if raw and raw~="" then
                local value,valid=raw,true
                if chosen.kind=="number" then value=tonumber(raw);valid=value~=nil
                elseif chosen.kind=="boolean" then
                    if raw=="true" or raw=="1" or raw=="y" or raw=="yes" then value=true
                    elseif raw=="false" or raw=="2" or raw=="n" or raw=="no" then value=false
                    else valid=false end
                elseif chosen.key=="display.touchProfile" then
                    valid=raw=="normal" or raw=="angled3" or raw=="angled3_swap" or raw=="mirror_x"
                elseif chosen.key=="display.mode" then
                    valid=raw=="auto" or raw=="text" or raw=="graphics"
                elseif chosen.key=="display.viewMode" then
                    valid=raw=="views" or raw=="exports"
                end
                if (chosen.key=="display.touchInsetX" or chosen.key=="display.touchInsetY") and valid then
                    valid=value>=0 and value<=40 and value%1==0
                end
                if chosen.key=="display.textScale" and valid then
                    valid=value>=0.5 and value<=5 and value*2%1==0
                end
                if not valid then
                    printError("Invalid value")
                    sleep(1.5)
                else
                    if chosen.key=="commissioning.allowOutputs" and value==true then
                        write("Type ENABLE to confirm output activation: ")
                        if read()~="ENABLE" then valid=false end
                    end
                    if valid then
                        set(current,chosen.key,value)
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
