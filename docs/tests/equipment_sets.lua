-- Exercises the Equipment Sets trigger, which no real capture has covered yet.
-- Three scenarios: a fully equipped set, a partially equipped one, and an id mismatch
-- between C_EquipmentSet and the situation option.
local ROOT = arg[1] or "."

local SCENARIO = arg[2] or "equipped"

Enum = { TransmogSituation = {} }

local function Opt(name, situationID, equipmentSetID)
    return {
        name = name,
        value = false,
        option = { situationID = situationID, specID = 0, loadoutID = 0, equipmentSetID = equipmentSetID or 0 },
    }
end

-- Presumed ids 18/19 for the equipment-set pair; the option's own equipmentSetID is what
-- actually matters, so the situationID here is only along for the ride.
local CATEGORIES = {
    { triggerID = 6, name = "Equipment Sets", isRadioButton = false, groupData = { { optionData = {
        -- Verbatim from the Retail dump: ids start at 0, and the All row also carries 0.
        Opt("All Equipment Sets", 18), Opt("plop 1", 19, 0), Opt("prout", 19, 1),
        Opt("haha", 19, 2) } } } },
}

C_TransmogOutfitInfo = {
    GetUISituationCategoriesAndOptions = function() return CATEGORIES end,
    GetActiveOutfitID = function() return 1 end,
    GetOutfitSituationsEnabled = function() return true end,
}

local SETS = {
    -- Set id 0 is the case the old `value ~= 0` guard silently dropped.
    equipped     = { { id = 0, name = "plop 1", isEquipped = true,  numItems = 16, numEquipped = 16 },
                     { id = 1, name = "prout",  isEquipped = false, numItems = 16, numEquipped = 2 } },
    -- All three report isEquipped, exactly as the real dump did.
    allequipped  = { { id = 0, name = "plop 1", isEquipped = true, numItems = 16, numEquipped = 16 },
                     { id = 1, name = "prout",  isEquipped = true, numItems = 16, numEquipped = 16 },
                     { id = 2, name = "haha",   isEquipped = true, numItems = 16, numEquipped = 16 } },
    -- Verbatim from the second Retail dump, after the sets were made distinct:
    -- only "plop 1" is fully equipped, the others are one item short.
    distinct     = { { id = 0, name = "plop 1", isEquipped = true,  numItems = 15, numEquipped = 15 },
                     { id = 1, name = "prout",  isEquipped = false, numItems = 15, numEquipped = 14 },
                     { id = 2, name = "haha",   isEquipped = false, numItems = 15, numEquipped = 14 } },
    partial      = { { id = 0, name = "plop 1", isEquipped = false, numItems = 16, numEquipped = 15 },
                     { id = 1, name = "prout",  isEquipped = false, numItems = 16, numEquipped = 1 } },
    idmismatch   = { { id = 77, name = "Healing", isEquipped = true, numItems = 16, numEquipped = 16 } },
    -- Applied "Healing", then swapped one ring: isEquipped goes false but the player is
    -- still wearing the set in any meaningful sense.
    swappedring  = { { id = 0, name = "plop 1", isEquipped = false, numItems = 16, numEquipped = 15 },
                     { id = 1, name = "prout",  isEquipped = false, numItems = 16, numEquipped = 1 } },
    -- Three match, but the player applied "haha": that one should win the tie.
    specassigned = { { id = 0, name = "plop 1", isEquipped = true, numItems = 16, numEquipped = 16 },
                     { id = 1, name = "prout",  isEquipped = true, numItems = 16, numEquipped = 16 },
                     { id = 2, name = "haha",   isEquipped = true, numItems = 16, numEquipped = 16 } },
    tiebreak     = { { id = 0, name = "plop 1", isEquipped = true, numItems = 16, numEquipped = 16 },
                     { id = 1, name = "prout",  isEquipped = true, numItems = 16, numEquipped = 16 },
                     { id = 2, name = "haha",   isEquipped = true, numItems = 16, numEquipped = 16 } },
}
local ACTIVE = SETS[SCENARIO]

SPEC_ASSIGNED = nil -- equipmentSetID assigned to the current spec, if any

C_EquipmentSet = {
    GetEquipmentSetForSpec = function() return SPEC_ASSIGNED end,
    GetEquipmentSetAssignedSpec = function(id) return (id == SPEC_ASSIGNED) and 1 or nil end,
    GetEquipmentSetIDs = function()
        local ids = {}
        for _, s in ipairs(ACTIVE) do table.insert(ids, s.id) end
        return ids
    end,
    GetEquipmentSetInfo = function(id)
        for _, s in ipairs(ACTIVE) do
            if s.id == id then
                return s.name, 123, s.id, s.isEquipped, s.numItems, s.numEquipped, 0, 0, 0
            end
        end
    end,
}

C_DelvesUI = { HasActiveDelve = function() return false end }
C_PlayerInfo = { GetAlternateFormInfo = function() return false, false end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 259, "Assassination" end,
}
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }

function IsInInstance() return false, "none" end
function IsResting() return false end
function IsIndoors() return false end
function IsSwimming() return false end
function IsMounted() return false end
function IsFlying() return false end
function GetGameTime() return 10, 0 end
function GetRealZoneText() return "Orgrimmar" end
function GetSubZoneText() return "" end
function hooksecurefunc() end
date = os.date

HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
SlashCmdList = {}
local output = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(output, msg) end }
local function StubFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() return f end end })
    return f
end
function CreateFrame() return StubFrame() end

local ns = {}
for _, file in ipairs({ "core/Util.lua", "core/Capabilities.lua", "core/Triggers.lua", "core/OutfitCache.lua",
    "core/Diagnostics.lua", "core/SituationPanel.lua", "BetterSituation.lua" }) do
    local chunk = assert(loadfile(ROOT .. "/" .. file))
    assert(pcall(chunk, "BetterSituation", ns))
end

local api = ns.BetterSituation
ns.Capabilities:Init()
ns.Triggers:Init(api)
ns.Diagnostics:Init(api)

if SCENARIO == "swappedring" then
    ns.Triggers:RememberAppliedSet(0) -- as EQUIPMENT_SWAP_FINISHED would have
elseif SCENARIO == "tiebreak" then
    ns.Triggers:RememberAppliedSet(2)
elseif SCENARIO == "specassigned" then
    -- Three match, nothing applied this session, but "prout" is assigned to this spec.
    SPEC_ASSIGNED = 1
end

local entry = ns.Triggers:ResolveAll()[1]
print(string.format("scenario=%-12s state=%-8s name=%-7s ambiguous=%-5s specAssigned=%-5s reason=%s",
    SCENARIO, entry.result.state, tostring(entry.displayName),
    tostring(entry.result.ambiguous), tostring(entry.result.specAssigned),
    tostring(entry.result.reason)))
output = {}
ns.Diagnostics:PrintEnvironmentSnapshot()
print("   chat: " .. output[1])
