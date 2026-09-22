---@diagnostic disable: undefined-global, lowercase-global
-- /bs list marks the current and also-active options from the resolver's own answer, never
-- from a second copy of the matching logic. Retail tree, inside a house while resting: House
-- is current and Rest Area is only also active.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

H.categories = H.RetailTree()
H.W.inInstance, H.W.instanceType, H.W.insideHouse, H.W.resting = true, "neighborhood", true, true
H.W.mounted = true
H.W.hasAltForm, H.W.inAltForm = true, true -- Dracthyr in visage
H.W.specIndex, H.W.specID = 1, 259
H.W.hour, H.W.minute = 23, 3

local ns = H.Load()
H.ClearChat()
ns.Diagnostics:PrintCategoriesList()

local function Marked(name, marker)
    for _, line in ipairs(H.chat) do
        if line:find("   " .. name, 1, true) and line:find(marker, 1, true) then
            return true
        end
    end
    return false
end

H.Section("/bs list marking")
H.Check("House [current]", Marked("House", "[current]"), true)
H.Check("Rest Area [also active]", Marked("Rest Area", "[also active]"), true)
H.Check("Ground Mount [current]", Marked("Ground Mount", "[current]"), true)
H.Check("Assassination [current]", Marked("Assassination", "[current]"), true)
H.Check("Visage [current]", Marked("Visage", "[current]"), true)
H.Check("World carries no marker", Marked("World", "[current]") or Marked("World", "[also active]"), false)

local doubled = 0
for _, line in ipairs(H.chat) do
    if line:find("[current]", 1, true) and line:find("[also active]", 1, true) then
        doubled = doubled + 1
    end
end
H.Check("nothing is marked twice", doubled, 0)

H.Done()
