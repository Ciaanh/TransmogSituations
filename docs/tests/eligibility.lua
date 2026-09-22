-- Phase 4: the outfit cache and the eligibility matcher.
--
-- None of this has ever run in game. It proves the rules behave as designed, NOT that the
-- rules are Blizzard's. /bs verify is what scores them against reality.
local ROOT = arg[1] or "."

Enum = { TransmogSituation = {}, WeatherType = { Clear = 0 } }

local function Opt(name, situationID, value, extra)
    local option = { situationID = situationID, specID = 0, loadoutID = 0, equipmentSetID = 0 }
    for k, v in pairs(extra or {}) do option[k] = v end
    return { name = name, value = value or false, option = option }
end

-- Assignments of the outfit currently being viewed. Swapping this is what "the player
-- clicked another outfit" means.
local ASSIGNED = {}
local VIEWED = 1
local PENDING = false

-- The option tree's `value` flag is deliberately ALWAYS false here. Blizzard's own dropdown
-- never reads it; it asks GetOutfitSituation(option), and so must the cache. A cache that
-- still read `value` would record nothing and fail every check below.
local function Categories()
    return {
        { triggerID = 3, name = "Locations", isRadioButton = false, groupData = { { optionData = {
            Opt("All Locations", 3), Opt("Rest Area", 4), Opt("World", 5),
            Opt("Raids", 10) } } } },
        { triggerID = 4, name = "Movement", isRadioButton = false, groupData = { { optionData = {
            Opt("All Movement", 13), Opt("Unmounted", 14),
            Opt("Ground Mount", 16) } } } },
        { triggerID = 5, name = "Specializations", isRadioButton = false, groupData = { { optionData = {
            Opt("All Specializations", 1),
            Opt("Assassination", 2, false, { specID = 259 }),
            Opt("Outlaw", 2, false, { specID = 260 }) } } } },
        -- No C_Weather is defined in this file, so Weather resolves as unsupported -- the
        -- Retail situation. An outfit ticked "All Weather" must still be able to match.
        { triggerID = 11, name = "Weather", isRadioButton = false, groupData = { { optionData = {
            Opt("All Weather", 32), Opt("Clear", 33), Opt("Rain", 34) } } } },
    }
end

local function GetOutfitSituation(option)
    local key = string.format("%d:%d:%d:%d", option.situationID, option.specID or 0, option.loadoutID or 0, option.equipmentSetID or 0)
    return (ASSIGNED[VIEWED] and ASSIGNED[VIEWED][key]) and true or false
end

local OUTFITS = {
    { outfitID = 2, name = "Combat",  playerFacingOutfitIndex = 1 },
    { outfitID = 3, name = "Rest",    playerFacingOutfitIndex = 2 },
    { outfitID = 4, name = "Raiding", playerFacingOutfitIndex = 3 },
    { outfitID = 5, name = "Unseen",  playerFacingOutfitIndex = 4 },
}

local ACTIVE_OUTFIT = 3

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return Categories() end,
    GetActiveOutfitID = function() return ACTIVE_OUTFIT end,
    GetCurrentlyViewedOutfitID = function() return VIEWED end,
    GetOutfitsInfo = function() return OUTFITS end,
    GetOutfitSituationsEnabled = function() return true end,
    GetOutfitSituation = GetOutfitSituation,
    HasPendingOutfitSituations = function() return PENDING end,
    ChangeViewedOutfit = function(id) VIEWED = id end,
}

local W = { inInstance = false, instanceType = "none", resting = true, mounted = false }
C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end, GetEquipmentSetInfo = function() end }
C_DelvesUI = { HasActiveDelve = function() return false end }
C_PlayerInfo = { GetAlternateFormInfo = function() return false, false end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 259 end,
}
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

function IsInInstance() return W.inInstance, W.instanceType end
function IsResting() return W.resting end
function IsIndoors() return false end
function IsSwimming() return false end
function IsMounted() return W.mounted end
function IsFlying() return false end
function GetGameTime() return 12, 0 end
function GetRealZoneText() return "Zone" end
function GetSubZoneText() return "" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return false end
function time() return 1000 end
function hooksecurefunc() end
date = os.date
HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
UIParent = {}
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(chat, msg) end }
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
    local chunk = assert(loadfile(ROOT .. "/" .. file))
    assert(pcall(chunk, "BetterSituation", ns))
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
    print(string.format("  %-50s %-22s %s", label, tostring(got),
        ok and "OK" or ("<<< FAIL, wanted " .. tostring(expected))))
end

-- Record three outfits by "viewing" each in turn. Outfit 5 is deliberately never viewed.
-- RecordViewed invalidates the category tree itself; nothing here does it for it.
local function Record(outfitID, keys)
    VIEWED = outfitID
    ASSIGNED[outfitID] = keys
    return ns.OutfitCache:RecordViewed()
end

Record(2, { ["10:0:0:0"] = true })                      -- Combat: Raids only
Record(3, { ["4:0:0:0"] = true, ["32:0:0:0"] = true })    -- Rest: Rest Area + All Weather
Record(4, { ["10:0:0:0"] = true, ["2:259:0:0"] = true })  -- Raiding: Raids AND Assassination
VIEWED = 3
ns.Triggers:InvalidateCategories()

print("cache:")
Check("outfits recorded", ns.OutfitCache:Count(), 3)
Check("never-viewed outfit is absent", ns.OutfitCache:Get(5), nil)
Check("unrecorded reported", #ns.OutfitCache:GetUnrecordedOutfits(), 1)
Check("assignment read through the api", ns.OutfitCache:Get(3).categories[3].keys["4:0:0:0"], true)
Check("wildcard flagged on the category", ns.OutfitCache:Get(3).categories[11].wildcard, true)

-- Mid-edit, GetOutfitSituation answers with the pending state. Nothing may be recorded then.
print("pending edits:")
PENDING = true
Check("recording is skipped while pending", Record(5, { ["5:0:0:0"] = true }), nil)
Check("outfit 5 still absent", ns.OutfitCache:Get(5), nil)
PENDING = false
ASSIGNED[5] = nil
VIEWED = 3
ns.Triggers:InvalidateCategories()

-- Resting, unmounted, Assassination. Rest also ticks "All Weather", and Weather is
-- unsupported here, so this doubles as the wildcard-over-unsupported check.
print("resting in the world:")
local eligible, rejected = ns.Eligibility:GetEligible()
Check("eligible count", #eligible, 1)
Check("best match (All Weather ignored on no-weather client)", eligible[1] and eligible[1].name, "Rest")
Check("wildcards do not count toward specificity", eligible[1] and eligible[1].specificity, 1)
local combatReason
for _, r in ipairs(rejected) do if r.name == "Combat" then combatReason = r.reason end end
Check("Combat rejected on Locations", combatReason, "Locations is Rest Area")

-- Now in a raid: both Combat (Raids) and Raiding (Raids + Assassination) match, and the
-- more specific one must come first.
W.inInstance, W.instanceType, W.resting = true, "raid", false
ns.Triggers:InvalidateCategories()
print("in a raid as Assassination:")
eligible = ns.Eligibility:GetEligible()
Check("eligible count", #eligible, 2)
-- Unranked: Blizzard picks among all of them at random, so the list keeps outfit order.
Check("listed in outfit order", eligible[1] and eligible[1].name, "Combat")
Check("second in outfit order", eligible[2] and eligible[2].name, "Raiding")
Check("constrained categories counted", eligible[2] and eligible[2].specificity, 2)

-- Same raid, wrong spec: Raiding constrains spec, Combat does not.
C_SpecializationInfo.GetSpecializationInfo = function() return 260 end
ns.Triggers:InvalidateCategories()
print("in a raid as Outlaw:")
eligible = ns.Eligibility:GetEligible()
Check("eligible count", #eligible, 1)
Check("spec-constrained outfit drops out", eligible[1] and eligible[1].name, "Combat")
C_SpecializationInfo.GetSpecializationInfo = function() return 259 end

-- A wildcard selection satisfies its category whatever the live value is.
Record(2, { ["3:0:0:0"] = true })  -- Combat: All Locations
W.inInstance, W.instanceType, W.resting = false, "none", true
ns.Triggers:InvalidateCategories()
print("wildcard selection:")
eligible = ns.Eligibility:GetEligible()
local names = {}
for _, e in ipairs(eligible) do names[e.name] = true end
Check("All Locations matches while resting", names["Combat"], true)

-- Verification against the outfit Blizzard applied.
print("verify:")
local report = ns.Eligibility:Verify()
Check("active outfit read", report and report.activeOutfitID, 3)
Check("unrecorded counted", report and report.unrecorded, 1)

Check("applied outfit among the eligible agrees", report and report.agrees, true)

ACTIVE_OUTFIT = 4
report = ns.Eligibility:Verify()
Check("disagreement is detected", report and report.agrees, false)
Check("a recorded active outfit scores the rules", report and report.activeRecorded, true)

-- Outfit 5 was never recorded, so it could not have been matched whatever the rules say.
-- That has to read as "unscorable", not as evidence against the matcher.
ACTIVE_OUTFIT = 5
report = ns.Eligibility:Verify()
Check("unrecorded active outfit is not scorable", report and report.activeRecorded, false)

-- Blizzard applied the less constrained of two eligible outfits. That is the random pick
-- among equals, which the Retail run observed, so it must score as agreement.
ACTIVE_OUTFIT = 2
report = ns.Eligibility:Verify()
Check("any eligible outfit agrees", report and report.agrees, true)
Check("applied outfit reported eligible", report and report.activeEligible, true)
ACTIVE_OUTFIT = 3

-- An edit committed while the cache was not looking leaves an entry describing assignments
-- the outfit no longer has (seen in game: an outfit reset to Defaults kept its old entry).
-- situationCategories names the constrained categories, so the contradiction is detectable.
print("stale entries:")
OUTFITS[2].situationCategories = {} -- Rest reset to all wildcards; the cache still says Rest Area
Check("entry contradicting situationCategories is stale", ns.OutfitCache:IsStale(3, OUTFITS[2]), true)
local _, staleReason = ns.Eligibility:Match(3, ns.Eligibility:GetCurrentKeys(), OUTFITS[2])
Check("stale entry is not matched", staleReason, "changed since last viewed")
Check("stale entry counts as unrecorded", #ns.OutfitCache:GetUnrecordedOutfits(), 2)
report = ns.Eligibility:Verify()
Check("stale active outfit is not scorable", report and report.activeRecorded, false)
OUTFITS[2].situationCategories = { "Locations" }
Check("agreeing entry is not stale", ns.OutfitCache:IsStale(3, OUTFITS[2]), false)
OUTFITS[2].situationCategories = nil

-- Deleting an outfit must drop its cache entry the next time the outfit list is consulted.
print("prune:")
table.remove(OUTFITS, 3) -- Raiding (id 4) is gone
ns.OutfitCache:GetUnrecordedOutfits()
Check("deleted outfit pruned", ns.OutfitCache:Get(4), nil)
Check("count follows", ns.OutfitCache:Count(), 2)

-- The scan must refuse rather than silently record wrong data when the transmog window is
-- shut, since ChangeViewedOutfit would not take effect.
print("scan guards:")
chat = {}
TransmogFrame = nil
Check("refuses without the transmog window", ns.OutfitCache:Scan(), false)

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
