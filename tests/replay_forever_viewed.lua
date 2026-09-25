---@diagnostic disable: undefined-global, lowercase-global
-- Replays the /ts dump captured on the Forever beta on 2026-09-22 with the transmog window
-- open and "Outfit 2" (id 3) viewed. This is the capture that settled how an assignment is
-- read: GetOutfitSituation answered true for every "All" option while the option tree's
-- `value` flag was false on every option. It also carries a real Equipment Sets category with
-- set id 0 equipped, and an outfit whose situationCategories is empty yet is all wildcards.
local H = dofile((arg[1] or ".") .. "/tests/harness.lua")

H.categories = H.ForeverTree()
table.insert(H.categories, 4, H.Category(6, "Equipment Sets", { H.Opt("All Equipment Sets", 18),
    H.Opt("plop", 19, { equipmentSetID = 0 }), H.Opt("test", 19, { equipmentSetID = 1 }) }))
H.EnableWeather(0)
H.W.resting = true
H.W.specIndex, H.W.specID = 1, 1485
H.W.hour, H.W.minute = 0, 59
H.sets = {
    { id = 0, name = "plop", isEquipped = true, numItems = 6, numEquipped = 6 },
    { id = 1, name = "test", isEquipped = false, numItems = 5, numEquipped = 5 },
}
H.outfits = {
    { outfitID = 2, name = "Outfit 1", playerFacingOutfitIndex = 1, situationCategories = { "Locations" } },
    { outfitID = 3, name = "Outfit 2", playerFacingOutfitIndex = 2, situationCategories = {} },
}
H.activeOutfitID, H.viewedOutfitID = 2, 3
-- What the api answered for the viewed outfit: true for every "All", false otherwise.
H.assigned[3] = {}
for _, id in ipairs({ 3, 13, 1, 18, 32, 37 }) do
    H.assigned[3][id .. ":0:0:0"] = true
end

local ns = H.Load()

H.Section("resolved values")
local EXPECTED = { [3] = "Rest Area", [4] = "Unmounted", [5] = "Hunter", [6] = "plop", [11] = "Clear", [12] = "Night" }
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    H.Check(string.format("[%d] %s", entry.triggerID, entry.categoryName), entry.result.optionName,
        EXPECTED[entry.triggerID])
end
H.Check("equipment set id 0 matched by situationID 19 + id", ns.Triggers:Resolve(6).equipmentSetID, 0)

-- `value` is false everywhere, so only the api path can record anything.
H.Section("assignment read")
local assigned, source = ns.OutfitCache.IsAssigned(ns.Triggers:GetOptions(3)[1])
H.Check("All Locations assigned", assigned, true)
H.Check("answered by the api, not the value flag", source, "api")
H.Check("Rest Area not assigned", ns.OutfitCache.IsAssigned(ns.Triggers:GetOptions(3)[2]), false)

H.Check("viewed outfit recorded", ns.OutfitCache:RecordViewed(), 3)
local wildcards = 0
for _, selected in pairs(ns.OutfitCache:Get(3).categories) do
    if selected.wildcard then wildcards = wildcards + 1 end
end
H.Check("every category is a wildcard on a fresh outfit", wildcards, 6)

-- An all-wildcard outfit matches anywhere; the never-viewed one cannot be matched at all.
H.Section("eligibility")
local eligible, rejected = ns.Eligibility:GetEligible()
H.Check("eligible count", #eligible, 1)
H.Check("Outfit 2 matches", eligible[1] and eligible[1].name, "Outfit 2")
H.Check("wildcards constrain nothing", eligible[1] and eligible[1].specificity, 0)
H.Check("Outfit 1 rejected as not recorded", rejected[1] and rejected[1].reason, "not recorded")

H.Done()
