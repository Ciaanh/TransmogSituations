---@diagnostic disable: undefined-global, lowercase-global
-- Replays the /ts dump captured on the Forever beta. Locations here is MISSING House (7) and
-- Delves (6), which is what rules out identifying options by position.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

H.categories = H.ForeverTree()
H.EnableWeather(0)
H.W.resting = true
H.W.specIndex, H.W.specID = 1, 1485
H.W.hour, H.W.minute = 14, 8
H.activeOutfitID = 1

local ns = H.Load()

H.Section("resolved values")
local EXPECTED = { [3] = "Rest Area", [4] = "Unmounted", [5] = "Hunter", [11] = "Clear", [12] = "Midday" }
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    H.Check(string.format("[%d] %s", entry.triggerID, entry.categoryName), entry.result.optionName,
        EXPECTED[entry.triggerID])
end

-- The critical cross-client check: position 5 of Locations is "Dungeons" here but "World" on
-- Retail, so anything position-based would silently return the wrong option.
H.Section("identity is the situationID, not the position")
H.Check("Locations position 5 on this client", ns.Triggers:GetOptions(3)[5].name, "Dungeons")
H.Check("House (7) is not offered here", ns.Triggers:FindOption(3, ns.Triggers.SITUATION.LocationHouse), nil)

H.Done()
