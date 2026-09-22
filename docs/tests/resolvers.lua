-- Drives every branch of every resolver against the real situationID table.
--
-- Most of these states have never been reached in game: no capture has been in a dungeon,
-- a raid, an arena, swimming, flying, or in any weather but Clear. This does not prove the
-- game reports what we assume it does -- only that given those inputs the right option comes
-- back. The in-game checks in docs/ROADMAP.md are still what settles the inputs.
local ROOT = arg[1] or "."

Enum = {
    TransmogSituation = {}, -- empty on purpose: the client owns the ids
    WeatherType = { Clear = 0, Rain = 1, Snow = 2, Sandstorm = 3, Miscellaneous = 4 },
}

local function Opt(name, situationID, specID)
    return {
        name = name,
        value = false,
        option = { situationID = situationID, specID = specID or 0, loadoutID = 0, equipmentSetID = 0 },
    }
end

local CATEGORIES = {
    { triggerID = 3, name = "Locations", isRadioButton = false, groupData = { { optionData = {
        Opt("All Locations", 3), Opt("Rest Area", 4), Opt("House", 7), Opt("Character Select", 8),
        Opt("World", 5), Opt("Delves", 6), Opt("Dungeons", 9), Opt("Raids", 10),
        Opt("Arenas", 11), Opt("Battlegrounds", 12) } } } },
    { triggerID = 4, name = "Movement", isRadioButton = false, groupData = { { optionData = {
        Opt("All Movement", 13), Opt("Unmounted", 14), Opt("Swimming", 15),
        Opt("Ground Mount", 16), Opt("Flying Mount", 17) } } } },
    { triggerID = 7, name = "Racial Forms", isRadioButton = false, groupData = { { optionData = {
        Opt("All Racial Forms", 20), Opt("Dracthyr", 21), Opt("Visage", 22) } } } },
    { triggerID = 11, name = "Weather", isRadioButton = false, groupData = { { optionData = {
        Opt("All Weather", 32), Opt("Clear", 33), Opt("Rain", 34), Opt("Snow", 35),
        Opt("Sandstorm", 36) } } } },
    { triggerID = 12, name = "Time of Day", isRadioButton = false, groupData = { { optionData = {
        Opt("All Times", 37), Opt("Morning", 38), Opt("Midday", 39), Opt("Evening", 40),
        Opt("Night", 41) } } } },
}

-- Mutable world state the resolvers read.
local W = {}

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return CATEGORIES end,
    GetActiveOutfitID = function() return 1 end,
    GetCurrentlyViewedOutfitID = function() return 1 end,
    GetOutfitsInfo = function() return {} end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_Weather = { GetCurrentWeather = function() return { type = W.weather, intensity = 0.5 } end }
C_DelvesUI = { HasActiveDelve = function() return W.delve end }
C_Housing = {
    IsInsideHouse = function() return W.insideHouse end,
    IsInsideHouseOrPlot = function() return W.insideHouse end,
    IsOnNeighborhoodMap = function() return W.instanceType == "neighborhood" end,
}
C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end, GetEquipmentSetInfo = function() end }
C_PlayerInfo = { GetAlternateFormInfo = function() return W.hasAltForm, W.inAltForm end }
-- specId is documented non-nilable with Default = 0, so a specless character yields 0.
SPEC_INDEX, SPEC_ID = nil, 0
C_SpecializationInfo = {
    GetSpecialization = function() return SPEC_INDEX end,
    GetSpecializationInfo = function() return SPEC_ID end,
}
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

function IsInInstance() return W.inInstance, W.instanceType end
function IsResting() return W.resting end
function IsIndoors() return false end
function IsSwimming() return W.swimming end
function IsMounted() return W.mounted end
function IsFlying() return W.flying end
function GetGameTime() return W.hour, 0 end
function GetRealZoneText() return "Zone" end
function GetSubZoneText() return "" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function hooksecurefunc() end
date = os.date
HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local function StubFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() return f end end })
    return f
end
function CreateFrame() return StubFrame() end

local ns = {}
for _, file in ipairs({ "core/Util.lua", "core/Capabilities.lua", "core/Triggers.lua",
    "core/Diagnostics.lua", "core/SituationPanel.lua", "BetterSituation.lua" }) do
    local chunk = assert(loadfile(ROOT .. "/" .. file))
    assert(pcall(chunk, "BetterSituation", ns))
end
ns.Capabilities:Init()
ns.Triggers:Init(ns.BetterSituation)
ns.Diagnostics:Init(ns.BetterSituation)

local LOCATION, MOVEMENT, FORMS, WEATHER, TIME = 3, 4, 7, 11, 12

local CASES = {
    -- Locations: every instance type, plus the housing indoor/outdoor split.
    { LOCATION, "arena",                { inInstance = true, instanceType = "arena" }, "Arenas" },
    { LOCATION, "battleground",         { inInstance = true, instanceType = "pvp" }, "Battlegrounds" },
    { LOCATION, "raid",                 { inInstance = true, instanceType = "raid" }, "Raids" },
    { LOCATION, "dungeon",              { inInstance = true, instanceType = "party" }, "Dungeons" },
    { LOCATION, "delve",                { inInstance = true, instanceType = "party", delve = true }, "Delves" },
    -- Blizzard's banner asks HasActiveDelve regardless of type; delves show up as scenarios too.
    { LOCATION, "delve as scenario",    { inInstance = true, instanceType = "scenario", delve = true }, "Delves" },
    { LOCATION, "inside house",         { inInstance = true, instanceType = "neighborhood", insideHouse = true }, "House" },
    -- InstanceDifficulty.lua treats "interior" as the second housing type.
    { LOCATION, "inside house (interior)", { inInstance = true, instanceType = "interior", insideHouse = true }, "House" },
    { LOCATION, "interior, not in house", { inInstance = true, instanceType = "interior" }, "World" },
    { LOCATION, "neighborhood outdoors",{ inInstance = true, instanceType = "neighborhood", resting = true }, "Rest Area" },
    { LOCATION, "resting",              { resting = true }, "Rest Area" },
    { LOCATION, "open world",           {}, "World" },
    -- An instance type with no counterpart must not guess.
    { LOCATION, "scenario (unmapped)",  { inInstance = true, instanceType = "scenario" }, nil },

    -- Movement: swimming wins over mounted, flying over ground.
    { MOVEMENT, "unmounted",            {}, "Unmounted" },
    { MOVEMENT, "swimming",             { swimming = true }, "Swimming" },
    { MOVEMENT, "swimming on a mount",  { swimming = true, mounted = true }, "Swimming" },
    { MOVEMENT, "ground mount",         { mounted = true }, "Ground Mount" },
    { MOVEMENT, "flying mount",         { mounted = true, flying = true }, "Flying Mount" },

    -- Racial forms.
    { FORMS, "native form",             { hasAltForm = true, inAltForm = false }, "Dracthyr" },
    { FORMS, "alternate form",          { hasAltForm = true, inAltForm = true }, "Visage" },

    -- Weather: only Clear has ever been seen in game.
    { WEATHER, "clear",                 { weather = 0 }, "Clear" },
    { WEATHER, "rain",                  { weather = 1 }, "Rain" },
    { WEATHER, "snow",                  { weather = 2 }, "Snow" },
    { WEATHER, "sandstorm",             { weather = 3 }, "Sandstorm" },
    { WEATHER, "miscellaneous",         { weather = 4 }, nil },

    -- Time of day: boundaries are still invented, so this pins current behaviour only.
    { TIME, "06:00 morning",            { hour = 6 }, "Morning" },
    { TIME, "11:00 morning",            { hour = 11 }, "Morning" },
    { TIME, "12:00 midday",             { hour = 12 }, "Midday" },
    { TIME, "16:00 midday",             { hour = 16 }, "Midday" },
    { TIME, "17:00 evening",            { hour = 17 }, "Evening" },
    { TIME, "20:00 evening",            { hour = 20 }, "Evening" },
    { TIME, "21:00 night",              { hour = 21 }, "Night" },
    { TIME, "00:00 night",              { hour = 0 }, "Night" },
    { TIME, "05:00 night",              { hour = 5 }, "Night" },
}

local failures = 0
print(string.format("%-8s %-24s %-14s %-14s %s", "trigger", "state", "expected", "got", ""))
for _, case in ipairs(CASES) do
    local triggerID, label, world, expected = case[1], case[2], case[3], case[4]

    W = { inInstance = false, instanceType = "none", hour = 12, weather = 0 }
    for k, v in pairs(world) do W[k] = v end

    ns.Triggers:InvalidateCategories()
    local result = ns.Triggers:Resolve(triggerID)
    local got = ns.Triggers:GetDisplayName(triggerID, result)

    local ok = (got == expected)
    if not ok then failures = failures + 1 end
    print(string.format("%-8s %-24s %-14s %-14s %s",
        triggerID, label, tostring(expected), tostring(got), ok and "OK" or "<<< FAIL"))
end

-- A character with no chosen specialization reports specID 0, which is truthy. It must read
-- as "no specialization", not as an ok result that then fails to match anything.
do
    local SPEC = 5
    table.insert(CATEGORIES, { triggerID = SPEC, name = "Specializations", isRadioButton = false,
        groupData = { { optionData = { Opt("All Specializations", 1), Opt("Assassination", 2, 259) } } } })
    ns.Triggers:InvalidateCategories()

    SPEC_INDEX, SPEC_ID = 1, 0
    local r = ns.Triggers:Resolve(SPEC)
    print("")
    print("specless character:")
    print(string.format("  %-28s %-10s %s", "state", r.state,
        r.state == "unknown" and "OK" or "<<< FAIL"))
    print(string.format("  %-28s %-10s %s", "reason", tostring(r.reason),
        r.reason == "no specialization chosen" and "OK" or "<<< FAIL"))
    if r.state ~= "unknown" or r.reason ~= "no specialization chosen" then failures = failures + 1 end

    SPEC_INDEX, SPEC_ID = 1, 259
    ns.Triggers:InvalidateCategories()
    local ok = ns.Triggers:GetDisplayName(SPEC, ns.Triggers:Resolve(SPEC))
    print(string.format("  %-28s %-10s %s", "real spec still resolves", tostring(ok),
        ok == "Assassination" and "OK" or "<<< FAIL"))
    if ok ~= "Assassination" then failures = failures + 1 end

    SPEC_INDEX, SPEC_ID = nil, 0
    table.remove(CATEGORIES)
    ns.Triggers:InvalidateCategories()
end

-- A resolved-but-unavailable situation must report unknown, never a neighbouring option.
ns.Triggers:InvalidateCategories()
W = { inInstance = false, instanceType = "none", resting = true, hour = 12, weather = 0 }
local before = ns.Triggers:GetDisplayName(LOCATION, ns.Triggers:Resolve(LOCATION))
if before ~= "Rest Area" then failures = failures + 1 print("<<< FAIL baseline") end

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
