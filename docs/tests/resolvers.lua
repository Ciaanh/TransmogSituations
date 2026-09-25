---@diagnostic disable: undefined-global, lowercase-global
-- Drives every branch of every resolver against the real situationID table.
--
-- Most of these states have never been reached in game: no capture has been in a dungeon,
-- a raid, an arena, flying, or in any weather but Clear. This does not prove the game reports
-- what we assume it does -- only that given those inputs the right option comes back. The
-- in-game checks in docs/ROADMAP.md are still what settles the inputs.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

H.categories = H.RetailTree()
H.EnableWeather(0)

local ns = H.Load()

local LOCATION, MOVEMENT, SPEC, FORMS, WEATHER, TIME = 3, 4, 5, 7, 11, 12

local CASES = {
    -- Locations: every instance type, plus the housing indoor/outdoor split.
    { LOCATION, "arena",                   { inInstance = true, instanceType = "arena" }, "Arenas" },
    { LOCATION, "battleground",            { inInstance = true, instanceType = "pvp" }, "Battlegrounds" },
    { LOCATION, "raid",                    { inInstance = true, instanceType = "raid" }, "Raids" },
    { LOCATION, "dungeon",                 { inInstance = true, instanceType = "party" }, "Dungeons" },
    { LOCATION, "delve",                   { inInstance = true, instanceType = "party", delve = true }, "Delves" },
    -- Blizzard's banner asks HasActiveDelve regardless of type; delves show up as scenarios too.
    { LOCATION, "delve as scenario",       { inInstance = true, instanceType = "scenario", delve = true }, "Delves" },
    { LOCATION, "inside house",            { inInstance = true, instanceType = "neighborhood", insideHouse = true }, "House" },
    -- InstanceDifficulty.lua treats "interior" as the second housing type.
    { LOCATION, "inside house (interior)", { inInstance = true, instanceType = "interior", insideHouse = true }, "House" },
    { LOCATION, "interior, not in house",  { inInstance = true, instanceType = "interior" }, "World" },
    { LOCATION, "neighborhood outdoors",   { inInstance = true, instanceType = "neighborhood", resting = true }, "Rest Area" },
    { LOCATION, "resting",                 { resting = true }, "Rest Area" },
    { LOCATION, "open world",              {}, "World" },
    -- An instance type with no counterpart must not guess.
    { LOCATION, "scenario (unmapped)",     { inInstance = true, instanceType = "scenario" }, nil },

    -- Movement: swimming wins over mounted, flying over ground.
    { MOVEMENT, "unmounted",               {}, "Unmounted" },
    { MOVEMENT, "swimming",                { swimming = true }, "Swimming" },
    { MOVEMENT, "swimming on a mount",     { swimming = true, mounted = true }, "Swimming" },
    { MOVEMENT, "ground mount",            { mounted = true }, "Ground Mount" },
    { MOVEMENT, "flying mount",            { mounted = true, flying = true }, "Flying Mount" },

    -- Specializations. specId is documented non-nilable with Default = 0, and 0 is truthy in
    -- Lua: a specless character must read as unknown, not resolve and then match nothing.
    { SPEC, "a real spec",                 { specIndex = 1, specID = 259 }, "Assassination" },
    { SPEC, "no specialization chosen",    { specIndex = 1, specID = 0 }, nil },
    { SPEC, "no specialization yet",       { specIndex = nil }, nil },

    -- Racial forms.
    { FORMS, "native form",                { hasAltForm = true, inAltForm = false }, "Dracthyr" },
    { FORMS, "alternate form",             { hasAltForm = true, inAltForm = true }, "Visage" },

    -- Weather: only Clear has ever been seen in game.
    { WEATHER, "clear",                    { weather = 0 }, "Clear" },
    { WEATHER, "rain",                     { weather = 1 }, "Rain" },
    { WEATHER, "snow",                     { weather = 2 }, "Snow" },
    { WEATHER, "sandstorm",                { weather = 3 }, "Sandstorm" },
    { WEATHER, "miscellaneous",            { weather = 4 }, nil },

    -- Time of day: boundaries are still invented, so this pins current behaviour only.
    { TIME, "06:00 morning",               { hour = 6 }, "Morning" },
    { TIME, "11:00 morning",               { hour = 11 }, "Morning" },
    { TIME, "12:00 midday",                { hour = 12 }, "Midday" },
    { TIME, "16:00 midday",                { hour = 16 }, "Midday" },
    { TIME, "17:00 evening",               { hour = 17 }, "Evening" },
    { TIME, "20:00 evening",               { hour = 20 }, "Evening" },
    { TIME, "21:00 night",                 { hour = 21 }, "Night" },
    { TIME, "00:00 night",                 { hour = 0 }, "Night" },
    { TIME, "05:00 night",                 { hour = 5 }, "Night" },
}

local DEFAULTS = {}
for k, v in pairs(H.W) do DEFAULTS[k] = v end
local function Reset(world)
    for k in pairs(H.W) do H.W[k] = nil end
    for k, v in pairs(DEFAULTS) do H.W[k] = v end
    for k, v in pairs(world or {}) do H.W[k] = v end
end

for _, case in ipairs(CASES) do
    local triggerID, label, world, expected = case[1], case[2], case[3], case[4]
    Reset(world)
    ns.Triggers:InvalidateCategories()
    H.Check(string.format("[%d] %s", triggerID, label), ns.Triggers:Resolve(triggerID).optionName, expected)
end

Reset({ specIndex = 1, specID = 0 })
H.Check("specless reason", ns.Triggers:Resolve(SPEC).reason, "no specialization chosen")

H.Done()
