-- AttaCC / CraftOS: filesystem hosting the current directory.
-- Read-only; no options and no file traversal.

if select("#",...)>0 then
    print("Usage: df")
    return
end

local cwd=shell.resolve(".")

local function size(bytes)
    if bytes<1024 then return tostring(bytes).." B" end
    local units={"KiB","MiB","GiB","TiB"}
    local i=1
    repeat
        bytes=bytes/1024
        if bytes<1024 or i==#units then break end
        i=i+1
    until false
    return string.format("%.1f %s",bytes,units[i])
end

local function mountOf(path)
    while true do
        local ok,isRoot=pcall(fs.isDriveRoot,path)
        if ok and isRoot then
            return path=="" and "/" or ("/"..path:gsub("^/",""))
        end
        local parent=fs.getDir(path)
        if not parent or parent==path or parent=="" then return "/" end
        path=parent
    end
end

local driveOk,drive=pcall(fs.getDrive,cwd)
local capacityOk,capacity=false,nil
if type(fs.getCapacity)=="function" then
    capacityOk,capacity=pcall(fs.getCapacity,cwd)
end
local freeOk,free=pcall(fs.getFreeSpace,cwd)
local readonlyOk,readonly=pcall(fs.isReadOnly,cwd)

print("-- Filesystem --")
print("Drive: "..(driveOk and tostring(drive or "unknown") or "unknown"))
print("Mount: "..mountOf(cwd))
if readonlyOk and readonly then print("Mode: read-only") end
if capacityOk and type(capacity)=="number" and capacity>0 then
    print("Capacity: "..size(capacity))
else
    print("Capacity: N/A")
end
if freeOk and type(free)=="number" then
    if capacityOk and type(capacity)=="number" and capacity>0 then
        local used=math.max(0,capacity-free)
        print("Used: "..size(used)..
            string.format(" (%.1f%%)",math.min(100,used/capacity*100)))
    else
        print("Used: N/A")
    end
    print("Free: "..size(free))
else
    print("Used: N/A")
    print("Free: "..(freeOk and tostring(free or "N/A") or "N/A"))
end
