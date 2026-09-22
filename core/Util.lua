local _, ns = ...

local Util = {}
ns.Util = Util

-- House style for every optional Blizzard call: a missing system must no-op, not error.
-- Note this only protects *calls*. Enum members need their own nil check, because indexing
-- a missing enum table happens before any pcall can help (see core/Capabilities.lua).
function Util.SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        return false, nil
    end

    return true, result
end

-- Same contract, but keeps every return value. Needed for the Blizzard APIs that answer
-- with a positional tuple, such as C_EquipmentSet.GetEquipmentSetInfo.
function Util.SafeCallAll(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    local results = { pcall(fn, ...) }
    if not results[1] then
        return false
    end

    return unpack(results)
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
-- across our two target clients (WEATHER_CHANGED does not exist on Retail). Returns the
-- events that were actually registered.
function Util.RegisterEventsSafely(frame, events)
    local registered = {}

    for _, event in ipairs(events or {}) do
        if pcall(frame.RegisterEvent, frame, event) then
            table.insert(registered, event)
        end
    end

    return registered
end
