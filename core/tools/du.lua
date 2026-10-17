-- AttaCC / CraftOS: disk usage of the current directory.
-- Read-only; no options. Dirs are counted recursively, like a small du.

if select("#",...)>0 then
    print("Usage: du")
    return
end

local cwd=shell.resolve(".")
local skipped=0

local function sizeOf(path)
    local ok,isDir=pcall(fs.isDir,path)
    if not ok then skipped=skipped+1;return 0,false,false end
    if not isDir then
        local valid,bytes=pcall(fs.getSize,path)
        if not valid or type(bytes)~="number" then
            skipped=skipped+1
            return 0,false,false
        end
        return bytes,true,false
    end
    local listed,files=pcall(fs.list,path)
    if not listed or type(files)~="table" then
        skipped=skipped+1
        return 0,false,true
    end
    local total,complete=0,true
    for _,name in ipairs(files) do
        local bytes,good=sizeOf(fs.combine(path,name))
        total=total+bytes
        if not good then complete=false end
    end
    return total,complete,true
end

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

local ok,items=pcall(fs.list,cwd)
if not ok or type(items)~="table" then
    printError("du: cannot read current directory")
    return
end

local entries,total,complete={},0,true
for _,name in ipairs(items) do
    local bytes,valid,isDir=sizeOf(fs.combine(cwd,name))
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
    print(string.format("%9s  %s",size(entry.bytes),entry.name))
end
print(string.format("%9s  .%s",size(total),complete and "" or "*"))
if skipped>0 then
    printError("du: "..skipped.." unreadable file(s), * = partial size")
end
