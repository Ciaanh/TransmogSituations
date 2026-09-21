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

-- The situationID values the live clients actually use. These are NOT the values in
-- Enum.TransmogSituation / the generated API docs, which say LocationHouse=4 and
-- TimeNight=31; the real numbering is a permutation on a different base.
--
-- Captured with /bs dump on both targets. Every option present on both carries the SAME id
-- on both, so the id is the stable identity. What varies is which options exist at all:
-- Forever has no House (7) and no Delves (6). That rules out identifying an option by its
-- position in the category -- position 5 is "World" on Retail but "Dungeons" on Forever.
--
-- Ids 18/19 are presumed to be the equipment-set pair and 23-31 are unaccounted for; neither
-- is needed, because those categories are matched on equipmentSetID / specID instead.
local SITUATION = {
    AllSpecs = 1,
    Spec = 2,
    AllLocations = 3,
    LocationRested = 4,
    LocationWorld = 5,
    LocationDelves = 6,
    LocationHouse = 7,
    LocationCharacterSelect = 8,
    LocationDungeons = 9,
    LocationRaids = 10,
    LocationArenas = 11,
    LocationBattlegrounds = 12,
    AllMovement = 13,
    MovementUnmounted = 14,
    MovementSwimming = 15,
    MovementGroundMount = 16,
    MovementFlyingMount = 17,
    AllRacialForms = 20,
    FormNative = 21,
    FormNonNative = 22,
    AllWeather = 32,
    WeatherClear = 33,
    WeatherRain = 34,
    WeatherSnow = 35,
    WeatherSand = 36,
    AllTime = 37,
    TimeMorning = 38,
    TimeDay = 39,
    TimeEvening = 40,
    TimeNight = 41
}
Triggers.SITUATION = SITUATION

-- The per-category "any value" options, for the Phase 4 matcher.
Triggers.WILDCARD_SITUATIONS = {
    [SITUATION.AllSpecs] = true,
    [SITUATION.AllLocations] = true,
    [SITUATION.AllMovement] = true,
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
-- Category data. Localized names come from here.
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
    self.options = nil
end

function Triggers:GetCategory(triggerID)
    for _, category in ipairs(self:GetCategories()) do
        if category.triggerID == triggerID then
            return category
        end
    end

    return nil
end

-- Every option of a category, flattened across groups. The order is whatever the client
-- gave us and carries NO meaning: an option is identified by its situationID, never by its
-- position. Forever omits House and Delves, which shifts every later position.
function Triggers:GetOptions(triggerID)
    self.options = self.options or {}
    if self.options[triggerID] then
        return self.options[triggerID]
    end

    local ordered = {}
    local category = self:GetCategory(triggerID)

    for _, groupData in ipairs(category and category.groupData or {}) do
        for _, optionData in ipairs(groupData.optionData or {}) do
            table.insert(ordered, optionData)
        end
    end

    self.options[triggerID] = ordered
    return ordered
end

-- Find the option carrying a situationID. Returns nil when this client doesn't offer it,
-- which is a real answer (Forever has no House), not a failure to be papered over.
function Triggers:FindOptionBySituation(triggerID, situationID)
    if not situationID then
        return nil
    end

    for _, optionData in ipairs(self:GetOptions(triggerID)) do
        local option = optionData.option
        if option and option.situationID == situationID then
            return optionData
        end
    end

    return nil
end

-- Specializations and Equipment Sets have a variable number of options, all sharing one
-- situationID, so they are told apart by the id the option carries.
function Triggers:FindOptionByField(triggerID, field, value)
    if not value then
        return nil
    end

    for _, optionData in ipairs(self:GetOptions(triggerID)) do
        local option = optionData.option
        if option and option[field] == value and value ~= 0 then
            return optionData
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

        -- Locations is a checkbox category and genuinely multi-valued: standing in a
        -- neighborhood also counts as resting. Report the most specific as the value and
        -- keep the rest in `also` so the Phase 4 matcher can use them.
        local resting = IsResting()

        local function Primary(situationID)
            local also = {}
            if resting and situationID ~= SITUATION.LocationRested then
                table.insert(also, SITUATION.LocationRested)
            end

            return Result(STATE_OK, situationID, { also = also })
        end

        if inInstance then
            if instanceType == "arena" then
                return Primary(SITUATION.LocationArenas)
            end

            if instanceType == "pvp" then
                return Primary(SITUATION.LocationBattlegrounds)
            end

            if instanceType == "raid" then
                return Primary(SITUATION.LocationRaids)
            end

            if instanceType == "party" then
                if ns.Capabilities.hasDelves then
                    local ok, hasActiveDelve = SafeCall(C_DelvesUI.HasActiveDelve)
                    if ok and hasActiveDelve then
                        return Primary(SITUATION.LocationDelves)
                    end
                end

                return Primary(SITUATION.LocationDungeons)
            end

            -- Player housing reports as the "neighborhood" instance type, but that covers
            -- both the outdoor plots and the house interior. Only the interior is House --
            -- Blizzard uses IsInsideHouse() for exactly this indoor/outdoor split.
            if instanceType == "neighborhood" then
                local insideHouse = false
                if ns.Capabilities.hasHousing then
                    local ok, inside = SafeCall(C_Housing.IsInsideHouse)
                    insideHouse = (ok and inside) and true or false
                end

                if insideHouse then
                    return Primary(SITUATION.LocationHouse)
                end

                -- Standing outdoors in the neighborhood: fall through to the open-world
                -- handling below, which reports Rest Area when the area is rested.
            else
                return Unknown("instanceType=" .. tostring(instanceType))
            end
        end

        if resting then
            return Primary(SITUATION.LocationRested)
        end

        return Primary(SITUATION.LocationWorld)
    end
}

resolvers[UI_TRIGGER.Movement] = {
    -- Mount state has an event, but swimming and flying do not, so this is the one
    -- resolver that genuinely needs polling.
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
                return Result(STATE_OK, nil, { equipmentSetID = setID })
            end
        end

        -- Having sets but wearing none is a real state, not a failure. isEquipped only goes
        -- true when every non-ignored item of the set is worn, so a single swapped piece
        -- lands here.
        return Unknown(string.format("no set fully equipped (%d sets)", #setIDs))
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

        -- Confirmed in game on a Dracthyr: visage reports inAlternateForm = true, and the
        -- category lists the racial form ("Dracthyr", 21) before visage (22).
        return Result(
            STATE_OK,
            inAlternateForm and SITUATION.FormNonNative or SITUATION.FormNative
        )
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

        local extra = { intensity = tonumber(weather.intensity) or 0 }

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

        -- Enum.WeatherType.Miscellaneous has no counterpart in the category.
        return Unknown("weather type " .. tostring(weather.type))
    end
}

-- UNVERIFIED: the client's own labels are All Times / Morning / Midday / Evening / Night,
-- but the hour each band starts at is still a guess. Confirmed datapoints so far:
-- 23:03 -> Night, 14:08 -> Midday. See docs/ROADMAP.md, open question 2.
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

-- Attach the client's own option to a resolved value: its localized name, and confirmation
-- that this client offers the situation at all.
function Triggers:AttachOption(triggerID, result)
    if result.state ~= STATE_OK then
        return result
    end

    local optionData = nil

    if result.specID then
        optionData = self:FindOptionByField(triggerID, "specID", result.specID)
    elseif result.equipmentSetID then
        optionData = self:FindOptionByField(triggerID, "equipmentSetID", result.equipmentSetID)
    else
        optionData = self:FindOptionBySituation(triggerID, result.situationID)
    end

    if not optionData then
        -- This client doesn't offer the situation we resolved to. Say so plainly rather
        -- than falling back to a neighbouring option.
        result.state = STATE_UNKNOWN
        if result.specID then
            result.reason = "no option with specID " .. tostring(result.specID)
        elseif result.equipmentSetID then
            result.reason = "no option with equipmentSetID " .. tostring(result.equipmentSetID)
        else
            result.reason = "no option with situationID " .. tostring(result.situationID)
        end
        return result
    end

    result.optionName = optionData.name
    result.option = optionData.option
    result.isAssigned = optionData.value and true or false

    return result
end

function Triggers:Resolve(triggerID)
    local resolver = resolvers[triggerID]
    if not resolver then
        return Unsupported("no resolver for trigger " .. tostring(triggerID))
    end

    local ok, result = pcall(resolver.Resolve)
    if not ok or type(result) ~= "table" then
        return Unknown("resolver error")
    end

    return self:AttachOption(triggerID, result)
end

-- Localized display name for a resolved value, straight from the client's option list.
function Triggers:GetDisplayName(triggerID, result)
    return result and result.optionName or nil
end

-- The other situations that are also true right now (Locations is multi-valued), as the
-- client's own display names. Silently skips any this client doesn't offer.
function Triggers:GetAlsoNames(triggerID, result)
    local names = {}

    for _, situationID in ipairs(result and result.also or {}) do
        local optionData = self:FindOptionBySituation(triggerID, situationID)
        if optionData then
            table.insert(names, optionData.name)
        end
    end

    return names
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
                displayName = self:GetDisplayName(category.triggerID, result),
                alsoNames = self:GetAlsoNames(category.triggerID, result)
            }
        )
    end

    return resolved
end

-- The union of the events the *active* categories care about. Restricted to categories the
-- client actually offers, so we never try to register an event this client doesn't know --
-- RegisterEvent throws on an unknown event name, and WEATHER_CHANGED is exactly that on
-- Retail. Callers should still register defensively; see ns.Util.RegisterEventsSafely.
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
