local _, ns = ...

-- Phase 1: the single source of truth for "what is this trigger's value right now?".
--
-- Everything downstream (chat command, Situations tab overlay, standalone panel, and later
-- the eligible-set resolver) reads from here. The canonical answer is always a
-- situationID -- never a display string -- so values can be compared, and so user-facing
-- text can be taken from the localized option names the client already hands us.

local Triggers = {}
ns.Triggers = Triggers

local SafeCall = ns.Util.SafeCall
local SafeCallAll = ns.Util.SafeCallAll

-- UI trigger IDs as returned by GetUISituationCategoriesAndOptions(). These are their own
-- namespace and do NOT line up with Enum.TransmogSituationTrigger (see CLAUDE.md).
local UI_TRIGGER = {
    Location = 3,
    Movement = 4,
    Specialization = 5,
    EquipmentSet = 6,
    Forms = 7,
    Weather = 11,
    TimeOfDay = 12
}
Triggers.UI_TRIGGER = UI_TRIGGER

local STATE_OK = "ok"
local STATE_UNSUPPORTED = "unsupported"
local STATE_UNKNOWN = "unknown"

Triggers.STATE_OK = STATE_OK
Triggers.STATE_UNSUPPORTED = STATE_UNSUPPORTED
Triggers.STATE_UNKNOWN = STATE_UNKNOWN

-- Read an Enum.TransmogSituation member defensively, falling back to the documented numeric
-- value. The enum is identical on Forever and Retail, but a missing enum must not break load.
local function Situation(name, fallback)
    local enum = Enum and Enum.TransmogSituation
    local value = enum and enum[name]
    if type(value) == "number" then
        return value
    end

    return fallback
end

local SITUATION = {
    AllSpecs = Situation("AllSpecs", 0),
    Spec = Situation("Spec", 1),
    AllLocations = Situation("AllLocations", 2),
    LocationRested = Situation("LocationRested", 3),
    LocationHouse = Situation("LocationHouse", 4),
    LocationWorld = Situation("LocationWorld", 6),
    LocationDelves = Situation("LocationDelves", 7),
    LocationDungeons = Situation("LocationDungeons", 8),
    LocationRaids = Situation("LocationRaids", 9),
    LocationArenas = Situation("LocationArenas", 10),
    LocationBattlegrounds = Situation("LocationBattlegrounds", 11),
    AllMovement = Situation("AllMovement", 12),
    MovementUnmounted = Situation("MovementUnmounted", 13),
    MovementSwimming = Situation("MovementSwimming", 14),
    MovementGroundMount = Situation("MovementGroundMount", 15),
    MovementFlyingMount = Situation("MovementFlyingMount", 16),
    AllEquipmentSets = Situation("AllEquipmentSets", 17),
    EquipmentSets = Situation("EquipmentSets", 18),
    AllRacialForms = Situation("AllRacialForms", 19),
    FormNative = Situation("FormNative", 20),
    FormNonNative = Situation("FormNonNative", 21),
    AllWeather = Situation("AllWeather", 22),
    WeatherClear = Situation("WeatherClear", 23),
    WeatherRain = Situation("WeatherRain", 24),
    WeatherSnow = Situation("WeatherSnow", 25),
    WeatherSand = Situation("WeatherSand", 26),
    AllTime = Situation("AllTime", 27),
    TimeMorning = Situation("TimeMorning", 28),
    TimeDay = Situation("TimeDay", 29),
    TimeEvening = Situation("TimeEvening", 30),
    TimeNight = Situation("TimeNight", 31)
}
Triggers.SITUATION = SITUATION

-- The per-category "any value" options. Used by the Phase 4 matcher as wildcards.
Triggers.WILDCARD_SITUATIONS = {
    [SITUATION.AllSpecs] = true,
    [SITUATION.AllLocations] = true,
    [SITUATION.AllMovement] = true,
    [SITUATION.AllEquipmentSets] = true,
    [SITUATION.AllRacialForms] = true,
    [SITUATION.AllWeather] = true,
    [SITUATION.AllTime] = true
}

local function Result(state, situationID, extra)
    local result = extra or {}
    result.state = state
    result.situationID = situationID
    return result
end

local function Unsupported(reason)
    return Result(STATE_UNSUPPORTED, nil, { reason = reason })
end

local function Unknown(reason)
    return Result(STATE_UNKNOWN, nil, { reason = reason })
end

--------------------------------------------------------------------------------
-- Category data (localized names come from here, never from hardcoded strings)
--------------------------------------------------------------------------------

function Triggers:GetCategories()
    if self.categories then
        return self.categories
    end

    if not ns.Capabilities.hasSituations then
        self.categories = {}
        return self.categories
    end

    local ok, categories = SafeCall(C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions)
    self.categories = (ok and type(categories) == "table") and categories or {}

    return self.categories
end

function Triggers:InvalidateCategories()
    self.categories = nil
end

function Triggers:GetCategory(triggerID)
    for _, category in ipairs(self:GetCategories()) do
        if category.triggerID == triggerID then
            return category
        end
    end

    return nil
end

local function OptionMatches(option, result, matchSecondary)
    if option.situationID ~= result.situationID then
        return false
    end

    if not matchSecondary then
        return true
    end

    if result.specID and option.specID ~= result.specID then
        return false
    end

    if result.equipmentSetID and option.equipmentSetID ~= result.equipmentSetID then
        return false
    end

    if result.loadoutID and option.loadoutID ~= result.loadoutID then
        return false
    end

    return true
end

-- Localized display name for a resolved value, taken from the client's own option list.
-- Returns nil when nothing matches, so callers can render a neutral placeholder rather
-- than inventing English text.
function Triggers:GetDisplayName(triggerID, result)
    if not result or result.state ~= STATE_OK or not result.situationID then
        return nil
    end

    local category = self:GetCategory(triggerID)
    if not category then
        return nil
    end

    -- Two passes: an exact match on the secondary IDs (spec/equipment set/loadout) first,
    -- then situationID alone. Spec options share one situationID and differ only by specID,
    -- and a talent loadout may narrow it further than we can resolve.
    for _, matchSecondary in ipairs({ true, false }) do
        for _, groupData in ipairs(category.groupData or {}) do
            for _, optionData in ipairs(groupData.optionData or {}) do
                local option = optionData.option
                if option and OptionMatches(option, result, matchSecondary) then
                    return optionData.name
                end
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Resolvers
--------------------------------------------------------------------------------

local resolvers = {}

resolvers[UI_TRIGGER.Location] = {
    events = {
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_UPDATE_RESTING"
    },
    Resolve = function()
        local inInstance, instanceType = IsInInstance()
        if inInstance then
            if instanceType == "arena" then
                return Result(STATE_OK, SITUATION.LocationArenas)
            end

            if instanceType == "pvp" then
                return Result(STATE_OK, SITUATION.LocationBattlegrounds)
            end

            if instanceType == "raid" then
                return Result(STATE_OK, SITUATION.LocationRaids)
            end

            if instanceType == "party" then
                if ns.Capabilities.hasDelves then
                    local ok, hasActiveDelve = SafeCall(C_DelvesUI.HasActiveDelve)
                    if ok and hasActiveDelve then
                        return Result(STATE_OK, SITUATION.LocationDelves)
                    end
                end

                return Result(STATE_OK, SITUATION.LocationDungeons)
            end

            -- "scenario" and friends have no TransmogSituation counterpart.
            return Unknown("instanceType=" .. tostring(instanceType))
        end

        if IsResting() then
            return Result(STATE_OK, SITUATION.LocationRested)
        end

        -- UNVERIFIED: LocationHouse is assumed to mean player housing, but IsIndoors() is
        -- the only signal available. See docs/ROADMAP.md, open question 1.
        if IsIndoors() then
            return Result(STATE_OK, SITUATION.LocationHouse, { unverified = true })
        end

        return Result(STATE_OK, SITUATION.LocationWorld)
    end
}

resolvers[UI_TRIGGER.Movement] = {
    -- Mount state has PLAYER_MOUNT_DISPLAY_CHANGED, but swimming and flying have no event,
    -- so this is the one resolver that genuinely needs polling.
    events = { "PLAYER_MOUNT_DISPLAY_CHANGED" },
    poll = true,
    Resolve = function()
        if IsSwimming("player") then
            return Result(STATE_OK, SITUATION.MovementSwimming)
        end

        if IsMounted() then
            if IsFlying("player") then
                return Result(STATE_OK, SITUATION.MovementFlyingMount)
            end

            return Result(STATE_OK, SITUATION.MovementGroundMount)
        end

        return Result(STATE_OK, SITUATION.MovementUnmounted)
    end
}

resolvers[UI_TRIGGER.Specialization] = {
    events = { "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" },
    Resolve = function()
        if type(C_SpecializationInfo) ~= "table" then
            return Unsupported("C_SpecializationInfo")
        end

        local okIndex, specIndex = SafeCall(C_SpecializationInfo.GetSpecialization)
        if not okIndex or not specIndex then
            -- No specialization before level 10; the category is hidden in that case.
            return Unknown("no specialization")
        end

        local okInfo, specID = SafeCall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
        if not okInfo or not specID then
            return Unknown("no spec id")
        end

        local loadoutID = nil
        if ns.Capabilities.hasTalentLoadouts then
            local okLoadout, configID = SafeCall(C_ClassTalents.GetActiveConfigID)
            if okLoadout then
                loadoutID = configID
            end
        end

        return Result(STATE_OK, SITUATION.Spec, { specID = specID, loadoutID = loadoutID })
    end
}

resolvers[UI_TRIGGER.EquipmentSet] = {
    events = { "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED" },
    Resolve = function()
        if not ns.Capabilities.hasEquipmentSets then
            return Unsupported("C_EquipmentSet")
        end

        local okIDs, setIDs = SafeCall(C_EquipmentSet.GetEquipmentSetIDs)
        if not okIDs or type(setIDs) ~= "table" then
            return Unknown("no equipment sets")
        end

        for _, setID in ipairs(setIDs) do
            -- GetEquipmentSetInfo returns name, icon, setID, isEquipped, ...
            local okInfo, _name, _icon, _setID, isEquipped = SafeCallAll(C_EquipmentSet.GetEquipmentSetInfo, setID)
            if okInfo and isEquipped then
                return Result(STATE_OK, SITUATION.EquipmentSets, { equipmentSetID = setID })
            end
        end

        -- Having sets but wearing none is a real state, not a failure.
        return Unknown("no set equipped")
    end
}

resolvers[UI_TRIGGER.Forms] = {
    events = { "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" },
    Resolve = function()
        if not ns.Capabilities.hasAlternateFormInfo then
            return Unsupported("C_PlayerInfo.GetAlternateFormInfo")
        end

        local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
        if not hasAlternateForm then
            -- Races without a second form don't get this category at all.
            return Unsupported("race has no alternate form")
        end

        return Result(STATE_OK, inAlternateForm and SITUATION.FormNonNative or SITUATION.FormNative)
    end
}

resolvers[UI_TRIGGER.Weather] = {
    events = { "WEATHER_CHANGED" },
    Resolve = function()
        if not ns.Capabilities.hasWeather then
            -- Retail has no C_Weather. Unsupported, not unknown.
            return Unsupported("C_Weather")
        end

        local ok, weather = SafeCall(C_Weather.GetCurrentWeather)
        if not ok or type(weather) ~= "table" then
            return Unknown("no weather info")
        end

        local intensity = tonumber(weather.intensity) or 0
        local extra = { intensity = intensity }

        if weather.type == Enum.WeatherType.Clear then
            return Result(STATE_OK, SITUATION.WeatherClear, extra)
        end

        if weather.type == Enum.WeatherType.Rain then
            return Result(STATE_OK, SITUATION.WeatherRain, extra)
        end

        if weather.type == Enum.WeatherType.Snow then
            return Result(STATE_OK, SITUATION.WeatherSnow, extra)
        end

        if weather.type == Enum.WeatherType.Sandstorm then
            return Result(STATE_OK, SITUATION.WeatherSand, extra)
        end

        -- Enum.WeatherType.Miscellaneous has no TransmogSituation counterpart.
        -- See docs/ROADMAP.md, open question 5.
        return Unknown("weather type " .. tostring(weather.type))
    end
}

-- UNVERIFIED: these boundaries are guesses carried over from the first implementation.
-- They must be replaced with values sampled in game. See docs/ROADMAP.md, open question 2.
local TIME_BOUNDARIES = {
    { from = 6, to = 12, situation = SITUATION.TimeMorning },
    { from = 12, to = 17, situation = SITUATION.TimeDay },
    { from = 17, to = 21, situation = SITUATION.TimeEvening }
}

resolvers[UI_TRIGGER.TimeOfDay] = {
    poll = true,
    Resolve = function()
        local hour, minute = GetGameTime()
        if type(hour) ~= "number" then
            return Unknown("no game time")
        end

        local extra = { hour = hour, minute = minute, unverified = true }

        for _, boundary in ipairs(TIME_BOUNDARIES) do
            if hour >= boundary.from and hour < boundary.to then
                return Result(STATE_OK, boundary.situation, extra)
            end
        end

        return Result(STATE_OK, SITUATION.TimeNight, extra)
    end
}

Triggers.resolvers = resolvers

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Triggers:Resolve(triggerID)
    local resolver = resolvers[triggerID]
    if not resolver then
        return Unsupported("no resolver for trigger " .. tostring(triggerID))
    end

    local ok, result = pcall(resolver.Resolve)
    if not ok or type(result) ~= "table" then
        return Unknown("resolver error")
    end

    return result
end

-- Resolve every category this client actually offers, in the client's own order.
function Triggers:ResolveAll()
    local resolved = {}

    for _, category in ipairs(self:GetCategories()) do
        local result = self:Resolve(category.triggerID)
        table.insert(
            resolved,
            {
                triggerID = category.triggerID,
                categoryName = category.name,
                result = result,
                displayName = self:GetDisplayName(category.triggerID, result)
            }
        )
    end

    return resolved
end

-- The union of the events the *active* categories care about. Restricted to categories the
-- client actually offers, so we never try to register an event this client doesn't know --
-- RegisterEvent throws on an unknown event name, and WEATHER_CHANGED is exactly that on Retail.
-- Callers should still register defensively; see ns.Util.RegisterEventsSafely.
function Triggers:GetAllEvents()
    local seen, events = {}, {}

    for _, category in ipairs(self:GetCategories()) do
        local resolver = resolvers[category.triggerID]
        for _, event in ipairs(resolver and resolver.events or {}) do
            if not seen[event] then
                seen[event] = true
                table.insert(events, event)
            end
        end
    end

    return events
end

-- True when at least one active category can only be tracked by polling.
function Triggers:NeedsPolling()
    for _, category in ipairs(self:GetCategories()) do
        local resolver = resolvers[category.triggerID]
        if resolver and resolver.poll then
            return true
        end
    end

    return false
end

function Triggers:Init(api)
    self.api = api
    self:InvalidateCategories()
end
