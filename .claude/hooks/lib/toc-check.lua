-- toc-check.lua ROOT: reads the repo's tracked + untracked *.lua / *.xml / *.toc paths on stdin
-- (relative to ROOT) and prints the load-order problems, nothing when all is well:
--   - a file a top-level toc lists does not exist;
--   - a Lua file under an entry of make-release.ps1's $includes is loaded by no toc and no xml.
-- Embedded libs/ folders are skipped. Paths compare case-insensitively, like the game.
-- Vendored from Ciaanh/wow-dev (repo-slice/); edit it there and sync, not here.
local root = (arg[1] or "."):gsub("\\", "/"):gsub("/+$", "")

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- "a/b/../c.lua" -> "a/c.lua"
local function clean(path)
    local out = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then out[#out] = nil elseif part ~= "." then out[#out + 1] = part end
    end
    return table.concat(out, "/")
end

local paths, tocs, xmls = {}, {}, {}
for line in io.lines() do
    local p = line:gsub("\r$", "")
    if p ~= "" then
        paths[#paths + 1] = p
        if p:match("%.toc$") and not p:find("/") then tocs[#tocs + 1] = p end
        if p:match("%.xml$") then xmls[#xmls + 1] = p end
    end
end

local loaded, problems = {}, {}

for _, toc in ipairs(tocs) do
    local text = read(root .. "/" .. toc) or ""
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local entry = line:match("^%s*([^#%s].-)%s*$")
        if entry then
            entry = clean(entry)
            loaded[entry:lower()] = true
            if not read(root .. "/" .. entry) then
                problems[#problems + 1] = ("  %s lists %s, which does not exist"):format(toc, entry)
            end
        end
    end
end

for _, xml in ipairs(xmls) do
    local base = xml:match("^(.*)/[^/]*$")
    for ref in (read(root .. "/" .. xml) or ""):gmatch('file%s*=%s*"([^"]+)"') do
        loaded[clean((base and (base .. "/") or "") .. ref):lower()] = true
    end
end

-- make-release.ps1's $includes: the top-level files and folders that ship.
local includes
local script = read(root .. "/make-release.ps1")
local list = script and script:match("%$includes%s*=%s*@%((.-)%)")
if list then
    includes = {}
    for entry in list:gmatch('"([^"]+)"') do includes[entry:lower()] = true end
end

-- A file that is never loaded on purpose says so in its first lines: a LuaLS "---@meta" file, or a
-- "toc-check: skip" comment (a local test rig, say).
local function optedOut(p)
    local head = (read(root .. "/" .. p) or ""):sub(1, 400)
    return head:find("---@meta", 1, true) or head:find("toc-check: skip", 1, true)
end

if includes then
    for _, p in ipairs(paths) do
        local lower = p:lower()
        local top = lower:match("^([^/]+)/") or lower
        if lower:match("%.lua$") and includes[top] and not lower:find("^libs/") and not lower:find("/libs/")
            and not loaded[lower] and not optedOut(p) then
            problems[#problems + 1] = ("  %s ships (make-release.ps1 $includes) but no toc or xml loads it"):format(p)
        end
    end
end

if #problems > 0 then
    print("toc-check:")
    print(table.concat(problems, "\n"))
end
