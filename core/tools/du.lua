-- AttaCC disk usage for CraftOS.
-- Shows immediate children of the current directory, including folder totals.
-- Read-only: does not touch files or write temporary data.

local args={...}
local target="."
local exact=false
local summary=false
local filesystemOnly=false
local chosen=false

local function usage()
    print("Usage: du [path] [-b] [-s] [--df]")
    print("  path  directory or file (default: current directory)")
    print("  -h    human-readable sizes (default)")
    print("  -b    sizes in exact bytes")
    print("  -s    only show the directory total and filesystem")
    print("  --df  only show the containing filesystem (no file scan)")
    print("  --help show this help")
end

for _,arg in ipairs(args) do
    if arg=="--help" then
        usage()
        return
    elseif arg=="-h" or arg=="--human-readable" then
        exact=false
    elseif arg=="-b" or arg=="--bytes" then
        exact=true
    elseif arg=="-s" or arg=="--summary" then
        summary=true
    elseif arg=="--df" then
        filesystemOnly=true
    elseif arg:sub(1,1)=="-" then
        printError("du: unknown option "..arg)
        usage()
        return
    elseif chosen then
        printError("du: only one path is supported")
        usage()
        return
    else
        target=arg
        chosen=true
    end
end

local path=shell.resolve(target)
if not fs.exists(path) then
    printError("du: no such file or directory: "..target)
    return
end

-- Mod-provided ROM mounts can advertise entries that are not readable
-- through fs.getSize(). Keep scanning and explicitly mark partial totals.
local skipped=0
local examples={}
local function unreadable(p,err)
    skipped=skipped+1
    if #examples<3 then
        examples[#examples+1]=tostring(p)..": "..tostring(err)
    end
end

local function sizeOf(p)
    local ok,isDir=pcall(fs.isDir,p)
    if not ok then
        unreadable(p,isDir)
        return 0,false,false
    end
    if not isDir then
        local found,bytes=pcall(fs.getSize,p)
        if not found or type(bytes)~="number" then
            unreadable(p,found and "size unavailable" or bytes)
            return 0,false,false
        end
        return bytes,true,false
    end
    local listed,children=pcall(fs.list,p)
    if not listed or type(children)~="table" then
        unreadable(p,listed and "cannot list directory" or children)
        return 0,false,true
    end
    local total,complete=0,true
    for _,name in ipairs(children) do
        local bytes,valid=sizeOf(fs.combine(p,name))
        total=total+bytes
        if not valid then complete=false end
    end
    return total,complete,true
end

local function displaySize(bytes)
    if exact then return tostring(bytes).." B" end
    if bytes<1024 then return tostring(bytes).." B" end
    local units={"KiB","MiB","GiB","TiB"}
    local n=bytes
    local unit=1
    repeat
        n=n/1024
        if n>=1024 and unit<#units then unit=unit+1
        else break end
    until false
    return string.format("%.1f %s",n,units[unit])
end

-- Resolve the mount which owns the selected file/directory, not the
-- computer's default HDD. Nested mounts are supported by isDriveRoot().
local function mountPoint(p)
    local current=p
    while true do
        local ok,isRoot=pcall(fs.isDriveRoot,current)
        if ok and isRoot then return current end
        local parent=fs.getDir(current)
        if not parent or parent==current or parent=="" then return "/" end
        current=parent
    end
end

local function showFilesystem(p)
    local okDrive,drive=pcall(fs.getDrive,p)
    local okCap,capacity=false,nil
    if type(fs.getCapacity)=="function" then
        okCap,capacity=pcall(fs.getCapacity,p)
    end
    local okFree,free=pcall(fs.getFreeSpace,p)
    local okRead,readOnly=pcall(fs.isReadOnly,p)
    print("-- Filesystem --")
    print("Drive: "..(okDrive and tostring(drive or "unknown") or "unknown"))
    print("Mount: "..mountPoint(p))
    if okRead and readOnly then print("Mode: read-only") end
    if okCap and type(capacity)=="number" and capacity>0 then
        print("Capacity: "..displaySize(capacity))
    else
        print("Capacity: N/A")
    end
    if okFree and type(free)=="number" then
        if okCap and type(capacity)=="number" and capacity>0 then
            local used=math.max(0,capacity-free)
            local pct=math.min(100,math.max(0,used/capacity*100))
            print("Used: "..displaySize(used)..
                string.format(" (%.1f%%)",pct))
        else
            print("Used: N/A")
        end
        print("Free: "..displaySize(free))
    elseif okFree and free=="unlimited" then
        print("Used: N/A")
        print("Free: unlimited")
    else
        print("Used: N/A")
        print("Free: N/A")
    end
end

if filesystemOnly then
    showFilesystem(path)
    return
end

local total,complete=0,true
local directory=fs.isDir(path)
if directory and not summary then
    local listed,children=pcall(fs.list,path)
    if not listed or type(children)~="table" then
        printError("du: cannot list "..target..": "..tostring(children))
        return
    end
    local entries={}
    for _,name in ipairs(children) do
        local child=fs.combine(path,name)
        local bytes,valid,isDir=sizeOf(child)
        total=total+bytes
        if not valid then complete=false end
        entries[#entries+1]={
            name=name..(isDir and "/" or "")..(valid and "" or "*"),
            bytes=bytes
        }
    end
    table.sort(entries,function(a,b)
        if a.bytes==b.bytes then return a.name<b.name end
        return a.bytes>b.bytes
    end)
    for _,entry in ipairs(entries) do
        print(string.format("%9s  %s",displaySize(entry.bytes),entry.name))
    end
else
    total,complete=sizeOf(path)
end
print(string.format("%9s  %s%s",displaySize(total),
    target=="." and "." or target,complete and "" or "*"))
if skipped>0 then
    printError("du: "..skipped.." unreadable entry/entries skipped (* = partial total)")
    for _,example in ipairs(examples) do printError("  "..example) end
end
showFilesystem(path)
