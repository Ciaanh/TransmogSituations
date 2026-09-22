-- Replays the exact /bs dump captured on live Retail: real situationIDs, real option
-- names and order, real player state. Expected values are asserted, so this fails loudly
-- if the mapping regresses.
local ROOT = arg[1] or "."

Enum = { TransmogSituation = {} } -- values deliberately absent: the client owns the IDs

local function Opt(name, situationID, specID)
    return {
        name = name,
        value = false,
        option = { situationID = situationID, specID = specID or 0, loadoutID = 0, equipmentSetID = 0 },
    }
end

-- Verbatim from the dump, including list order.
local CATEGORIES = {
    { triggerID = 3, name = "Locations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Locations", 3), Opt("Rest Area", 4), Opt("House", 7), Opt("Character Select", 8),
        Opt("World", 5), Opt("Delves", 6), Opt("Dungeons", 9), Opt("Raids", 10),
        Opt("Arenas", 11), Opt("Battlegrounds", 12) } } } },
    { triggerID = 4, name = "Movement", isRadioButton = false, groupData = { { optionData = {
        Opt("All Movement", 13), Opt("Unmounted", 14), Opt("Swimming", 15),
        Opt("Ground Mount", 16), Opt("Flying Mount", 17) } } } },
    { triggerID = 5, name = "Specializations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Specializations", 1), Opt("Assassination", 2, 259), Opt("Outlaw", 2, 260),
        Opt("Subtlety", 2, 261) } } } },
    { triggerID = 7, name = "Racial Forms", isRadioButton = false, groupData = { { optionData = {
        Opt("All Racial Forms", 20), Opt("Dracthyr", 21), Opt("Visage", 22) } } } },
    { triggerID = 11, name = "Weather", isRadioButton = false, groupData = { { optionData = {
        Opt("All Weather", 32), Opt("Clear", 33), Opt("Rain", 34), Opt("Snow", 35),
        Opt("Sandstorm", 36) } } } },
    { triggerID = 12, name = "Time of Day", isRadioButton = false, groupData = { { optionData = {
        Opt("All Times", 37), Opt("Morning", 38), Opt("Midday", 39), Opt("Evening", 40),
        Opt("Night", 41) } } } },
}

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return CATEGORIES end,
    GetActiveOutfitID = function() return 3 end,
    GetCurrentlyViewedOutfitID = function() return 3 end,
    -- Matches the in-game list: "Rest" is second on screen but carries outfitID 3.
    GetOutfitsInfo = function()
        return {
            { outfitID = 2, name = "Combat", playerFacingOutfitIndex = 1,
              situationCategories = { "Locations" }, isEventOutfit = false, isDisabled = false },
            { outfitID = 3, name = "Rest", playerFacingOutfitIndex = 2,
              situationCategories = { "Locations" }, isEventOutfit = false, isDisabled = false },
        }
    end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_DelvesUI = { HasActiveDelve = function() return false end }
INSIDE_HOUSE = false -- outdoors in the neighborhood, per the capture
INSTANCE_TYPE = "neighborhood"
C_Housing = {
    IsInsideHouse = function() return INSIDE_HOUSE end,
    IsInsideHouseOrPlot = function() return true end,
    IsOnNeighborhoodMap = function() return true end,
}
C_EquipmentSet = {
    GetEquipmentSetIDs = function() return {} end,
    GetEquipmentSetInfo = function() return nil end,
}
C_PlayerInfo = { GetAlternateFormInfo = function() return true, true end } -- dracthyr in visage
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 259, "Assassination" end,
}
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

-- Raw player state exactly as the dump reported it.
function IsInInstance() return true, INSTANCE_TYPE end
function IsResting() return true end
function IsIndoors() return false end
function IsSwimming() return false end
function IsMounted() return true end
function IsFlying() return false end
function GetGameTime() return 23, 3 end
function GetRealZoneText() return "Neighborhood" end
function GetSubZoneText() return "" end
function hooksecurefunc() end
date = os.date

HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
local output = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(output, msg) end }
local function StubFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() return f end end })
    return f
end
function CreateFrame() return StubFrame() end

local ns = {}
for _, file in ipairs({ "core/Util.lua", "core/Capabilities.lua", "core/Triggers.lua", "core/OutfitCache.lua",
    "core/Diagnostics.lua", "core/SituationPanel.lua", "BetterSituation.lua" }) do
    local chunk, err = loadfile(ROOT .. "/" .. file)
    if not chunk then print("LOAD FAIL " .. file .. ": " .. tostring(err)); os.exit(1) end
    local ok, runErr = pcall(chunk, "BetterSituation", ns)
    if not ok then print("RUN FAIL " .. file .. ": " .. tostring(runErr)); os.exit(1) end
end

local api = ns.BetterSituation
ns.Capabilities:Init()
ns.Triggers:Init(api)
ns.Diagnostics:Init(api)

-- What the player was actually doing, per the dump.
local EXPECTED = {
    [3] = "Rest Area", -- in the neighborhood but NOT inside the house
    [4] = "Ground Mount",
    [5] = "Assassination",
    [7] = "Visage",
    [11] = nil, -- C_Weather absent on Retail
    [12] = "Night",
}

local failures = 0
print("trigger | expected          | got                | state")
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    local want = EXPECTED[entry.triggerID]
    local got = entry.displayName
    local ok = (want == got)
    if entry.triggerID == 11 then
        ok = (entry.result.state == "unsupported")
    end
    if not ok then failures = failures + 1 end
    print(string.format("%-7s | %-17s | %-18s | %-11s %s",
        entry.triggerID, tostring(want), tostring(got), entry.result.state,
        ok and "OK" or "<<< FAIL"))
end

print("")
print("also-true for Locations: " .. table.concat(ns.Triggers:GetAlsoNames(3,
    ns.Triggers:Resolve(3)), ", "))
print("")
output = {}
ns.Diagnostics:PrintEnvironmentSnapshot()
for _, line in ipairs(output) do print("  " .. line) end

-- Inside the house, as captured on Retail 2026-09-22: the instance type switches to "interior"
-- (not "neighborhood"), IsInsideHouse goes true, and the player is still resting.
INSIDE_HOUSE = true
INSTANCE_TYPE = "interior"
ns.Triggers:InvalidateCategories()
local inside = ns.Triggers:Resolve(3)
local insideName = ns.Triggers:GetDisplayName(3, inside)
local insideAlso = table.concat(ns.Triggers:GetAlsoNames(3, inside), ", ")
print(string.format("inside the house -> %s (+ %s)", tostring(insideName), insideAlso))
if insideName ~= "House" then failures = failures + 1 print("<<< FAIL: expected House") end
if insideAlso ~= "Rest Area" then failures = failures + 1 print("<<< FAIL: expected Rest Area alongside") end

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
