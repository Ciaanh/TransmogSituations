local _, ns = ...

-- Phase 0: one place that answers "does this client have that system?".
-- Forever exposes more than Retail (C_Weather is the notable gap), so every optional
-- subsystem is probed once here instead of being re-tested ad hoc at each call site.

local Capabilities = {}
ns.Capabilities = Capabilities

function Capabilities:Probe()
    self.hasSituations = type(C_TransmogOutfitInfo) == "table" and
        type(C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions) == "function"

    -- Retail has no C_Weather at all; indexing Enum.WeatherType there is a load-time error.
    self.hasWeather = type(C_Weather) == "table" and type(C_Weather.GetCurrentWeather) == "function" and
        type(Enum) == "table" and type(Enum.WeatherType) == "table"

    self.hasDelves = type(C_DelvesUI) == "table" and type(C_DelvesUI.HasActiveDelve) == "function"

    -- Player housing. Absent on Forever, which has no housing at all.
    self.hasHousing = type(C_Housing) == "table" and type(C_Housing.IsInsideHouse) == "function"

    self.hasEquipmentSets = type(C_EquipmentSet) == "table" and
        type(C_EquipmentSet.GetEquipmentSetIDs) == "function"

    -- Sets can be assigned to a specialization; Blizzard sorts those first in its own
    -- Equipment Manager, which makes the assignment a usable precedence signal.
    self.hasSpecEquipmentSets = self.hasEquipmentSets and
        type(C_EquipmentSet.GetEquipmentSetForSpec) == "function"

    self.hasAlternateFormInfo = type(C_PlayerInfo) == "table" and
        type(C_PlayerInfo.GetAlternateFormInfo) == "function"

    self.hasTalentLoadouts = type(C_ClassTalents) == "table" and
        type(C_ClassTalents.GetActiveConfigID) == "function"

    return self
end

function Capabilities:Init()
    self:Probe()
end
