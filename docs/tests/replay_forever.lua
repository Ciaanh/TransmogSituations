-- Replays the /bs dump captured on the Forever beta. Note Locations here is MISSING
-- House (7) and Delves (6), which is what rules out identifying options by position.
local ROOT = arg[1] or "."

Enum = {
    TransmogSituation = {}, -- deliberately empty: the client owns the ids
    WeatherType = { Clear = 0, Rain = 1, Snow = 2, Sandstorm = 3, Miscellaneous = 4 },
}

local function Opt(name, situationID, specID)
    return {
        name = name,
        value = false,
        option = { situationID = situationID, specID = specID or 0, loadoutID = 0, equipmentSetID = 0 },
    }
end

-- Verbatim from the Forever dump, including the gaps.
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
    { triggerID = 11, name = "Weather", isRadioButton = false, groupData = { { optionData = {
        Opt("All Weather", 32), Opt("Clear", 33), Opt("Rain", 34), Opt("Snow", 35),
        Opt("Sand", 36) } } } },
    { triggerID = 12, name = "Time of Day", isRadioButton = false, groupData = { { optionData = {
        Opt("All Times", 37), Opt("Morning", 38), Opt("Midday", 39), Opt("Evening", 40),
        Opt("Night", 41) } } } },
}

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return CATEGORIES end,
    GetActiveOutfitID = function() return 1 end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_Weather = { GetCurrentWeather = function() return { type = 0, intensity = 0 } end }
C_DelvesUI = { HasActiveDelve = function() return false end }
C_EquipmentSet = {
    GetEquipmentSetIDs = function() return {} end,
    GetEquipmentSetInfo = function() return nil end,
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
function GetGameTime() return 14, 8 end
function GetRealZoneText() return "Stormwind" end
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

local EXPECTED = {
    [3] = "Rest Area",
    [4] = "Unmounted",
    [5] = "Hunter",
    [11] = "Clear",
    [12] = "Midday",
}

local failures = 0
print("trigger | expected          | got                | state")
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    local want, got = EXPECTED[entry.triggerID], entry.displayName
    local ok = (want == got)
    if not ok then failures = failures + 1 end
    print(string.format("%-7s | %-17s | %-18s | %-11s %s",
        entry.triggerID, tostring(want), tostring(got), entry.result.state,
        ok and "OK" or "<<< FAIL"))
end

-- The critical cross-client check: position 5 of Locations is "Dungeons" here but "World"
-- on Retail, so anything position-based would silently return the wrong option.
local opts = ns.Triggers:GetOptions(3)
print("")
print(string.format("Locations position 5 on this client = %s (Retail: World)", opts[5].name))
local house = ns.Triggers:FindOptionBySituation(3, ns.Triggers.SITUATION.LocationHouse)
print("House (7) offered here? " .. tostring(house ~= nil) .. "  <- correctly absent")

print("")
output = {}
ns.Diagnostics:PrintEnvironmentSnapshot()
for _, line in ipairs(output) do print("  " .. line) end

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
