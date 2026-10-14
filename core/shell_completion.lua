-- AttaCC shell completion, limited to native command syntax.
local M = {}
local cmds = {
    profilectl = {"info","show","machines","init","config","push","pull","edit","reset","storage-sync"},
    storagectl = {"init","hosts","use","target","ping","ns","tree","list","get","set","delete"},
    storagehostctl = {"status","configure","backup","migrate"},
    pkgctl = {"list","status","show","deps","install","configure","update","upgrade","prune"},
    ioctl = {"init","check","hardware","bind","list","show","read","write"},
    webbridgectl = {"configure"},
    machinectl = {"status","init","hostname","export","import","reset"},
}
local subcommands = {
    ["profilectl config"] = {"inter","list","show","set","unset","remote"},
    ["profilectl config remote"] = {"inter"},
    ["storagehostctl migrate"] = {"local","drive"},
}
local function completions(partial, options)
    local out = {}
    for _, option in ipairs(options) do
        if option:sub(1,#partial) == partial then
            out[#out+1] = option:sub(#partial+1) .. " "
        end
    end
    return out
end
local function words(line)
    local out = {}
    for item in tostring(line or ""):gmatch("%S+") do out[#out+1] = item end
    return out
end
function M.complete(program, _, current, previous)
    local context = words(previous)
    local prefix = program
    for _,item in ipairs(context) do prefix = prefix .. " " .. item end
    return completions(current or "", subcommands[prefix] or (#context==0 and cmds[program] or {}))
end
function M.install()
    if not shell or type(shell.setCompletionFunction) ~= "function" then
        return false, "Shell completion API unavailable"
    end
    for program in pairs(cmds) do
        for _,path in ipairs({program,program..".lua"}) do
            if fs.exists(path) then
                shell.setCompletionFunction(path,function(shellArg,index,text,previous)
                    return M.complete(program,index,text,previous)
                end)
            end
        end
    end
    return true
end
return M
