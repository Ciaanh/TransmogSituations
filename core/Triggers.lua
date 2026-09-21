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

-- The live client's situationID values are NOT the documented Enum.TransmogSituation
-- values: they are a permutation with a different base (in game, House=7 and World=5, and
-- Time of Day sits at 37-41 rather than 27-31). Blizzard's own UI never reads situationID
-- either -- it passes the whole option table around as an opaque token -- so there is
-- nothing to anchor a fixed table to.
--
-- What IS stable is the order of the options inside each category, which matches the
-- documented enum order exactly. So we identify a value by its ordinal slot in the
-- category and read the real situationID back out of the client's own data.
local SLOT = {
    All = "All",
    -- Location
    Rested = "Rested",
    House = "House",
    CharacterSelect = "CharacterSelect",
    World = "World",
    Delves = "Delves",
    Dungeons = "Dungeons",
    Raids = "Raids",
    Arenas = "Arenas",
    Battlegrounds = "Battlegrounds",
    -- Movement
    Unmounted = "Unmounted",
    Swimming = "Swimming",
    GroundMount = "GroundMount",
    FlyingMount = "FlyingMount",
    -- Forms
    Native = "Native",
    NonNative = "NonNative",
    -- Weather
    Clear = "Clear",
    Rain = "Rain",
    Snow = "Snow",
    Sand = "Sand",
    -- Time of day
    Morning = "Morning",
    Day = "Day",
    Evening = "Evening",
    Night = "Night"
}
Triggers.SLOT = SLOT

-- Ordinal layout of each category, in the order the client lists its options.
-- Specializations and Equipment Sets are variable length past the leading "All", so their
-- entries are matched on specID / equipmentSetID instead of by position.
local CATEGORY_SLOTS = {
    [UI_TRIGGER.Location] = {
        SLOT.All, SLOT.Rested, SLOT.House, SLOT.CharacterSelect, SLOT.World,
        SLOT.Delves, SLOT.Dungeons, SLOT.Raids, SLOT.Arenas, SLOT.Battlegrounds
    },
    [UI_TRIGGER.Movement] = {
        SLOT.All, SLOT.Unmounted, SLOT.Swimming, SLOT.GroundMount, SLOT.FlyingMount
    },
    [UI_TRIGGER.Specialization] = { SLOT.All },
    [UI_TRIGGER.EquipmentSet] = { SLOT.All },
    [UI_TRIGGER.Forms] = { SLOT.All, SLOT.Native, SLOT.NonNative },
    [UI_TRIGGER.Weather] = { SLOT.All, SLOT.Clear, SLOT.Rain, SLOT.Snow, SLOT.Sand },
    [UI_TRIGGER.TimeOfDay] = {
        SLOT.All, SLOT.Morning, SLOT.Day, SLOT.Evening, SLOT.Night
    }
}
Triggers.CATEGORY_SLOTS = CATEGORY_SLOTS


local function Result(state, slot, extra)
    local result = extra or {}
    result.state = state
    result.slot = slot
    return result
end

local function Unsupported(reason)
    return Result(STATE_UNSUPPORTED, nil, { reason = reason })
end

local function Unknown(reason)
    return Result(STATE_UNKNOWN, nil, { reason = reason })
end

--------------------------------------------------------------------------------
-- Category data. Localized names and the real situationIDs both come from here.
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
    self.orderedOptions = nil
end

function Triggers:GetCategory(triggerID)
    for _, category in ipairs(self:GetCategories()) do
        if category.triggerID == triggerID then
            return category
        end
    end

    return nil
end

-- Options flattened across groups, in the order the client lists them. That order is the
-- thing we rely on, so it is never sorted or reshuffled.
function Triggers:GetOrderedOptions(triggerID)
    self.orderedOptions = self.orderedOptions or {}
    if self.orderedOptions[triggerID] then
        return self.orderedOptions[triggerID]
    end

    local ordered = {}
    local category = self:GetCategory(triggerID)

    for _, groupData in ipairs(category and category.groupData or {}) do
        for _, optionData in ipairs(groupData.optionData or {}) do
            table.insert(ordered, optionData)
        end
    end

    self.orderedOptions[triggerID] = ordered
    return ordered
end

-- The option occupying a named ordinal slot of a category.
function Triggers:GetSlotOption(triggerID, slot)
    local slots = CATEGORY_SLOTS[triggerID]
    if not slots or not slot then
        return nil
    end

    for index, slotName in ipairs(slots) do
        if slotName == slot then
            return self:GetOrderedOptions(triggerID)[index]
        end
    end

    return nil
end

-- Specializations and Equipment Sets have a variable number of options past the leading
-- "All", so they are matched on the ID the option carries rather than by position.
function Triggers:FindOptionByField(triggerID, field, value)
    if not value then
        return nil
    end

    for index, optionData in ipairs(self:GetOrderedOptions(triggerID)) do
        local option = optionData.option
        -- index 1 is the "All ..." entry, whose IDs are all zero.
        if index > 1 and option and option[field] == value then
            return optionData
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Resolvers. Each answers with an ordinal slot (or an ID to match on), never with a
-- raw situationID, because the client owns that number.
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
        local also = {}
        if IsResting() then
            table.insert(also, SLOT.Rested)
        end

        local function Primary(slot)
            local filtered = {}
            for _, other in ipairs(also) do
                if other ~= slot then
                    table.insert(filtered, other)
                end
            end

            return Result(STATE_OK, slot, { also = filtered })
        end

        if inInstance then
            if instanceType == "arena" then
                return Primary(SLOT.Arenas)
            end

            if instanceType == "pvp" then
                return Primary(SLOT.Battlegrounds)
            end

            if instanceType == "raid" then
                return Primary(SLOT.Raids)
            end

            -- Confirmed in game: player housing reports as the "neighborhood" instance type.
            if instanceType == "neighborhood" then
                return Primary(SLOT.House)
            end

            if instanceType == "party" then
                if ns.Capabilities.hasDelves then
                    local ok, hasActiveDelve = SafeCall(C_DelvesUI.HasActiveDelve)
                    if ok and hasActiveDelve then
                        return Primary(SLOT.Delves)
                    end
                end

                return Primary(SLOT.Dungeons)
            end

            return Unknown("instanceType=" .. tostring(instanceType))
        end

        if IsResting() then
            return Primary(SLOT.Rested)
        end

        return Primary(SLOT.World)
    end
}

resolvers[UI_TRIGGER.Movement] = {
    -- Mount state has an event, but swimming and flying do not, so this is the one
    -- resolver that genuinely needs polling.
    events = { "PLAYER_MOUNT_DISPLAY_CHANGED" },
    poll = true,
    Resolve = function()
        if IsSwimming("player") then
            return Result(STATE_OK, SLOT.Swimming)
        end

        if IsMounted() then
            if IsFlying("player") then
                return Result(STATE_OK, SLOT.FlyingMount)
            end

            return Result(STATE_OK, SLOT.GroundMount)
        end

        return Result(STATE_OK, SLOT.Unmounted)
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

        return Result(STATE_OK, nil, { specID = specID, loadoutID = loadoutID })
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

        -- Confirmed in game on a Dracthyr: visage reports inAlternateForm = true, and the
        -- category lists the racial form first ("Dracthyr") and visage second.
        return Result(STATE_OK, inAlternateForm and SLOT.NonNative or SLOT.Native)
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
            return Result(STATE_OK, SLOT.Clear, extra)
        end

        if weather.type == Enum.WeatherType.Rain then
            return Result(STATE_OK, SLOT.Rain, extra)
        end

        if weather.type == Enum.WeatherType.Snow then
            return Result(STATE_OK, SLOT.Snow, extra)
        end

        if weather.type == Enum.WeatherType.Sandstorm then
            return Result(STATE_OK, SLOT.Sand, extra)
        end

        -- Enum.WeatherType.Miscellaneous has no counterpart in the category.
        return Unknown("weather type " .. tostring(weather.type))
    end
}

-- UNVERIFIED: the client's own labels are All Times / Morning / Midday / Evening / Night,
-- but the hour each band starts at is still a guess. 23:03 reading as Night is consistent
-- with this, which is the only point confirmed so far.
-- See docs/ROADMAP.md, open question 2.
local TIME_BOUNDARIES = {
    { from = 6, to = 12, slot = SLOT.Morning },
    { from = 12, to = 17, slot = SLOT.Day },
    { from = 17, to = 21, slot = SLOT.Evening }
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
                return Result(STATE_OK, boundary.slot, extra)
            end
        end

        return Result(STATE_OK, SLOT.Night, extra)
    end
}

Triggers.resolvers = resolvers

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Turn a resolver's answer into the client's own option: its localized name and the real
-- situationID, both read back from the category data rather than assumed.
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
        optionData = self:GetSlotOption(triggerID, result.slot)
    end

    if not optionData then
        result.state = STATE_UNKNOWN
        result.reason = "no option for slot " .. tostring(result.slot or result.specID or result.equipmentSetID)
        return result
    end

    result.optionName = optionData.name
    result.option = optionData.option
    result.situationID = optionData.option and optionData.option.situationID
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

-- The extra slots that are also true right now (Locations is multi-valued), as display names.
function Triggers:GetAlsoNames(triggerID, result)
    local names = {}

    for _, slot in ipairs(result and result.also or {}) do
        local optionData = self:GetSlotOption(triggerID, slot)
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
