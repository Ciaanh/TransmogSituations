-- Replays the /bs dump captured on Retail on 2026-09-22 on a mage with saved talent loadouts,
-- transmog window open and "Home" (id 4) viewed. This is the capture that showed the
-- Specializations category lists one option PER SAVED LOADOUT (specID + loadoutID) next to the
-- per-spec option (specID + loadoutID 0), overturning the earlier "per-spec only" conclusion
-- drawn from a rogue who had no loadouts. Option names are not unique ("wowhead" three times,
-- "Frost" twice), so only the ids can identify an option. It also confirms the api read on
-- Retail: House answered true for the viewed outfit while `value` was false everywhere.
local ROOT = arg[1] or "."

Enum = { TransmogSituation = {} } -- deliberately empty: the client owns the ids

local function Opt(name, situationID, specID, loadoutID)
    return {
        name = name,
        value = false, -- false on every option, exactly as captured
        option = { situationID = situationID, specID = specID or 0, loadoutID = loadoutID or 0, equipmentSetID = 0 },
    }
end

-- Verbatim from the dump, including list order. No Equipment Sets (the character has none) and
-- no Racial Forms (not a Dracthyr/Worgen): both conditional categories absent, as documented.
local CATEGORIES = {
    { triggerID = 3, name = "Locations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Locations", 3), Opt("Rest Area", 4), Opt("House", 7), Opt("Character Select", 8),
        Opt("World", 5), Opt("Delves", 6), Opt("Dungeons", 9), Opt("Raids", 10),
        Opt("Arenas", 11), Opt("Battlegrounds", 12) } } } },
    { triggerID = 4, name = "Movement", isRadioButton = false, groupData = { { optionData = {
        Opt("All Movement", 13), Opt("Unmounted", 14), Opt("Swimming", 15),
        Opt("Ground Mount", 16), Opt("Flying Mount", 17) } } } },
    { triggerID = 5, name = "Specializations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Specializations", 1),
        Opt("Arcane", 2, 62), Opt("wowhead", 2, 62, 84113877),
        Opt("Fire", 2, 63), Opt("wowhead", 2, 63, 83381349),
        Opt("Frost", 2, 64), Opt("Frost", 2, 64, 53887243), Opt("Perso", 2, 64, 54223284),
        Opt("wowhead", 2, 64, 82065976) } } } },
    { triggerID = 11, name = "Weather", isRadioButton = false, groupData = { { optionData = {
        Opt("All Weather", 32), Opt("Clear", 33), Opt("Rain", 34), Opt("Snow", 35),
        Opt("Sandstorm", 36) } } } },
    { triggerID = 12, name = "Time of Day", isRadioButton = false, groupData = { { optionData = {
        Opt("All Times", 37), Opt("Morning", 38), Opt("Midday", 39), Opt("Evening", 40),
        Opt("Night", 41) } } } },
}

-- What the api answered for the viewed outfit "Home": House, plus every "All" except Locations.
local HOME_ASSIGNED = { [7] = true, [13] = true, [1] = true, [32] = true, [37] = true }

-- Which saved loadout is selected; nil means none. Not in the dump (it only shows the options),
-- so the replay drives it through the states that matter.
SELECTED_LOADOUT = 54223284 -- "Perso"

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return CATEGORIES end,
    GetActiveOutfitID = function() return 39 end,
    GetCurrentlyViewedOutfitID = function() return 4 end,
    GetOutfitSituation = function(option) return HOME_ASSIGNED[option.situationID] == true end,
    HasPendingOutfitSituations = function() return false end,
    GetOutfitsInfo = function()
        -- The spec-vs-loadout block below hand-writes entries that constrain Specializations
        -- only. The captured labels say otherwise, and the stale check would rightly reject
        -- the contradiction, so that block switches these three to a matching label.
        local spec = SPEC_ONLY_LABELS and { "Specializations" } or nil
        return {
            { outfitID = 2, name = "Frost", playerFacingOutfitIndex = 1,
              situationCategories = spec or { "Specializations", "Locations", "Movement" } },
            { outfitID = 3, name = "Rest", playerFacingOutfitIndex = 2, situationCategories = { "Locations" } },
            { outfitID = 4, name = "Home", playerFacingOutfitIndex = 3, situationCategories = { "Locations" } },
            { outfitID = 5, name = "Ceremony", playerFacingOutfitIndex = 4, situationCategories = {} },
            { outfitID = 36, name = "Fire", playerFacingOutfitIndex = 5,
              situationCategories = spec or { "Specializations", "Locations", "Movement" } },
            { outfitID = 37, name = "Arcane", playerFacingOutfitIndex = 6,
              situationCategories = spec or { "Specializations", "Locations", "Movement" } },
            { outfitID = 39, name = "Mount", playerFacingOutfitIndex = 7, situationCategories = { "Movement" } },
        }
    end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_DelvesUI = { HasActiveDelve = function() return false end }
C_Housing = {
    IsInsideHouse = function() return false end,
    IsInsideHouseOrPlot = function() return false end,
    IsOnNeighborhoodMap = function() return false end,
}
C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end, GetEquipmentSetInfo = function() end }
C_PlayerInfo = { GetAlternateFormInfo = function() return false, false end }
C_SpecializationInfo = {
    GetSpecialization = function() return 3 end,
    GetSpecializationInfo = function() return 64, "Frost" end,
}
C_ClassTalents = {
    GetLastSelectedSavedConfigID = function(specID) return specID == 64 and SELECTED_LOADOUT or nil end,
}
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

-- Raw player state exactly as the dump reported it: open world, not resting, on a ground mount.
function IsInInstance() return false, "none" end
function IsResting() return false end
function IsIndoors() return false end
function IsSwimming() return false end
function IsMounted() return true end
function IsFlying() return false end
function GetGameTime() return 11, 0 end
function GetRealZoneText() return "Zone" end
function GetSubZoneText() return "" end
function UnitName() return "Tester" end
function GetRealmName() return "Retail" end
function InCombatLockdown() return false end
function time() return 1000 end
function hooksecurefunc() end
date = os.date
HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
UIParent = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local function StubFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() return f end end })
    return f
end
function CreateFrame() return StubFrame() end

local ns = {}
for _, file in ipairs({ "core/Util.lua", "core/Capabilities.lua", "core/Triggers.lua",
    "core/OutfitCache.lua", "core/Eligibility.lua", "core/Diagnostics.lua",
    "core/StatusPanel.lua", "core/SituationPanel.lua", "BetterSituation.lua" }) do
    local chunk, err = loadfile(ROOT .. "/" .. file)
    if not chunk then print("LOAD FAIL " .. file .. ": " .. tostring(err)); os.exit(1) end
    local ok, runErr = pcall(chunk, "BetterSituation", ns)
    if not ok then print("RUN FAIL " .. file .. ": " .. tostring(runErr)); os.exit(1) end
end
BetterSituationDB.debug = false
ns.BetterSituation.db = BetterSituationDB
ns.Capabilities:Init()
ns.Triggers:Init(ns.BetterSituation)
ns.OutfitCache:Init(ns.BetterSituation)
ns.Eligibility:Init(ns.BetterSituation)
ns.Diagnostics:Init(ns.BetterSituation)

local failures = 0
local function Check(label, got, expected)
    local ok = (got == expected)
    if not ok then failures = failures + 1 end
    print(string.format("  %-56s %-16s %s", label, tostring(got),
        ok and "OK" or ("<<< FAIL, wanted " .. tostring(expected))))
end

local SPEC = 5

print("resolved values, loadout 'Perso' selected:")
local EXPECTED = { [3] = "World", [4] = "Ground Mount", [5] = "Perso", [12] = "Morning" }
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    if EXPECTED[entry.triggerID] then
        Check(string.format("[%d] %s", entry.triggerID, entry.categoryName), entry.displayName,
            EXPECTED[entry.triggerID])
    end
end
Check("Weather is unsupported here", ns.Triggers:Resolve(11).state, "unsupported")

local spec = ns.Triggers:Resolve(SPEC)
Check("loadout option carries the loadoutID", spec.option.loadoutID, 54223284)
Check("the spec option rides along", ns.Triggers:GetAlsoNames(SPEC, spec)[1], "Frost")
Check("...and it is the loadout-0 Frost, not the loadout named Frost",
    spec.alsoOptions[1].option.loadoutID, 0)

print("no saved loadout selected:")
SELECTED_LOADOUT = nil
ns.Triggers:InvalidateCategories()
spec = ns.Triggers:Resolve(SPEC)
Check("falls back to the per-spec option", spec.optionName, "Frost")
Check("which is the loadout-0 one", spec.option.loadoutID, 0)
Check("nothing rides along", #spec.alsoOptions, 0)

print("selected loadout no longer offered (deleted):")
SELECTED_LOADOUT = 99999999
ns.Triggers:InvalidateCategories()
spec = ns.Triggers:Resolve(SPEC)
Check("falls back to the per-spec option", spec.optionName, "Frost")
SELECTED_LOADOUT = 54223284
ns.Triggers:InvalidateCategories()

print("option identity:")
local frostSpec = ns.Triggers:GetOptions(SPEC)[6].option
local frostLoadout = ns.Triggers:GetOptions(SPEC)[7].option
Check("same name, same spec, different key",
    ns.OutfitCache.OptionKey(frostSpec) ~= ns.OutfitCache.OptionKey(frostLoadout), true)
Check("key carries the loadout", ns.OutfitCache.OptionKey(frostLoadout), "2:64:53887243:0")

print("assignment read on Retail:")
local house = ns.Triggers:GetOptions(3)[3]
local assigned, source = ns.OutfitCache.IsAssigned(house)
Check("House assigned on the viewed outfit", assigned, true)
Check("answered by the api", source, "api")
Check("Home recorded", ns.OutfitCache:RecordViewed(), 4)
local home = ns.OutfitCache:Get(4)
Check("Locations is a real constraint", home.categories[3].wildcard, false)
Check("Locations holds House", home.categories[3].keys["7:0:0:0"], true)
Check("Specializations is a wildcard", home.categories[SPEC].wildcard, true)

print("eligibility in the open world, mounted:")
local eligible, rejected = ns.Eligibility:GetEligible()
Check("Home does not match out here", #eligible, 0)
local homeReason
for _, r in ipairs(rejected) do if r.outfitID == 4 then homeReason = r.reason end end
Check("...because of Locations", homeReason, "Locations is World")

-- An outfit bound to the spec matches under any of its loadouts; one bound to a loadout only
-- matches under that loadout. Recorded by hand, since only Home was viewed in the capture.
print("spec vs loadout constraints:")
SPEC_ONLY_LABELS = true
local store = ns.OutfitCache:GetStore(true)
local function Entry(keys)
    return { at = 1, categories = { [SPEC] = { any = true, wildcard = false, keys = keys } } }
end
store[2] = Entry({ ["2:64:0:0"] = true })          -- "Frost": the spec, any loadout
store[36] = Entry({ ["2:64:54223284:0"] = true })  -- pretend "Fire" is bound to loadout Perso
store[37] = Entry({ ["2:64:82065976:0"] = true })  -- pretend "Arcane" is bound to loadout wowhead
eligible = ns.Eligibility:GetEligible()
local names = {}
for _, e in ipairs(eligible) do names[e.name] = true end
Check("spec-bound outfit matches under Perso", names["Frost"], true)
Check("Perso-bound outfit matches under Perso", names["Fire"], true)
Check("other-loadout outfit does not", names["Arcane"], nil)

SELECTED_LOADOUT = nil
ns.Triggers:InvalidateCategories()
eligible = ns.Eligibility:GetEligible()
names = {}
for _, e in ipairs(eligible) do names[e.name] = true end
Check("spec-bound outfit still matches with no loadout", names["Frost"], true)
Check("loadout-bound outfit drops out", names["Fire"], nil)

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
