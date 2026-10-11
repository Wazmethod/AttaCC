-- CC Infrastructure pager
local args = { ... }

local function usage()
    print("Usage: less <file>")
    print("       less -n <file>")
    print("")
    print("Keys: Up/Down, PgUp/PgDn, Home/End, / search, n next, q quit")
end

local showNumbers = false
local path = nil
for _, arg in ipairs(args) do
    if arg == "-n" or arg == "--line-numbers" then
        showNumbers = true
    elseif not path then
        path = arg
    end
end

if not path then
    usage()
    return
end

if not fs.exists(path) then error(path .. ": no such file") end
if fs.isDir(path) then error(path .. ": is a directory") end

local h = fs.open(path, "r")
if not h then error("cannot open " .. path) end

local lines = {}
while true do
    local line = h.readLine()
    if line == nil then break end
    table.insert(lines, line)
end
h.close()

local width, height = term.getSize()
local contentHeight = math.max(1, height - 1)
local top = 1
local search = nil
local lastMatch = nil

local function clamp()
    local maxTop = math.max(1, #lines - contentHeight + 1)
    if top < 1 then top = 1 end
    if top > maxTop then top = maxTop end
end

local function visibleText(index)
    local prefix = ""
    if showNumbers then
        local digits = #tostring(math.max(1, #lines))
        prefix = string.format("%" .. tostring(digits) .. "d ", index)
    end
    local text = prefix .. (lines[index] or "")
    if #text > width then text = text:sub(1, width) end
    return text
end

local function draw(status)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    for row = 1, contentHeight do
        local index = top + row - 1
        if index > #lines then break end
        term.setCursorPos(1, row)
        term.write(visibleText(index))
    end

    term.setCursorPos(1, height)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    local percent = #lines == 0 and 100 or math.floor(math.min(100, ((top + contentHeight - 1) / #lines) * 100))
    local footer = status or (path .. "  " .. tostring(top) .. "/" .. tostring(math.max(1,#lines)) .. "  " .. tostring(percent) .. "%")
    term.write(footer:sub(1, width))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function findNext(pattern, start)
    if not pattern or pattern == "" then return nil end
    local needle = pattern:lower()
    for i = math.max(1, start or 1), #lines do
        if (lines[i] or ""):lower():find(needle, 1, true) then return i end
    end
    return nil
end

if #lines == 0 then
    draw(path .. " (empty)")
else
    draw()
end

while true do
    local event, p1 = os.pullEvent()

    if event == "key" then
        if p1 == keys.q then
            break
        elseif p1 == keys.up or p1 == keys.k then
            top = top - 1
        elseif p1 == keys.down or p1 == keys.j then
            top = top + 1
        elseif p1 == keys.pageUp then
            top = top - contentHeight
        elseif p1 == keys.pageDown or p1 == keys.space then
            top = top + contentHeight
        elseif p1 == keys.home or p1 == keys.g then
            top = 1
        elseif p1 == keys["end"] then
            top = #lines
        elseif p1 == keys.n and search then
            local match = findNext(search, (lastMatch or top) + 1)
            if not match then match = findNext(search, 1) end
            if match then
                lastMatch = match
                top = match
            end
        elseif p1 == keys.slash then
            term.setCursorPos(1, height)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clearLine()
            write("/")
            search = read()
            lastMatch = findNext(search, top)
            if lastMatch then top = lastMatch end
        end
        clamp()
        draw()
    elseif event == "term_resize" then
        width, height = term.getSize()
        contentHeight = math.max(1, height - 1)
        clamp()
        draw()
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
