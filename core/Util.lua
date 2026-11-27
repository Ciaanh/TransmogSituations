local _, ns = ...

local Util = {}
ns.Util = Util

-- House style for every optional Blizzard call: a missing function is skipped (false), never an
-- error. An error raised by the call itself is not caught: it reaches BugSack with its stack.
-- Enum members need their own nil check (see core/Capabilities.lua).
function Util.CallIfPresent(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end

    return true, (fn(...))
end

-- Same contract, but keeps every return value. Needed for the Blizzard APIs that answer
-- with a positional tuple, such as C_EquipmentSet.GetEquipmentSetInfo.
function Util.CallAllIfPresent(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    return true, fn(...)
end

-- Per-character key for SavedVariables that must not leak between characters (equipment set
-- ids and outfit ids are both character-scoped). nil until the player unit is available.
function Util.CharacterKey()
    local name = UnitName and UnitName("player") or nil
    if not name then
        return nil
    end

    return string.format("%s-%s", name, (GetRealmName and GetRealmName()) or "")
end

-- RegisterEvent raises on an event name the client doesn't know, which is a live hazard
-- across our two target clients (WEATHER_CHANGED does not exist on Retail): each name is checked
-- with C_EventUtils.IsEventValid (Retail and Forever) first. Returns the events that were
-- actually registered.
function Util.RegisterEventsSafely(frame, events)
    local registered = {}
    local isValid = C_EventUtils and C_EventUtils.IsEventValid

    for _, event in ipairs(events or {}) do
        if not isValid or isValid(event) then
            frame:RegisterEvent(event)
            table.insert(registered, event)
        end
    end

    return registered
end
