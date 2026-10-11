-- SteamPlant CC installer/updater
-- Repository: Wazmethod/steamplant-cc
-- Works with public repositories, or private repositories with a fine-grained
-- GitHub token having read-only Contents access to this repository.

local OWNER = "Wazmethod"
local REPO = "steamplant-cc"
local REF = "main"

local roles = {
    collector = {
        "main.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/controller.lua",
        "lib/io.lua",
        "lib/protocol.lua",
        "lib/telemetry.lua",
    },
    master = {
        "main.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/protocol.lua",
        "lib/ui.lua",
        "webbridge.lua",
        "web.example.lua",
    },
    pocket = {
        "main.lua",
        "startup.lua",
        "lib/config.lua",
        "lib/protocol.lua",
        "lib/ui.lua",
    },
}

local idDefaults = {
    [0] = "collector",
    [1] = "master",
    [2] = "pocket",
}

local function urlencodePath(path)
    -- Our repository paths only contain URL-safe characters at present.
    return path
end

local function headers(token)
    local h = {
        ["Accept"] = "application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["User-Agent"] = "CC-Tweaked-SteamPlant",
    }
    if token and token ~= "" then
        h["Authorization"] = "Bearer " .. token
    end
    return h
end

local function fetchFile(repoPath, token)
    local url
    local requestHeaders = nil

    -- Public repository: use raw.githubusercontent.com instead of the GitHub
    -- Contents API. This avoids burning the unauthenticated API rate limit
    -- (60 requests/hour per public IP) every time the installer downloads files.
    if not token or token == "" then
        url = "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO
            .. "/" .. REF .. "/" .. urlencodePath(repoPath)
    else
        -- Keep authenticated API support in case the repository becomes private.
        url = "https://api.github.com/repos/" .. OWNER .. "/" .. REPO
            .. "/contents/" .. urlencodePath(repoPath) .. "?ref=" .. REF
        requestHeaders = headers(token)
    end

    local response, err = http.get(url, requestHeaders)
    if not response then
        return nil, err or "HTTP request failed"
    end

    local code = response.getResponseCode()
    local body = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return nil, "GitHub HTTP " .. tostring(code) .. ": " .. tostring(body)
    end

    return body
end

local function chooseRole()
    local default = idDefaults[os.getComputerID()]
    print("Computer ID: " .. tostring(os.getComputerID()))
    if default then
        print("Role suggested: " .. default)
        write("Use this role? [Y/n] ")
        local answer = read()
        if answer == "" or answer:lower() == "y" or answer:lower() == "yes" then
            return default
        end
    end

    print("Select role:")
    print("  1) collector")
    print("  2) master")
    print("  3) pocket")
    write("> ")
    local answer = read()
    if answer == "1" then return "collector" end
    if answer == "2" then return "master" end
    if answer == "3" then return "pocket" end
    error("Invalid role")
end

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function writeFile(path, content)
    ensureParent(path)
    local tmp = path .. ".new"
    local f = fs.open(tmp, "w")
    if not f then error("Cannot open " .. tmp) end
    f.write(content)
    f.close()

    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
end

if not http then
    error("HTTP API unavailable. Enable HTTP in CC:Tweaked configuration.")
end

term.clear()
term.setCursorPos(1, 1)
print("SteamPlant installer")
print("====================")

local role = chooseRole()
print("")
print("Public repository: no GitHub token is required.")
print("Leave token blank (recommended).")
print("Only enter a fine-grained READ token if the repository is private.")
write("Token [blank]: ")
local token = read("*")

print("")
print("Installing role: " .. role)

for _, rel in ipairs(roles[role]) do
    local source = "cc/" .. role .. "/" .. rel
    write("- " .. rel .. " ... ")
    local body, err = fetchFile(source, token)
    if not body then
        print("FAILED")
        error(err)
    end
    writeFile(rel, body)
    print("OK")
end

local versionBody = fetchFile("version.json", token)
if versionBody then
    writeFile(".steamplant-version.json", versionBody)
end

print("")
print("Installation complete.")
print("Role: " .. role)
print("Run: reboot")
