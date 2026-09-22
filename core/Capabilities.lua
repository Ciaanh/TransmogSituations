local _, ns = ...

-- Phase 0: one place that answers "does this client have that system?".
-- Forever exposes more than Retail (C_Weather is the notable gap), so every optional
-- subsystem is probed once here instead of being re-tested ad hoc at each call site.

local Capabilities = {}
ns.Capabilities = Capabilities

function Capabilities:Init()
    self.hasSituations = type(C_TransmogOutfitInfo) == "table" and
        type(C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions) == "function"

    -- Retail has no C_Weather at all; indexing Enum.WeatherType there is a load-time error.
    self.hasWeather = type(C_Weather) == "table" and type(C_Weather.GetCurrentWeather) == "function" and
        type(Enum) == "table" and type(Enum.WeatherType) == "table"

    self.hasDelves = type(C_DelvesUI) == "table" and type(C_DelvesUI.HasActiveDelve) == "function"

    -- Player housing. Note C_Housing (and C_DelvesUI) exist on Forever too -- confirmed by
    -- /bs dump -- even though that client offers neither the House nor the Delves option. The
    -- API being present says nothing about the option; only the category tree does.
    self.hasHousing = type(C_Housing) == "table" and type(C_Housing.IsInsideHouse) == "function"

    self.hasEquipmentSets = type(C_EquipmentSet) == "table" and
        type(C_EquipmentSet.GetEquipmentSetIDs) == "function"

    -- Sets can be assigned to a specialization; Blizzard sorts those first in its own
    -- Equipment Manager, which makes the assignment a usable precedence signal.
    self.hasSpecEquipmentSets = self.hasEquipmentSets and
        type(C_EquipmentSet.GetEquipmentSetForSpec) == "function"

    self.hasAlternateFormInfo = type(C_PlayerInfo) == "table" and
        type(C_PlayerInfo.GetAlternateFormInfo) == "function"

    -- Saved talent loadouts. The Specializations category lists one option per saved loadout
    -- next to the per-spec option (confirmed on Retail with a mage carrying four loadouts), so
    -- the selected loadout is part of the current value. Present on both clients.
    self.hasTalentLoadouts = type(C_ClassTalents) == "table" and
        type(C_ClassTalents.GetLastSelectedSavedConfigID) == "function"
end
