local _, ns = ...

-- Chat-facing reporting. All situation values come from ns.Triggers; this module only
-- formats them, plus the few context details (zone, clock) that are not triggers.

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local SafeCall = ns.Util.SafeCall

local UNSUPPORTED_TEXT = "|cff808080n/a|r"
local UNKNOWN_TEXT = "|cffffcc00?|r"

-- Renders one resolved trigger. The value itself is the client's own localized option name;
-- we only add the markers and any numeric detail the option name can't carry.
function Diagnostics:FormatTriggerValue(entry)
    local result = entry.result

    if result.state == ns.Triggers.STATE_UNSUPPORTED then
        return UNSUPPORTED_TEXT
    end

    if result.state == ns.Triggers.STATE_UNKNOWN then
        -- Chat has room for the reason; the inline row on the Situations tab does not.
        if result.reason then
            return string.format("%s |cff808080(%s)|r", UNKNOWN_TEXT, result.reason)
        end

        return UNKNOWN_TEXT
    end

    local text = entry.displayName or UNKNOWN_TEXT

    -- Locations is multi-valued: a neighborhood is also a rest area.
    if entry.alsoNames and #entry.alsoNames > 0 then
        text = string.format("%s |cff808080(+ %s)|r", text, table.concat(entry.alsoNames, ", "))
    end

    if result.intensity and result.intensity > 0 then
        text = string.format("%s (%d%%)", text, math.floor(result.intensity * 100 + 0.5))
    end

    if result.hour then
        text = string.format("%s (%02d:%02d)", text, result.hour, tonumber(result.minute) or 0)
    end

    if result.unverified then
        text = text .. " |cff808080*|r"
    end

    return text
end

function Diagnostics:CollectSnapshot()
    local snapshot = {
        collectedAt = date("%Y-%m-%d %H:%M:%S"),
        triggers = ns.Triggers:ResolveAll(),
        zone = GetRealZoneText() or "",
        subZone = GetSubZoneText() or "",
        activeOutfitID = nil,
        situationsEnabled = nil
    }

    if ns.Capabilities.hasSituations then
        local okOutfit, activeOutfitID = SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
        if okOutfit then
            snapshot.activeOutfitID = activeOutfitID
        end

        local okEnabled, enabled = SafeCall(C_TransmogOutfitInfo.GetOutfitSituationsEnabled)
        if okEnabled then
            snapshot.situationsEnabled = enabled and true or false
        end
    end

    self.lastSnapshot = snapshot
    return snapshot
end

function Diagnostics:PrintEnvironmentSnapshot()
    local snapshot = self:CollectSnapshot()

    if #snapshot.triggers == 0 then
        self.api:Print("No situation categories available on this client.")
        return
    end

    for _, entry in ipairs(snapshot.triggers) do
        self.api:Print(string.format("%s: %s", entry.categoryName, self:FormatTriggerValue(entry)))
    end

    local zone = snapshot.zone
    if snapshot.subZone ~= "" then
        zone = string.format("%s - %s", zone, snapshot.subZone)
    end
    self.api:Print("Zone: " .. zone)

    if snapshot.situationsEnabled ~= nil then
        self.api:Print(
            string.format(
                "Situations: %s | Active outfit: %s",
                snapshot.situationsEnabled and "enabled" or "disabled",
                tostring(snapshot.activeOutfitID or "none")
            )
        )
    end

    self.api:Print("|cff808080* value derived from an unverified heuristic|r")
end

-- Full dump of the configured options for the outfit currently being viewed, with the
-- live value marked. Useful for working out how Blizzard's own matching behaves.
function Diagnostics:PrintCategoriesList()
    local categories = ns.Triggers:GetCategories()

    if #categories == 0 then
        self.api:Print("No situation categories available on this client.")
        return
    end

    for _, category in ipairs(categories) do
        local result = ns.Triggers:Resolve(category.triggerID)
        self.api:Print(string.format("|cffffd100[%d] %s|r", category.triggerID, category.name))

        for _, groupData in ipairs(category.groupData or {}) do
            for _, optionData in ipairs(groupData.optionData or {}) do
                local option = optionData.option or {}
                local isCurrent = result.state == ns.Triggers.STATE_OK and
                    option.situationID == result.situationID and
                    (not result.specID or option.specID == result.specID) and
                    (not result.equipmentSetID or option.equipmentSetID == result.equipmentSetID)

                local marks = ""
                if optionData.value then
                    marks = marks .. " |cff00ff00[assigned]|r"
                end
                if isCurrent then
                    marks = marks .. " |cff00ccff[current]|r"
                end

                self.api:Print(string.format("   %s%s", optionData.name, marks))
            end
        end
    end
end

-- Raw ground truth, for working out what the client actually reports rather than what the
-- generated API docs imply. Prints every option's real IDs next to the resolver's answer,
-- plus the raw player-state calls the resolvers are built on.
function Diagnostics:PrintRawDump()
    local caps = ns.Capabilities
    self.api:Print("|cffffd100-- capabilities --|r")
    self.api:Print(
        string.format(
            "situations=%s weather=%s(C_Weather=%s Enum.WeatherType=%s) equipmentSets=%s delves=%s loadouts=%s",
            tostring(caps.hasSituations),
            tostring(caps.hasWeather),
            type(C_Weather),
            type(Enum and Enum.WeatherType),
            tostring(caps.hasEquipmentSets),
            tostring(caps.hasDelves),
            tostring(caps.hasTalentLoadouts)
        )
    )

    self.api:Print("|cffffd100-- raw player state --|r")
    local inInstance, instanceType = IsInInstance()
    self.api:Print(
        string.format(
            "IsInInstance=%s/%s IsResting=%s IsIndoors=%s",
            tostring(inInstance),
            tostring(instanceType),
            tostring(IsResting()),
            tostring(IsIndoors())
        )
    )
    self.api:Print(
        string.format(
            "IsSwimming=%s IsMounted=%s IsFlying=%s",
            tostring(IsSwimming("player")),
            tostring(IsMounted()),
            tostring(IsFlying("player"))
        )
    )

    if caps.hasHousing then
        local _okHouse, insideHouse = SafeCall(C_Housing.IsInsideHouse)
        local _okPlot, insidePlot = SafeCall(C_Housing.IsInsideHouseOrPlot)
        local _okMap, onMap = SafeCall(C_Housing.IsOnNeighborhoodMap)
        self.api:Print(
            string.format(
                "Housing IsInsideHouse=%s IsInsideHouseOrPlot=%s IsOnNeighborhoodMap=%s",
                tostring(insideHouse),
                tostring(insidePlot),
                tostring(onMap)
            )
        )
    end

    local hasAlt, inAlt = nil, nil
    if caps.hasAlternateFormInfo then
        hasAlt, inAlt = C_PlayerInfo.GetAlternateFormInfo()
    end
    local hour, minute = GetGameTime()
    self.api:Print(
        string.format(
            "AlternateForm has=%s in=%s | GetGameTime=%s:%s",
            tostring(hasAlt),
            tostring(inAlt),
            tostring(hour),
            tostring(minute)
        )
    )

    if caps.hasWeather then
        local okWeather, weather = SafeCall(C_Weather.GetCurrentWeather)
        self.api:Print(
            string.format(
                "Weather ok=%s type=%s intensity=%s",
                tostring(okWeather),
                tostring(weather and weather.type),
                tostring(weather and weather.intensity)
            )
        )
    end

    if caps.hasEquipmentSets then
        local _ok, setIDs = SafeCall(C_EquipmentSet.GetEquipmentSetIDs)
        if type(setIDs) == "table" then
            self.api:Print(string.format("|cffffd100-- equipment sets (%d) --|r", #setIDs))
            for _, setID in ipairs(setIDs) do
                local okInfo, name, _icon, realSetID, isEquipped, numItems, numEquipped, _numInv, numLost, numIgnored =
                    ns.Util.SafeCallAll(C_EquipmentSet.GetEquipmentSetInfo, setID)
                self.api:Print(
                    string.format(
                        "   id=%s realSetID=%s %s | isEquipped=%s items=%s/%s lost=%s ignored=%s ok=%s",
                        tostring(setID),
                        tostring(realSetID),
                        tostring(name),
                        tostring(isEquipped),
                        tostring(numEquipped),
                        tostring(numItems),
                        tostring(numLost),
                        tostring(numIgnored),
                        tostring(okInfo)
                    )
                )
            end
        end
    end

    self.api:Print("|cffffd100-- categories (name | situationID spec loadout equipSet) --|r")
    for _, category in ipairs(ns.Triggers:GetCategories()) do
        local result = ns.Triggers:Resolve(category.triggerID)
        self.api:Print(
            string.format(
                "|cffffd100[%d] %s|r radio=%s -> state=%s situationID=%s specID=%s equipSetID=%s",
                category.triggerID,
                category.name,
                tostring(category.isRadioButton),
                tostring(result.state),
                tostring(result.situationID),
                tostring(result.specID),
                tostring(result.equipmentSetID)
            )
        )

        for _, groupData in ipairs(category.groupData or {}) do
            for _, optionData in ipairs(groupData.optionData or {}) do
                local option = optionData.option or {}
                self.api:Print(
                    string.format(
                        "   %-28s | %s %s %s %s%s",
                        tostring(optionData.name),
                        tostring(option.situationID),
                        tostring(option.specID),
                        tostring(option.loadoutID),
                        tostring(option.equipmentSetID),
                        optionData.value and " |cff00ff00[assigned]|r" or ""
                    )
                )
            end
        end
    end
end

function Diagnostics:Init(api)
    self.api = api
    self.lastSnapshot = nil
end
