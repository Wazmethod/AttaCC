-- CC Infrastructure cat
local args = { ... }

if #args == 0 then
    print("Usage: cat <file> [file ...]")
    return
end

for i, path in ipairs(args) do
    if not fs.exists(path) then
        printError("cat: " .. tostring(path) .. ": no such file")
    elseif fs.isDir(path) then
        printError("cat: " .. tostring(path) .. ": is a directory")
    else
        local h = fs.open(path, "r")
        if not h then
            printError("cat: " .. tostring(path) .. ": cannot open")
        else
            local data = h.readAll() or ""
            h.close()
            write(data)
            if data ~= "" and data:sub(-1) ~= "\n" then print() end
        end
    end
end
