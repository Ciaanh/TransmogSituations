-- json.lua: a small JSON decoder / encoder for Lua 5.1+, enough for Claude Code hook input and
-- the workspace config. No dependencies. The repo slice ships a byte-identical copy
-- (repo-slice/.claude/hooks/lib/json.lua); tests/run.sh checks they stay identical.
local json = {}

-- Decoded JSON null. Distinct from nil so arrays keep their positions.
json.null = setmetatable({}, { __tostring = function() return "null" end })

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local function skip(s, i)
    local _, e = s:find("^[ \t\r\n]*", i)
    return e + 1
end

local function fail(s, i, what)
    error(("json: %s at byte %d"):format(what, i), 0)
end

local function decodeString(s, i) -- s:sub(i, i) == '"'
    local out, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then fail(s, j, "unterminated string") end
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            if e == "u" then
                local cp = tonumber(s:sub(j + 2, j + 5), 16)
                if not cp then fail(s, j, "bad \\u escape") end
                j = j + 6
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
                    local lo = tonumber(s:sub(j + 2, j + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        j = j + 6
                    end
                end
                out[#out + 1] = utf8char(cp)
            else
                local r = ESCAPES[e]
                if not r then fail(s, j, "bad escape") end
                out[#out + 1] = r
                j = j + 2
            end
        else
            local k = s:find('["\\]', j)
            if not k then fail(s, j, "unterminated string") end
            out[#out + 1] = s:sub(j, k - 1)
            j = k
        end
    end
end

local decodeValue

local function decodeObject(s, i)
    local t = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
        i = skip(s, i)
        if s:sub(i, i) ~= '"' then fail(s, i, "expected a key") end
        local k, v
        k, i = decodeString(s, i)
        i = skip(s, i)
        if s:sub(i, i) ~= ":" then fail(s, i, "expected ':'") end
        v, i = decodeValue(s, i + 1)
        t[k] = v
        i = skip(s, i)
        local d = s:sub(i, i)
        if d == "}" then return t, i + 1 end
        if d ~= "," then fail(s, i, "expected ',' or '}'") end
        i = i + 1
    end
end

local function decodeArray(s, i)
    local t, n = {}, 0
    i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return t, i + 1 end
    while true do
        local v
        v, i = decodeValue(s, i)
        n = n + 1
        t[n] = v
        i = skip(s, i)
        local d = s:sub(i, i)
        if d == "]" then return t, i + 1 end
        if d ~= "," then fail(s, i, "expected ',' or ']'") end
        i = i + 1
    end
end

function decodeValue(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then return decodeObject(s, i) end
    if c == "[" then return decodeArray(s, i) end
    if c == '"' then return decodeString(s, i) end
    if s:find("^true", i) then return true, i + 4 end
    if s:find("^false", i) then return false, i + 5 end
    if s:find("^null", i) then return json.null, i + 4 end
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num then fail(s, i, "unexpected character") end
    return tonumber(num), i + #num
end

function json.decode(s)
    local v, i = decodeValue(s, 1)
    i = skip(s, i)
    if i <= #s then fail(s, i, "trailing data") end
    return v
end

local ENCODE_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(str)
    return '"' .. (str:gsub('[%c"\\]', function(ch)
        return ENCODE_ESCAPES[ch] or ("\\u%04x"):format(ch:byte())
    end)) .. '"'
end

function json.encode(v)
    local kind = type(v)
    if v == nil or v == json.null then return "null" end
    if kind == "boolean" or kind == "number" then return tostring(v) end
    if kind == "string" then return encodeString(v) end
    if kind == "table" then
        local parts = {}
        if #v > 0 then
            for _, item in ipairs(v) do parts[#parts + 1] = json.encode(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = encodeString(k) .. ":" .. json.encode(v[k]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("json: cannot encode a " .. kind, 0)
end

-- json.get(t, "tool_input.file_path"): a dotted path into decoded JSON, or nil.
function json.get(t, path)
    for key in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[key]
    end
    if t == json.null then return nil end
    return t
end

return json
