-- AttaCC disk usage for CraftOS.
-- Shows immediate children of the current directory, including folder totals.
-- Read-only: does not touch files or write temporary data.

local args={...}
local target="."
local exact=false
local summary=false
local chosen=false

local function usage()
    print("Usage: du [path] [-b] [-s]")
    print("  path  directory or file (default: current directory)")
    print("  -b    sizes in exact bytes")
    print("  -s    only show the total")
    print("  -h    show this help")
end

for _,arg in ipairs(args) do
    if arg=="-h" or arg=="--help" then
        usage()
        return
    elseif arg=="-b" or arg=="--bytes" then
        exact=true
    elseif arg=="-s" or arg=="--summary" then
        summary=true
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

local function sizeOf(p)
    if not fs.isDir(p) then return fs.getSize(p) end
    local bytes=0
    for _,name in ipairs(fs.list(p)) do
        bytes=bytes+sizeOf(fs.combine(p,name))
    end
    return bytes
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

if fs.isDir(path) and not summary then
    local entries={}
    for _,name in ipairs(fs.list(path)) do
        local child=fs.combine(path,name)
        entries[#entries+1]={
            name=name..(fs.isDir(child) and "/" or ""),
            bytes=sizeOf(child)
        }
    end
    table.sort(entries,function(a,b)
        if a.bytes==b.bytes then return a.name<b.name end
        return a.bytes>b.bytes
    end)
    for _,entry in ipairs(entries) do
        print(string.format("%9s  %s",displaySize(entry.bytes),entry.name))
    end
end

local total=sizeOf(path)
print(string.format("%9s  %s",displaySize(total),target=="." and "." or target))
local free=fs.getFreeSpace(path)
if type(free)=="number" then
    print("Free: "..displaySize(free))
elseif free~=nil then
    print("Free: "..tostring(free))
end
