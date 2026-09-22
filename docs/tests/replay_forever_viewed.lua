-- Replays the /bs dump captured on the Forever beta on 2026-09-22 with the transmog window
-- open and "Outfit 2" (id 3) viewed. This is the capture that settled how an assignment is
-- read: GetOutfitSituation answered true for every "All" option while the option tree's
-- `value` flag was false on every option. It also carries a real Equipment Sets category with
-- set id 0 equipped, and an outfit whose situationCategories is empty yet is all wildcards.
local ROOT = arg[1] or "."

Enum = {
    TransmogSituation = {}, -- deliberately empty: the client owns the ids
    WeatherType = { Clear = 0, Rain = 1, Snow = 2, Sandstorm = 3, Miscellaneous = 4 },
}

-- `value` is false on EVERY option, exactly as captured.
local function Opt(name, situationID, specID, equipmentSetID)
    return {
        name = name,
        value = false,
        option = {
            situationID = situationID,
            specID = specID or 0,
            loadoutID = 0,
            equipmentSetID = equipmentSetID or 0,
        },
    }
end

-- Verbatim from the dump, including list order and the missing House / Delves.
local CATEGORIES = {
    { triggerID = 3, name = "Locations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Locations", 3), Opt("Rest Area", 4), Opt("Character Select", 8),
        Opt("World", 5), Opt("Dungeons", 9), Opt("Raids", 10), Opt("Arenas", 11),
        Opt("Battlegrounds", 12) } } } },
    { triggerID = 4, name = "Movement", isRadioButton = false, groupData = { { optionData = {
        Opt("All Movement", 13), Opt("Unmounted", 14), Opt("Swimming", 15),
        Opt("Ground Mount", 16), Opt("Flying Mount", 17) } } } },
    { triggerID = 5, name = "Specializations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Specializations", 1), Opt("Hunter", 2, 1485) } } } },
    { triggerID = 6, name = "Equipment Sets", isRadioButton = false, groupData = { { optionData = {
        Opt("All Equipment Sets", 18), Opt("plop", 19, 0, 0), Opt("test", 19, 0, 1) } } } },
    { triggerID = 11, name = "Weather", isRadioButton = false, groupData = { { optionData = {
        Opt("All Weather", 32), Opt("Clear", 33), Opt("Rain", 34), Opt("Snow", 35),
        Opt("Sand", 36) } } } },
    { triggerID = 12, name = "Time of Day", isRadioButton = false, groupData = { { optionData = {
        Opt("All Times", 37), Opt("Morning", 38), Opt("Midday", 39), Opt("Evening", 40),
        Opt("Night", 41) } } } },
}

-- What the api answered for the viewed outfit: true for every "All", false otherwise.
local ALL = { [3] = true, [13] = true, [1] = true, [18] = true, [32] = true, [37] = true }

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return CATEGORIES end,
    GetActiveOutfitID = function() return 2 end,
    GetCurrentlyViewedOutfitID = function() return 3 end,
    GetOutfitSituation = function(option) return ALL[option.situationID] == true end,
    HasPendingOutfitSituations = function() return false end,
    GetOutfitsInfo = function()
        return {
            { outfitID = 2, name = "Outfit 1", playerFacingOutfitIndex = 1,
              situationCategories = { "Locations" }, isEventOutfit = false, isDisabled = false },
            { outfitID = 3, name = "Outfit 2", playerFacingOutfitIndex = 2,
              situationCategories = {}, isEventOutfit = false, isDisabled = false },
        }
    end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_Weather = { GetCurrentWeather = function() return { type = 0, intensity = 0 } end }
C_DelvesUI = { HasActiveDelve = function() return false end }
C_Housing = {
    IsInsideHouse = function() return false end,
    IsInsideHouseOrPlot = function() return false end,
    IsOnNeighborhoodMap = function() return false end,
}
-- Two sets, ids 0 and 1; only id 0 ("plop") is fully equipped.
C_EquipmentSet = {
    GetEquipmentSetIDs = function() return { 0, 1 } end,
    GetEquipmentSetInfo = function(id)
        if id == 0 then return "plop", 0, 0, true, 6, 6, 0, 0, 0 end
        if id == 1 then return "test", 0, 1, false, 5, 5, 0, 0, 0 end
        return nil
    end,
    GetEquipmentSetForSpec = function() return nil end,
}
C_PlayerInfo = { GetAlternateFormInfo = function() return false, false end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1485, "Hunter" end,
}
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

-- Raw player state exactly as the dump reported it.
function IsInInstance() return false, "none" end
function IsResting() return true end
function IsIndoors() return false end
function IsSwimming() return false end
function IsMounted() return false end
function IsFlying() return false end
function GetGameTime() return 0, 59 end
function GetRealZoneText() return "Zone" end
function GetSubZoneText() return "" end
function UnitName() return "Tester" end
function GetRealmName() return "Forever" end
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
    print(string.format("  %-52s %-14s %s", label, tostring(got),
        ok and "OK" or ("<<< FAIL, wanted " .. tostring(expected))))
end

-- Every category's resolved value, as the dump reported it.
print("resolved values:")
local EXPECTED = {
    [3] = "Rest Area", [4] = "Unmounted", [5] = "Hunter", [6] = "plop", [11] = "Clear", [12] = "Night",
}
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    Check(string.format("[%d] %s", entry.triggerID, entry.categoryName), entry.displayName,
        EXPECTED[entry.triggerID])
end
local eq = ns.Triggers:Resolve(6)
Check("equipment set id 0 matched by situationID 19 + id", eq.equipmentSetID, 0)

-- The assignment read. `value` is false everywhere, so only the api path can record anything.
print("assignment read:")
local allLoc = ns.Triggers:GetOptions(3)[1]
local assigned, source = ns.OutfitCache.IsAssigned(allLoc)
Check("All Locations assigned", assigned, true)
Check("answered by the api, not the value flag", source, "api")
Check("Rest Area not assigned", ns.OutfitCache.IsAssigned(ns.Triggers:GetOptions(3)[2]), false)

local recordedID = ns.OutfitCache:RecordViewed()
Check("viewed outfit recorded", recordedID, 3)
local entry = ns.OutfitCache:Get(3)
local wildcardCategories = 0
for _, selected in pairs(entry.categories) do
    if selected.any and selected.wildcard then wildcardCategories = wildcardCategories + 1 end
end
Check("every category is a wildcard on a fresh outfit", wildcardCategories, 6)

-- An all-wildcard outfit matches anywhere with specificity 0; the never-viewed one cannot.
print("eligibility:")
local eligible, rejected = ns.Eligibility:GetEligible()
Check("eligible count", #eligible, 1)
Check("Outfit 2 matches", eligible[1] and eligible[1].name, "Outfit 2")
Check("wildcards give specificity 0", eligible[1] and eligible[1].specificity, 0)
Check("Outfit 1 rejected as not recorded", rejected[1] and rejected[1].reason, "not recorded")

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
