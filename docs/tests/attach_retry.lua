-- Blizzard_Transmog loads on demand, and being loaded does not guarantee SituationsFrame
-- exists yet. A single attach attempt that gives up, or one that stops listening whether or
-- not it worked, leaves the Situations tab permanently bare for the session.
local ROOT = arg[1] or "."

Enum = { TransmogSituation = {}, WeatherType = { Clear = 0 } }

local function Opt(name, situationID)
    return {
        name = name,
        value = false,
        option = { situationID = situationID, specID = 0, loadoutID = 0, equipmentSetID = 0 },
    }
end

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function()
        return { { triggerID = 3, name = "Locations", isRadioButton = false, groupData = { { optionData = {
            Opt("All Locations", 3), Opt("Rest Area", 4) } } } } }
    end,
    GetActiveOutfitID = function() return 1 end,
    GetCurrentlyViewedOutfitID = function() return 1 end,
    GetOutfitsInfo = function() return {} end,
    GetOutfitSituationsEnabled = function() return true end,
}
C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end, GetEquipmentSetInfo = function() end }
C_DelvesUI = { HasActiveDelve = function() return false end }
C_PlayerInfo = { GetAlternateFormInfo = function() return false, false end }
C_SpecializationInfo = { GetSpecialization = function() return nil end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

TRANSMOG_LOADED = false
C_AddOns = { IsAddOnLoaded = function(name) return name == "Blizzard_Transmog" and TRANSMOG_LOADED end }

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
function hooksecurefunc(t, k) assert(type(t[k]) == "function", "hooksecurefunc on a nil method") end
date = os.date
HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local frames = {}
function CreateFrame()
    local f = { registered = {}, handler = nil }
    function f:SetScript(which, fn) if which == "OnEvent" then self.handler = fn end end
    function f:RegisterEvent(e) self.registered[e] = true end
    function f:UnregisterEvent(e) self.registered[e] = nil end
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
        if f.registered[event] and f.handler then f.handler(f, event, ...) end
    end
end

-- The Situations frame, built only when we say so.
local function BuildSituationsFrame(withMixin)
    local pool = { EnumerateActive = function() return function() end end }
    local frame = {
        SituationFramePool = pool,
        HookScript = function() end,
        IsVisible = function() return false end,
    }
    if withMixin then
        frame.Init = function() end
        frame.Refresh = function() end
    end
    TransmogFrame = { WardrobeCollection = { TabContent = { SituationsFrame = frame } } }
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
    print(string.format("  %-46s %-8s %s", label, tostring(got), ok and "OK" or ("<<< FAIL, wanted " .. tostring(expected))))
end

-- Transmog not loaded at addon load: must not attach, must keep listening.
ns.SituationPanel:Init(ns.BetterSituation)
Check("not attached before Blizzard_Transmog loads", ns.SituationPanel.attached, nil)
Check("still listening", ns.SituationPanel.loader ~= nil, true)

-- Addon loads but the frame is not built yet. This is the case the old code broke on: it
-- unregistered ADDON_LOADED whether or not the attach worked.
TRANSMOG_LOADED = true
TransmogFrame = nil
FireEvent("ADDON_LOADED", "Blizzard_Transmog")
Check("frame absent -> still not attached", ns.SituationPanel.attached, nil)
Check("still listening after a failed attempt", ns.SituationPanel.loader ~= nil, true)

-- Frame appears without the mixin methods: must decline rather than raise.
BuildSituationsFrame(false)
local ok = pcall(function() FireEvent("PLAYER_ENTERING_WORLD") end)
Check("no error when the mixin is missing", ok, true)
Check("declined to attach", ns.SituationPanel.attached, nil)

-- Frame is finally complete.
BuildSituationsFrame(true)
FireEvent("PLAYER_ENTERING_WORLD")
Check("attached once the frame exists", ns.SituationPanel.attached, true)
Check("stopped listening after success", ns.SituationPanel.loader, nil)

print("")
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
