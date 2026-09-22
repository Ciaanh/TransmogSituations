---@diagnostic disable: undefined-global, lowercase-global
-- Shared test harness: one set of WoW stubs, one loader, one Check.
--
-- Usage from a test file (run from the repo root, repo root as arg[1]):
--
--   local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")
--   H.categories = { H.Category(3, "Locations", { H.Opt("All Locations", 3), ... }) }
--   H.W.resting = true                 -- world state the stubbed game functions read
--   local ns = H.Load()                -- loads the toc's files, fires ADDON_LOADED
--   H.Check("label", got, expected)
--   H.Done()
--
-- Every stub reads mutable state on H, so a test changes the world by assigning fields, not by
-- redefining globals. A test that needs a different shape for an api may still replace the
-- global or a single function on it before calling H.Load() -- Capabilities probes at load.
local H = {}

H.ROOT = arg[1] or "."
H.failures = 0

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------

-- An option as GetUISituationCategoriesAndOptions returns it. `ids` may set specID, loadoutID
-- and equipmentSetID. `value` is false unless given: no in-game capture has ever shown it true.
function H.Opt(name, situationID, ids, value)
    ids = ids or {}
    return {
        name = name,
        value = value or false,
        option = {
            situationID = situationID,
            specID = ids.specID or 0,
            loadoutID = ids.loadoutID or 0,
            equipmentSetID = ids.equipmentSetID or 0,
        },
    }
end

function H.Category(triggerID, name, options)
    return { triggerID = triggerID, name = name, isRadioButton = false, groupData = { { optionData = options } } }
end

-- Same format as OutfitCache.OptionKey, so tests can assign by key without loading the addon.
function H.Key(option)
    return string.format("%d:%d:%d:%d", option.situationID, option.specID or 0, option.loadoutID or 0,
        option.equipmentSetID or 0)
end

-- The two category trees captured in game, verbatim including list order. Fresh tables on
-- every call, so a test can add or drop categories freely.
local function Locations(forever)
    local opts = { H.Opt("All Locations", 3), H.Opt("Rest Area", 4) }
    -- Forever offers neither House (7) nor Delves (6), which shifts every later position.
    if not forever then table.insert(opts, H.Opt("House", 7)) end
    table.insert(opts, H.Opt("Character Select", 8))
    table.insert(opts, H.Opt("World", 5))
    if not forever then table.insert(opts, H.Opt("Delves", 6)) end
    for _, o in ipairs({ { "Dungeons", 9 }, { "Raids", 10 }, { "Arenas", 11 }, { "Battlegrounds", 12 } }) do
        table.insert(opts, H.Opt(o[1], o[2]))
    end
    return H.Category(3, "Locations", opts)
end

function H.Movement()
    return H.Category(4, "Movement", { H.Opt("All Movement", 13), H.Opt("Unmounted", 14),
        H.Opt("Swimming", 15), H.Opt("Ground Mount", 16), H.Opt("Flying Mount", 17) })
end

function H.Weather(sandName)
    return H.Category(11, "Weather", { H.Opt("All Weather", 32), H.Opt("Clear", 33), H.Opt("Rain", 34),
        H.Opt("Snow", 35), H.Opt(sandName or "Sandstorm", 36) })
end

function H.TimeOfDay()
    return H.Category(12, "Time of Day", { H.Opt("All Times", 37), H.Opt("Morning", 38),
        H.Opt("Midday", 39), H.Opt("Evening", 40), H.Opt("Night", 41) })
end

function H.RacialForms()
    return H.Category(7, "Racial Forms", { H.Opt("All Racial Forms", 20), H.Opt("Dracthyr", 21),
        H.Opt("Visage", 22) })
end

-- Retail, a Dracthyr rogue: Assassination / Outlaw / Subtlety, no equipment sets.
function H.RetailTree()
    return {
        Locations(false),
        H.Movement(),
        H.Category(5, "Specializations", { H.Opt("All Specializations", 1),
            H.Opt("Assassination", 2, { specID = 259 }), H.Opt("Outlaw", 2, { specID = 260 }),
            H.Opt("Subtlety", 2, { specID = 261 }) }),
        H.RacialForms(),
        H.Weather(),
        H.TimeOfDay(),
    }
end

-- Forever beta, a hunter: one class-named spec option, Locations without House and Delves.
function H.ForeverTree()
    return {
        Locations(true),
        H.Movement(),
        H.Category(5, "Specializations", { H.Opt("All Specializations", 1),
            H.Opt("Hunter", 2, { specID = 1485 }) }),
        H.Weather("Sand"),
        H.TimeOfDay(),
    }
end

-- The weather enum as Forever defines it; Retail has neither this nor C_Weather.
function H.EnableWeather(weatherType)
    Enum.WeatherType = { Clear = 0, Rain = 1, Snow = 2, Sandstorm = 3, Miscellaneous = 4 }
    H.W.weather = weatherType or 0
    C_Weather = { GetCurrentWeather = function() return { type = H.W.weather, intensity = H.W.weatherIntensity or 0 } end }
end

-- The names of the options that are also true, as consumers show them.
function H.AlsoNames(result)
    local names = {}
    for _, optionData in ipairs(result and result.alsoOptions or {}) do
        table.insert(names, optionData.name)
    end
    return table.concat(names, ", ")
end

--------------------------------------------------------------------------------
-- State the stubs read
--------------------------------------------------------------------------------

H.categories = {}
H.returnNothing = false -- GetUISituationCategoriesAndOptions is declared MayReturnNothing
H.outfits = {}
H.activeOutfitID = 0
H.viewedOutfitID = 0
H.assigned = {} -- [outfitID] = { [optionKey] = true }: what GetOutfitSituation answers
H.pending = false
H.sets = {} -- { { id, name, isEquipped, numItems, numEquipped } }
H.specAssignedSet = nil
H.loadedAddons = {}

H.W = {
    inInstance = false,
    instanceType = "none",
    resting = false,
    indoors = false,
    swimming = false,
    mounted = false,
    flying = false,
    delve = false,
    insideHouse = false,
    hasAltForm = false,
    inAltForm = false,
    specIndex = nil,
    specID = 0, -- documented non-nilable with Default = 0
    hour = 12,
    minute = 0,
    zone = "Zone",
    subZone = "",
    inCombat = false,
}

--------------------------------------------------------------------------------
-- Frames: enough of the widget api to register events, run scripts and be hooked
--------------------------------------------------------------------------------

H.frames = {}

local function Chain()
    local stub = {}
    setmetatable(stub, { __index = function() return function() return stub end end })
    return stub
end

function H.NewFrame()
    local f = { registered = {}, scripts = {}, hooks = {}, shown = false }

    function f:SetScript(which, fn) self.scripts[which] = fn end
    function f:GetScript(which) return self.scripts[which] end
    function f:HookScript(which, fn)
        self.hooks[which] = self.hooks[which] or {}
        table.insert(self.hooks[which], fn)
    end
    function f:RunScript(which, ...)
        if self.scripts[which] then self.scripts[which](self, ...) end
        for _, fn in ipairs(self.hooks[which] or {}) do fn(self, ...) end
    end
    function f:RegisterEvent(event) self.registered[event] = true end
    function f:UnregisterEvent(event) self.registered[event] = nil end
    function f:UnregisterAllEvents() self.registered = {} end
    function f:IsEventRegistered(event) return self.registered[event] == true end
    function f:Show()
        if not self.shown then self.shown = true; self:RunScript("OnShow") end
    end
    function f:Hide()
        if self.shown then self.shown = false; self:RunScript("OnHide") end
    end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:CreateFontString() return Chain() end
    function f:CreateTexture() return Chain() end

    -- Anything else (SetSize, SetPoint, SetMovable, ...) is accepted and ignored.
    setmetatable(f, { __index = function() return function() return f end end })
    table.insert(H.frames, f)
    return f
end

-- Deliver an event to every frame registered for it, as the client would. The frame list is
-- snapshotted first: a handler that creates frames must not receive the event it is handling.
function H.Fire(event, ...)
    local snapshot = {}
    for i, f in ipairs(H.frames) do snapshot[i] = f end
    for _, f in ipairs(snapshot) do
        if f.registered[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

H.chat = {}
function H.ClearChat() H.chat = {} end

-- Every chat line so far, joined, for "does the output mention X" checks.
function H.ChatText() return table.concat(H.chat, "\n") end

local W = H.W

Enum = { TransmogSituation = {} } -- deliberately empty: the client owns the situation ids

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function()
        if H.returnNothing then return end
        return H.categories
    end,
    GetActiveOutfitID = function() return H.activeOutfitID end,
    GetCurrentlyViewedOutfitID = function() return H.viewedOutfitID end,
    GetOutfitsInfo = function() return H.outfits end,
    GetOutfitSituationsEnabled = function() return true end,
    GetOutfitSituation = function(option)
        local assigned = H.assigned[H.viewedOutfitID]
        return (assigned and assigned[H.Key(option)]) and true or false
    end,
    HasPendingOutfitSituations = function() return H.pending end,
    ChangeViewedOutfit = function(outfitID) H.viewedOutfitID = outfitID end,
    CommitPendingSituations = function() H.pending = false end,
}

C_EquipmentSet = {
    GetEquipmentSetIDs = function()
        local ids = {}
        for _, set in ipairs(H.sets) do table.insert(ids, set.id) end
        return ids
    end,
    GetEquipmentSetInfo = function(id)
        for _, set in ipairs(H.sets) do
            if set.id == id then
                return set.name, 0, set.id, set.isEquipped, set.numItems, set.numEquipped, 0, 0, 0
            end
        end
    end,
    GetEquipmentSetForSpec = function() return H.specAssignedSet end,
}

C_DelvesUI = { HasActiveDelve = function() return W.delve end }
C_Housing = {
    IsInsideHouse = function() return W.insideHouse end,
    IsInsideHouseOrPlot = function() return W.insideHouse end,
    IsOnNeighborhoodMap = function() return W.instanceType == "neighborhood" end,
}
C_PlayerInfo = { GetAlternateFormInfo = function() return W.hasAltForm, W.inAltForm end }
C_SpecializationInfo = {
    GetSpecialization = function() return W.specIndex end,
    GetSpecializationInfo = function() return W.specID end,
}
C_AddOns = { IsAddOnLoaded = function(name) return H.loadedAddons[name] == true end }
-- Tickers do not run by themselves; H.RunTickers() advances them, so a test decides when time
-- passes. After runs at once: nothing in the addon depends on it being deferred.
H.tickers = {}
C_Timer = {
    NewTicker = function(_, fn, iterations)
        local ticker = { fn = fn, remaining = iterations, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        table.insert(H.tickers, ticker)
        return ticker
    end,
    After = function(_, fn) fn() end,
}

-- Fire every live ticker `times` times (default: until the finite ones run out, at most 100).
function H.RunTickers(times)
    for _ = 1, times or 100 do
        local ran = false
        for _, ticker in ipairs(H.tickers) do
            if not ticker.cancelled and (ticker.remaining == nil or ticker.remaining > 0) then
                if ticker.remaining then ticker.remaining = ticker.remaining - 1 end
                ticker.fn(ticker)
                ran = true
            end
        end
        if not ran then return end
    end
end

function H.LiveTickers()
    local n = 0
    for _, ticker in ipairs(H.tickers) do
        if not ticker.cancelled and (ticker.remaining == nil or ticker.remaining > 0) then n = n + 1 end
    end
    return n
end
-- C_Weather and C_ClassTalents are left undefined: Retail has no C_Weather, and only the
-- loadout replay needs C_ClassTalents. A test that wants them defines them before H.Load().

function IsInInstance() return W.inInstance, W.instanceType end
function IsResting() return W.resting end
function IsIndoors() return W.indoors end
function IsSwimming() return W.swimming end
function IsMounted() return W.mounted end
function IsFlying() return W.flying end
function GetGameTime() return W.hour, W.minute end
function GetRealZoneText() return W.zone end
function GetSubZoneText() return W.subZone end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function InCombatLockdown() return W.inCombat end
function time() return 1000 end
date = os.date

function CreateFrame() return H.NewFrame() end
UIParent = H.NewFrame()
UISpecialFrames = {}

-- A real post-hook, so hooks on api tables (CommitPendingSituations) are under test too. It
-- raises on a missing method exactly like the client does.
function hooksecurefunc(target, name, fn)
    if type(target) == "string" then
        target, name, fn = _G, target, name
    end
    local original = target[name]
    assert(type(original) == "function", "hooksecurefunc on a nil method: " .. tostring(name))
    target[name] = function(...)
        local results = { original(...) }
        fn(...)
        return unpack(results)
    end
end

HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(H.chat, msg) end }

--------------------------------------------------------------------------------
-- Loading and checking
--------------------------------------------------------------------------------

-- Load the addon exactly as the client would: the files the toc lists, in its order, then
-- ADDON_LOADED, which runs every module's Init through the real bootstrap.
function H.Load()
    local ns = {}
    for line in io.lines(H.ROOT .. "/BetterSituation.toc") do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:match("^##") then
            local path = H.ROOT .. "/" .. line:gsub("\\", "/")
            local chunk = assert(loadfile(path))
            chunk("BetterSituation", ns)
        end
    end
    H.ns = ns
    H.Fire("ADDON_LOADED", "BetterSituation")
    return ns
end

function H.Check(label, got, expected)
    local ok = (got == expected)
    if not ok then
        H.failures = H.failures + 1
    end
    print(string.format("  %-60s %-18s %s", label, tostring(got),
        ok and "OK" or ("<<< FAIL, wanted " .. tostring(expected))))
end

function H.Section(title)
    print(title .. ":")
end

function H.Done()
    print("")
    print(H.failures == 0 and "ALL PASS" or (H.failures .. " FAILURES"))
    os.exit(H.failures == 0 and 0 or 1)
end

return H
