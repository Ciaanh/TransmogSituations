-- json-get.lua PATH: reads JSON on stdin and prints the value at a dotted PATH
-- ("tool_input.file_path"). Arrays print one element per line; a missing value prints nothing.
-- The repo slice ships a byte-identical copy.
local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path
local json = require("json")

local ok, data = pcall(json.decode, io.read("*a") or "")
if not ok then os.exit(0) end
local v = json.get(data, arg[1] or "")
if type(v) == "table" then
    for _, item in ipairs(v) do
        if type(item) ~= "table" then io.write(tostring(item), "\n") end
    end
elseif v ~= nil then
    io.write(tostring(v))
end
