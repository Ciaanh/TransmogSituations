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

-- Events after which the set of categories itself may differ: saving a first equipment set
-- adds the Equipment Sets category, deleting the last removes it, and Specializations only
-- appears from level 10. Anything caching category-derived state must react to these.
-- The last two are about content rather than composition: each option carries a `value`
-- flag saying whether it is assigned to the *currently viewed* outfit, and that flag is
-- baked into the tree we cache. Blizzard refetches the whole tree on these, so we must too,
-- or /bs list keeps reporting the previous outfit's assignments.
Triggers.CATEGORY_EVENTS = {
    "EQUIPMENT_SETS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_LEVEL_UP",
    "PLAYER_ENTERING_WORLD",
    "VIEWED_TRANSMOG_OUTFIT_CHANGED",
    "VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED"
}

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
-- Ids 23-31 are still unaccounted for. Equipment set ids start at 0, and the "All Equipment
-- Sets" row also carries equipmentSetID 0, so a set is identified by situationID 19 plus its
-- equipmentSetID -- never by the field alone.
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
    AllEquipmentSets = 18,
    EquipmentSets = 19,
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

    -- The API is declared MayReturnNothing. Caching an empty answer would pin the addon to
    -- "this client has no situations" until one of the CATEGORY_EVENTS happened to fire,
    -- which can be as far off as the next loading screen. Only a non-empty answer is worth
    -- keeping; re-asking costs one call.
    if ok and type(categories) == "table" and #categories > 0 then
        self.categories = categories
        return self.categories
    end

    return {}
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

    -- No category yet (the tree may not have been fetched, or this row is one Blizzard
    -- built before our fetch succeeded): answer empty, but don't remember it. Caching the
    -- miss would pin the row to "no option" until the next category event.
    if not category then
        return ordered
    end

    for _, groupData in ipairs(category.groupData or {}) do
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

-- Specializations and Equipment Sets have a variable number of options that all share one
-- situationID, so they are told apart by the ids the option carries. Every field given must
-- match: equipment set ids start at 0 and "All Equipment Sets" also carries equipmentSetID 0,
-- so a field alone is ambiguous -- the situationID separates the All row (18) from a specific
-- set (19), exactly as it separates All Specializations (1) from a spec (2). Specializations
-- go one level deeper: the per-spec option carries loadoutID 0 and each saved talent loadout
-- gets its own option with the same specID and its configID as loadoutID (confirmed on Retail),
-- so loadoutID must be part of the match or a loadout option is mistaken for its spec.
function Triggers:FindOptionBySituationAndFields(triggerID, situationID, fields)
    for _, optionData in ipairs(self:GetOptions(triggerID)) do
        local option = optionData.option
        if option and option.situationID == situationID then
            local all = true
            for field, value in pairs(fields) do
                if option[field] ~= value then
                    all = false
                    break
                end
            end

            if all then
                return optionData
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Last applied equipment set
--
-- There is no "currently selected set" API. GetEquipmentSetInfo's isEquipped means "all
-- non-ignored slots are equipped", so swapping a single ring makes the set you are plainly
-- wearing report false. EQUIPMENT_SWAP_FINISHED does carry (result, setID), so the set the
-- player last applied can be tracked and remembered across sessions.
--------------------------------------------------------------------------------

function Triggers:RememberAppliedSet(setID)
    self.lastAppliedSetID = setID

    local db = ns.BetterSituation and ns.BetterSituation.db
    local key = ns.Util.CharacterKey()
    if not db or not key then
        return
    end

    db.lastAppliedSet = db.lastAppliedSet or {}
    db.lastAppliedSet[key] = setID
end

-- The equipment set assigned to the player's current specialization, if any.
-- Note GetEquipmentSetForSpec takes the spec *index*, not a specID.
function Triggers:GetSpecAssignedSetID()
    if not ns.Capabilities.hasSpecEquipmentSets or type(C_SpecializationInfo) ~= "table" then
        return nil
    end

    local okIndex, specIndex = SafeCall(C_SpecializationInfo.GetSpecialization)
    if not okIndex or not specIndex then
        return nil
    end

    local okSet, equipmentSetID = SafeCall(C_EquipmentSet.GetEquipmentSetForSpec, specIndex)
    return okSet and equipmentSetID or nil
end

function Triggers:GetLastAppliedSetID()
    if self.lastAppliedSetID then
        return self.lastAppliedSetID
    end

    local db = ns.BetterSituation and ns.BetterSituation.db
    local key = ns.Util.CharacterKey()
    if db and key and db.lastAppliedSet then
        self.lastAppliedSetID = db.lastAppliedSet[key]
    end

    return self.lastAppliedSetID
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
            -- Delves first, independent of the instance type. Blizzard's own instance banner
            -- (InstanceDifficultyMixin:IsInDelve) asks C_DelvesUI.HasActiveDelve() without
            -- looking at the type, and delves are reported as "scenario" as often as "party".
            if ns.Capabilities.hasDelves then
                local ok, hasActiveDelve = SafeCall(C_DelvesUI.HasActiveDelve)
                if ok and hasActiveDelve then
                    return Primary(SITUATION.LocationDelves)
                end
            end

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
                return Primary(SITUATION.LocationDungeons)
            end

            -- Player housing. Confirmed on Retail (2026-09-22): the outdoor plots report as
            -- "neighborhood" and the inside of a house as "interior" -- the two types Blizzard's
            -- instance banner hides itself for. Either way only IsInsideHouse() decides House;
            -- it is the exact indoor/outdoor split Blizzard uses.
            if instanceType == "neighborhood" or instanceType == "interior" then
                local insideHouse = false
                if ns.Capabilities.hasHousing then
                    local ok, inside = SafeCall(C_Housing.IsInsideHouse)
                    insideHouse = (ok and inside) and true or false
                end

                if insideHouse then
                    return Primary(SITUATION.LocationHouse)
                end

                -- Standing outdoors on the plots: fall through to the open-world handling
                -- below, which reports Rest Area when the area is rested.
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
    -- The loadout events exist on both clients (ClassTalentsDocumentation.lua); registration
    -- is defensive anyway.
    events = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "SELECTED_LOADOUT_CHANGED",
        "ACTIVE_COMBAT_CONFIG_CHANGED",
        "TRAIT_CONFIG_UPDATED",
        "TRAIT_CONFIG_LIST_UPDATED",
        "PLAYER_ENTERING_WORLD"
    },
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
        -- specId is documented non-nilable with Default = 0, so a character without a chosen
        -- specialization yields 0 rather than nil -- and 0 is truthy in Lua. Left unchecked
        -- that resolves to "ok" and then fails to match any option, reporting a misleading
        -- "no option with specID 0" instead of simply having no specialization.
        if not okInfo or not specID or specID == 0 then
            return Unknown("no specialization chosen")
        end

        -- Saved talent loadouts are options of their own (specID + loadoutID), listed next to
        -- the per-spec option (specID + loadoutID 0). Blizzard's talent frame identifies the
        -- current one with GetLastSelectedSavedConfigID(specID); nil means no saved loadout is
        -- selected (fresh character, or the starter build). Whether Blizzard still counts a
        -- loadout that has unsaved changes is unknown -- /bs verify will tell.
        local loadoutID = nil
        if ns.Capabilities.hasTalentLoadouts then
            local okLoadout, configID = SafeCall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
            if okLoadout and type(configID) == "number" and configID > 0 then
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

        local lastAppliedID = Triggers:GetLastAppliedSetID()
        local lastAppliedStillExists = false
        local lastAppliedNumItems, lastAppliedNumEquipped = nil, nil
        local equipped = {}

        for _, setID in ipairs(setIDs) do
            -- GetEquipmentSetInfo returns name, icon, setID, isEquipped, numItems, numEquipped, ...
            local okInfo, _name, _icon, _setID, isEquipped, numItems, numEquipped =
                SafeCallAll(C_EquipmentSet.GetEquipmentSetInfo, setID)

            if okInfo and isEquipped then
                table.insert(equipped, setID)
            end

            if setID == lastAppliedID then
                lastAppliedStillExists = true
                lastAppliedNumItems = numItems
                lastAppliedNumEquipped = numEquipped
            end
        end

        -- Several sets can report isEquipped at once. Confirmed in game: the check is purely
        -- "are these items on your body", so sets saved from identical gear all match
        -- simultaneously, and Blizzard's own Equipment Manager just ticks every one of them.
        -- Make the sets differ by a single item and only the worn one matches, which is the
        -- common case -- but the tie still has to be broken deliberately, not by list order.
        if #equipped > 0 then
            -- 1. What the player actually applied. Strongest evidence of intent.
            for _, setID in ipairs(equipped) do
                if setID == lastAppliedID then
                    return Result(STATE_OK, SITUATION.EquipmentSets, { equipmentSetID = setID })
                end
            end

            -- 2. The set assigned to the current spec. Blizzard sorts spec-assigned sets
            --    first in SortEquipmentSetIDs, so this is their own precedence.
            local specAssignedID = Triggers:GetSpecAssignedSetID()
            for _, setID in ipairs(equipped) do
                if setID == specAssignedID then
                    return Result(
                        STATE_OK,
                        SITUATION.EquipmentSets,
                        { equipmentSetID = setID, specAssigned = true }
                    )
                end
            end

            -- 3. Nothing distinguishes them. Pick one, but say so.
            return Result(
                STATE_OK,
                SITUATION.EquipmentSets,
                {
                    equipmentSetID = equipped[1],
                    ambiguous = (#equipped > 1) and #equipped or nil
                }
            )
        end

        -- Nothing matches exactly. isEquipped only goes true when every non-ignored slot of
        -- the set is worn, so one swapped piece drops it -- yet the player is still, in any
        -- meaningful sense, wearing the set they last applied. Fall back to that, flagged as
        -- approximate so it is never mistaken for an exact match.
        if lastAppliedStillExists then
            return Result(
                STATE_OK,
                SITUATION.EquipmentSets,
                {
                    equipmentSetID = lastAppliedID,
                    approximate = true,
                    numItems = lastAppliedNumItems,
                    numEquipped = lastAppliedNumEquipped
                }
            )
        end

        return Unknown(string.format("no set equipped, none applied this session (%d sets)", #setIDs))
    end
}

resolvers[UI_TRIGGER.Forms] = {
    -- UNIT_FORM_CHANGED is the alternate-form event: TransmogCharacterMixin:OnShow registers
    -- exactly this, guarded by GetAlternateFormInfo(). UPDATE_SHAPESHIFT_FORM is the
    -- shapeshift-bar event and does not cover Dracthyr visage or Worgen Two Forms; it is kept
    -- only because it costs nothing and covers form changes this resolver may later care about.
    events = { "UNIT_FORM_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" },
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
--
-- Several categories are multi-valued, and the resolvers express that in two ways: Locations
-- lists extra situationIDs in `also` (a house is also a rest area), and Specializations is
-- both the spec and, when one is selected, the saved loadout (specID + loadoutID). Both are
-- normalised here into `result.alsoOptions`, the other option entries that are true right now,
-- so no consumer has to know how a category spells its secondary values.
function Triggers:AttachOption(triggerID, result)
    if result.state ~= STATE_OK then
        return result
    end

    local optionData = nil
    local alsoOptions = {}

    if result.specID then
        -- The per-spec option is the one every client lists; a loadout option is more specific
        -- and becomes the value when this client offers it, with the spec option kept alongside.
        local specOption =
            self:FindOptionBySituationAndFields(triggerID, result.situationID, { specID = result.specID, loadoutID = 0 })
        local loadoutOption = nil
        if result.loadoutID then
            loadoutOption = self:FindOptionBySituationAndFields(
                triggerID,
                result.situationID,
                { specID = result.specID, loadoutID = result.loadoutID }
            )
        end

        if loadoutOption then
            optionData = loadoutOption
            if specOption then
                table.insert(alsoOptions, specOption)
            end
        else
            optionData = specOption
        end
    elseif result.equipmentSetID then
        optionData = self:FindOptionBySituationAndFields(
            triggerID,
            result.situationID,
            { equipmentSetID = result.equipmentSetID }
        )
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

    -- Secondary situationIDs from the resolver. Silently skips any this client doesn't offer.
    for _, situationID in ipairs(result.also or {}) do
        local alsoData = self:FindOptionBySituation(triggerID, situationID)
        if alsoData then
            table.insert(alsoOptions, alsoData)
        end
    end

    result.optionName = optionData.name
    result.option = optionData.option
    result.alsoOptions = alsoOptions

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

-- The other options that are also true right now (a house is also a rest area; a loadout is
-- also its spec), as the client's own display names.
function Triggers:GetAlsoNames(_triggerID, result)
    local names = {}

    for _, optionData in ipairs(result and result.alsoOptions or {}) do
        table.insert(names, optionData.name)
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

    -- Must listen all the time, not just while the Situations tab is open: we would miss
    -- the swap that says which set is worn, and the category list can change composition
    -- while the tab is shut.
    if not self.watcher then
        local watcher = CreateFrame("Frame")
        watcher:SetScript(
            "OnEvent",
            function(_, event, ...)
                if event == "EQUIPMENT_SWAP_FINISHED" then
                    local result, setID = ...
                    if result and setID then
                        self:RememberAppliedSet(setID)
                    end
                    return
                end

                -- Which categories exist is not fixed for the session. Saving a first
                -- equipment set adds the Equipment Sets category, deleting the last one
                -- removes it, and Specializations only appears from level 10. Caching the
                -- category list forever meant those never showed up without a /reload.
                self:InvalidateCategories()
            end
        )

        local events = { "EQUIPMENT_SWAP_FINISHED" }
        for _, event in ipairs(Triggers.CATEGORY_EVENTS) do
            table.insert(events, event)
        end

        ns.Util.RegisterEventsSafely(watcher, events)

        self.watcher = watcher
    end
end
