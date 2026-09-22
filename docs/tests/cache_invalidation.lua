-- Which categories exist is not fixed for the session: saving a first equipment set adds
-- the Equipment Sets category, deleting the last removes it, and Specializations only
-- appears from level 10. The category list was cached once at load, so those changes never
-- appeared without a /reload. This drives the real event to prove they do now.
local ROOT = arg[1] or "."

Enum = { TransmogSituation = {}, WeatherType = { Clear = 0 } }

local function Opt(name, situationID, equipmentSetID)
    return {
        name = name,
        value = false,
        option = { situationID = situationID, specID = 0, loadoutID = 0, equipmentSetID = equipmentSetID or 0 },
    }
end

local LOCATIONS = { triggerID = 3, name = "Locations", isRadioButton = false,
    groupData = { { optionData = { Opt("All Locations", 3), Opt("Rest Area", 4) } } } }
local EQUIPMENT = { triggerID = 6, name = "Equipment Sets", isRadioButton = false,
    groupData = { { optionData = { Opt("All Equipment Sets", 18), Opt("plop 1", 19, 0) } } } }

-- Start with no equipment sets, as a fresh character has.
local CATEGORIES = { LOCATIONS }
-- GetUISituationCategoriesAndOptions is declared MayReturnNothing.
local RETURN_NOTHING = false
local SETS = {}

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function()
        if RETURN_NOTHING then return end
        return CATEGORIES
    end,
    GetActiveOutfitID = function() return 1 end,
    GetCurrentlyViewedOutfitID = function() return 1 end,
    GetOutfitsInfo = function() return {} end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_EquipmentSet = {
    GetEquipmentSetIDs = function() return SETS end,
    GetEquipmentSetInfo = function(id) return "plop 1", 1, id, true, 15, 15, 0, 0, 0 end,
    GetEquipmentSetForSpec = function() return nil end,
    GetEquipmentSetAssignedSpec = function() return nil end,
}
C_DelvesUI = { HasActiveDelve = function() return false end }
C_PlayerInfo = { GetAlternateFormInfo = function() return false, false end }
C_SpecializationInfo = { GetSpecialization = function() return nil end }
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

function IsInInstance() return false, "none" end
function IsResting() return true end
function IsIndoors() return false end
function IsSwimming() return false end
function IsMounted() return false end
function IsFlying() return false end
function GetGameTime() return 12, 0 end
function GetRealZoneText() return "Zone" end
function GetSubZoneText() return "" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function hooksecurefunc() end
date = os.date
time = os.time
HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- A frame stub that actually dispatches events, so the wiring is under test and not just
-- the InvalidateCategories call.
local frames = {}
function CreateFrame()
    local f = { registered = {}, handler = nil }
    function f:SetScript(which, fn) if which == "OnEvent" then self.handler = fn end end
    function f:RegisterEvent(event) self.registered[event] = true end
    function f:UnregisterEvent(event) self.registered[event] = nil end
    function f:UnregisterAllEvents() self.registered = {} end
    function f:HookScript() end
    function f:IsVisible() return false end
    function f:SetPoint() end
    function f:SetHeight() end
    function f:EnableMouse() end
    function f:CreateFontString()
        local fs = {}
        setmetatable(fs, { __index = function() return function() return fs end end })
        return fs
    end
    table.insert(frames, f)
    return f
end

local function FireEvent(event, ...)
    for _, f in ipairs(frames) do
        if f.registered[event] and f.handler then
            f.handler(f, event, ...)
        end
    end
end

local ns = {}
for _, file in ipairs({ "core/Util.lua", "core/Capabilities.lua", "core/Triggers.lua", "core/OutfitCache.lua",
    "core/Diagnostics.lua", "core/SituationPanel.lua", "BetterSituation.lua" }) do
    local chunk = assert(loadfile(ROOT .. "/" .. file))
    assert(pcall(chunk, "BetterSituation", ns))
end
ns.Capabilities:Init()
ns.Triggers:Init(ns.BetterSituation)
ns.Diagnostics:Init(ns.BetterSituation)

local failures = 0
local function Check(label, got, expected)
    local ok = (got == expected)
    if not ok then failures = failures + 1 end
    print(string.format("  %-52s %-12s %s", label, tostring(got), ok and "OK" or ("<<< FAIL, wanted " .. tostring(expected))))
end

print("before any equipment set exists:")
Check("categories", #ns.Triggers:GetCategories(), 1)
Check("Equipment Sets category present", ns.Triggers:GetCategory(6) ~= nil, false)

-- The player saves their first equipment set. Blizzard adds the category; the client would
-- now return it, but nothing has told us to look again.
-- Replace rather than mutate: the client hands back a fresh table each call, so the cache
-- must be holding its own copy for this to be a real staleness test.
CATEGORIES = { LOCATIONS, EQUIPMENT }
SETS = { 0 }

print("after saving a set, before the event:")
Check("still stale (cached)", #ns.Triggers:GetCategories(), 1)

print("after EQUIPMENT_SETS_CHANGED:")
FireEvent("EQUIPMENT_SETS_CHANGED")
Check("categories", #ns.Triggers:GetCategories(), 2)
Check("Equipment Sets resolves", ns.Triggers:GetDisplayName(6, ns.Triggers:Resolve(6)), "plop 1")

-- And the reverse: deleting every set removes the category again.
CATEGORIES = { LOCATIONS }
SETS = {}
FireEvent("EQUIPMENT_SETS_CHANGED")
print("after deleting every set:")
Check("categories", #ns.Triggers:GetCategories(), 1)

-- The swap event must still record the applied set, and must NOT be swallowed by the
-- invalidation branch.
CATEGORIES = { LOCATIONS, EQUIPMENT }
SETS = { 0 }
FireEvent("EQUIPMENT_SETS_CHANGED")
FireEvent("EQUIPMENT_SWAP_FINISHED", true, 0)
print("after EQUIPMENT_SWAP_FINISHED:")
Check("last applied set remembered", ns.Triggers:GetLastAppliedSetID(), 0)

-- An empty answer must not be cached as authoritative: the API may return nothing at any
-- moment, and caching that would pin the addon to "no situations on this client" until one
-- of the CATEGORY_EVENTS happened to fire.
print("transient empty answer:")
ns.Triggers:InvalidateCategories()
RETURN_NOTHING = true
Check("empty while the API is silent", #ns.Triggers:GetCategories(), 0)
RETURN_NOTHING = false
Check("recovers with no event needed", #ns.Triggers:GetCategories(), 2)

-- The `value` flag on each option is a snapshot of the VIEWED outfit's assignments, baked
-- into the tree we cache, so switching outfit must drop it.
print("viewed-outfit events invalidate the tree:")
local viewedEvents = { "VIEWED_TRANSMOG_OUTFIT_CHANGED", "VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED" }
for _, event in ipairs(viewedEvents) do
    local isCategoryEvent = false
    for _, e in ipairs(ns.Triggers.CATEGORY_EVENTS) do
        if e == event then isCategoryEvent = true end
    end
    Check(event .. " invalidates", isCategoryEvent, true)
end

-- The Situations tab must register the category events even when the category they concern
-- does not exist yet, or creating a first set while the tab is open would go unnoticed.
local panelEvents = {}
do
    local before = #frames
    ns.SituationPanel.eventFrame = CreateFrame()
    ns.SituationPanel.situationsFrame = { SituationFramePool = { EnumerateActive = function() return function() end end } }
    ns.SituationPanel:StartTracking()
    for event in pairs(ns.SituationPanel.eventFrame.registered) do
        panelEvents[event] = true
    end
    assert(#frames >= before)
end
print("panel event registration:")
for _, event in ipairs(ns.Triggers.CATEGORY_EVENTS) do
    Check("registers " .. event, panelEvents[event] == true, true)
end

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
