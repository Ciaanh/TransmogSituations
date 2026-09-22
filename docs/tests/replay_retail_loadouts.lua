---@diagnostic disable: undefined-global, lowercase-global
-- Replays the /bs dump captured on Retail on 2026-09-22 on a mage with saved talent loadouts,
-- transmog window open and "Home" (id 4) viewed. This is the capture that showed the
-- Specializations category lists one option PER SAVED LOADOUT (specID + loadoutID) next to the
-- per-spec option (specID + loadoutID 0), overturning the earlier "per-spec only" conclusion
-- drawn from a rogue who had no loadouts. Option names are not unique ("wowhead" three times,
-- "Frost" twice), so only the ids can identify an option. It also confirms the api read on
-- Retail: House answered true for the viewed outfit while `value` was false everywhere.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

local SPEC = 5
local function Spec(name, specID, loadoutID)
    return H.Opt(name, 2, { specID = specID, loadoutID = loadoutID })
end

-- Verbatim from the dump. No Equipment Sets (the character has none) and no Racial Forms (not a
-- Dracthyr or Worgen): both conditional categories absent, as documented.
H.categories = H.RetailTree()
H.categories[3] = H.Category(SPEC, "Specializations", {
    H.Opt("All Specializations", 1),
    Spec("Arcane", 62), Spec("wowhead", 62, 84113877),
    Spec("Fire", 63), Spec("wowhead", 63, 83381349),
    Spec("Frost", 64), Spec("Frost", 64, 53887243), Spec("Perso", 64, 54223284),
    Spec("wowhead", 64, 82065976) })
table.remove(H.categories, 4) -- Racial Forms

-- Open world, not resting, on a ground mount.
H.W.mounted = true
H.W.specIndex, H.W.specID = 3, 64
H.W.hour = 11

-- Which saved loadout is selected; nil means none. Not in the dump (it only shows the options),
-- so the replay drives it through the states that matter.
local selectedLoadout = 54223284 -- "Perso"
C_ClassTalents = {
    GetLastSelectedSavedConfigID = function(specID) return specID == 64 and selectedLoadout or nil end,
}

-- The captured outfit list and labels.
local CAPTURED_OUTFITS = {
    { outfitID = 2, name = "Frost", playerFacingOutfitIndex = 1, situationCategories = { "Specializations", "Locations", "Movement" } },
    { outfitID = 3, name = "Rest", playerFacingOutfitIndex = 2, situationCategories = { "Locations" } },
    { outfitID = 4, name = "Home", playerFacingOutfitIndex = 3, situationCategories = { "Locations" } },
    { outfitID = 5, name = "Ceremony", playerFacingOutfitIndex = 4, situationCategories = {} },
    { outfitID = 36, name = "Fire", playerFacingOutfitIndex = 5, situationCategories = { "Specializations", "Locations", "Movement" } },
    { outfitID = 37, name = "Arcane", playerFacingOutfitIndex = 6, situationCategories = { "Specializations", "Locations", "Movement" } },
    { outfitID = 39, name = "Mount", playerFacingOutfitIndex = 7, situationCategories = { "Movement" } },
}
H.outfits = CAPTURED_OUTFITS
H.activeOutfitID, H.viewedOutfitID = 39, 4
-- What the api answered for "Home": House, plus every "All" except Locations.
H.assigned[4] = {}
for _, id in ipairs({ 7, 13, 1, 32, 37 }) do
    H.assigned[4][id .. ":0:0:0"] = true
end

local ns = H.Load()

H.Section("resolved values, loadout 'Perso' selected")
local EXPECTED = { [3] = "World", [4] = "Ground Mount", [5] = "Perso", [12] = "Morning" }
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    if EXPECTED[entry.triggerID] then
        H.Check(string.format("[%d] %s", entry.triggerID, entry.categoryName), entry.result.optionName,
            EXPECTED[entry.triggerID])
    end
end
H.Check("Weather is unsupported here", ns.Triggers:Resolve(11).state, "unsupported")

local spec = ns.Triggers:Resolve(SPEC)
H.Check("loadout option carries the loadoutID", spec.option.loadoutID, 54223284)
H.Check("the spec option rides along", H.AlsoNames(spec), "Frost")
H.Check("...and it is the loadout-0 Frost, not the loadout named Frost", spec.alsoOptions[1].option.loadoutID, 0)

H.Section("no saved loadout selected")
selectedLoadout = nil
ns.Triggers:InvalidateCategories()
spec = ns.Triggers:Resolve(SPEC)
H.Check("falls back to the per-spec option", spec.optionName, "Frost")
H.Check("which is the loadout-0 one", spec.option.loadoutID, 0)
H.Check("nothing rides along", #spec.alsoOptions, 0)

H.Section("selected loadout no longer offered (deleted)")
selectedLoadout = 99999999
ns.Triggers:InvalidateCategories()
H.Check("falls back to the per-spec option", ns.Triggers:Resolve(SPEC).optionName, "Frost")
selectedLoadout = 54223284
ns.Triggers:InvalidateCategories()

H.Section("option identity")
local frostSpec = ns.Triggers:GetOptions(SPEC)[6].option
local frostLoadout = ns.Triggers:GetOptions(SPEC)[7].option
H.Check("same name, same spec, different key",
    ns.OutfitCache.OptionKey(frostSpec) ~= ns.OutfitCache.OptionKey(frostLoadout), true)
H.Check("key carries the loadout", ns.OutfitCache.OptionKey(frostLoadout), "2:64:53887243:0")

H.Section("assignment read on Retail")
local assigned, source = ns.OutfitCache.IsAssigned(ns.Triggers:GetOptions(3)[3])
H.Check("House assigned on the viewed outfit", assigned, true)
H.Check("answered by the api", source, "api")
H.Check("Home recorded", ns.OutfitCache:RecordViewed(), 4)
local home = ns.OutfitCache:Get(4)
H.Check("Locations is a real constraint", home.categories[3].wildcard, false)
H.Check("Locations holds House", home.categories[3].keys["7:0:0:0"], true)
H.Check("Specializations is a wildcard", home.categories[SPEC].wildcard, true)

H.Section("eligibility in the open world, mounted")
local eligible, rejected = ns.Eligibility:GetEligible()
H.Check("Home does not match out here", #eligible, 0)
local homeReason
for _, r in ipairs(rejected) do if r.outfitID == 4 then homeReason = r.reason end end
H.Check("...because of Locations", homeReason, "Locations is World")

-- An outfit bound to the spec matches under any of its loadouts; one bound to a loadout only
-- matches under that loadout. Recorded by hand, since only Home was viewed in the capture, so
-- the labels are switched to match what the hand-written entries constrain.
H.Section("spec vs loadout constraints")
for _, info in ipairs(H.outfits) do
    if info.outfitID == 2 or info.outfitID == 36 or info.outfitID == 37 then
        info.situationCategories = { "Specializations" }
    end
end
local store = ns.OutfitCache:GetStore(true)
local function Entry(keys)
    return { categories = { [SPEC] = { any = true, wildcard = false, keys = keys } } }
end
store[2] = Entry({ ["2:64:0:0"] = true })          -- "Frost": the spec, any loadout
store[36] = Entry({ ["2:64:54223284:0"] = true })  -- pretend "Fire" is bound to loadout Perso
store[37] = Entry({ ["2:64:82065976:0"] = true })  -- pretend "Arcane" is bound to loadout wowhead

local function EligibleNames()
    local names = {}
    for _, e in ipairs((ns.Eligibility:GetEligible())) do names[e.name] = true end
    return names
end

local names = EligibleNames()
H.Check("spec-bound outfit matches under Perso", names["Frost"], true)
H.Check("Perso-bound outfit matches under Perso", names["Fire"], true)
H.Check("other-loadout outfit does not", names["Arcane"], nil)

selectedLoadout = nil
ns.Triggers:InvalidateCategories()
names = EligibleNames()
H.Check("spec-bound outfit still matches with no loadout", names["Frost"], true)
H.Check("loadout-bound outfit drops out", names["Fire"], nil)

H.Done()
