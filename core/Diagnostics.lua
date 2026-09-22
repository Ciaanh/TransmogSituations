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

    local text = result.optionName or UNKNOWN_TEXT

    -- Multi-valued categories: a house is also a rest area, a loadout is also its spec.
    local alsoNames = {}
    for _, optionData in ipairs(result.alsoOptions or {}) do
        table.insert(alsoNames, optionData.name)
    end
    if #alsoNames > 0 then
        text = string.format("%s |cff808080(+ %s)|r", text, table.concat(alsoNames, ", "))
    end

    if result.intensity and result.intensity > 0 then
        text = string.format("%s (%d%%)", text, math.floor(result.intensity * 100 + 0.5))
    end

    if result.hour then
        text = string.format("%s (%02d:%02d)", text, result.hour, tonumber(result.minute) or 0)
    end

    if result.specAssigned then
        text = text .. " |cff808080(assigned to this spec)|r"
    end

    if result.ambiguous then
        text = string.format("%s |cff808080(%d sets match)|r", text, result.ambiguous)
    end

    if result.approximate then
        text = string.format(
            "%s |cff808080~ (last applied, %s/%s worn)|r",
            text,
            tostring(result.numEquipped or "?"),
            tostring(result.numItems or "?")
        )
    end

    if result.unverified then
        text = text .. " |cff808080*|r"
    end

    return text
end

-- outfitID is an identity, not a position: the list also carries playerFacingOutfitIndex,
-- so the second outfit on screen can perfectly well be id 3. Always report both, plus the
-- name, so an id can never be mistaken for a position again.
function Diagnostics:GetOutfitsByID()
    local byID = {}

    for _, info in ipairs(ns.OutfitCache:GetOutfits()) do
        byID[info.outfitID] = info
    end

    return byID
end

function Diagnostics:DescribeOutfit(outfitID, outfitsByID)
    if not outfitID or outfitID == 0 then
        return "none"
    end

    local info = outfitsByID and outfitsByID[outfitID]
    if not info then
        return string.format("id %s", tostring(outfitID))
    end

    return string.format(
        "%s (#%s, id %s)",
        tostring(info.name),
        tostring(info.playerFacingOutfitIndex),
        tostring(outfitID)
    )
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

        -- The highlight in the outfit list is the *viewed* outfit, not the active one:
        -- Blizzard does SetSelected(elementData.outfitID == GetCurrentlyViewedOutfitID()).
        local okViewed, viewedOutfitID = SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
        if okViewed then
            snapshot.viewedOutfitID = viewedOutfitID
        end

        snapshot.outfitsByID = self:GetOutfitsByID()

        local okEnabled, enabled = SafeCall(C_TransmogOutfitInfo.GetOutfitSituationsEnabled)
        if okEnabled then
            snapshot.situationsEnabled = enabled and true or false
        end
    end

    return snapshot
end

function Diagnostics:PrintEnvironmentSnapshot()
    local snapshot = self:CollectSnapshot()

    if #snapshot.triggers == 0 then
        ns.Print("No situation categories available on this client.")
        return
    end

    local anyUnverified = false
    for _, entry in ipairs(snapshot.triggers) do
        ns.Print(string.format("%s: %s", entry.categoryName, self:FormatTriggerValue(entry)))
        if entry.result.state == ns.Triggers.STATE_OK and entry.result.unverified then
            anyUnverified = true
        end
    end

    local zone = snapshot.zone
    if snapshot.subZone ~= "" then
        zone = string.format("%s - %s", zone, snapshot.subZone)
    end
    ns.Print("Zone: " .. zone)

    if snapshot.situationsEnabled ~= nil then
        ns.Print(
            string.format(
                "Situations: %s | Active outfit: %s",
                snapshot.situationsEnabled and "enabled" or "disabled",
                self:DescribeOutfit(snapshot.activeOutfitID, snapshot.outfitsByID)
            )
        )

        -- Distinct from the active outfit, and it is the one the list highlights.
        if snapshot.viewedOutfitID ~= snapshot.activeOutfitID then
            ns.Print(
                "Viewed outfit (highlighted in the list): " ..
                    self:DescribeOutfit(snapshot.viewedOutfitID, snapshot.outfitsByID)
            )
        end
    end

    if anyUnverified then
        ns.Print("|cff808080* value derived from an unverified heuristic|r")
    end
end

-- Full dump of the configured options for the outfit currently being viewed, with the
-- live value marked. Useful for working out how Blizzard's own matching behaves.
function Diagnostics:PrintCategoriesList()
    local categories = ns.Triggers:GetCategories()

    if #categories == 0 then
        ns.Print("No situation categories available on this client.")
        return
    end

    for _, category in ipairs(categories) do
        local result = ns.Triggers:Resolve(category.triggerID)
        ns.Print(string.format("|cffffd100[%d] %s|r", category.triggerID, category.name))

        -- Compare against the option the resolver actually picked rather than re-deriving
        -- the match here; a second copy of that logic is a copy that drifts.
        local alsoActive = {}
        for _, optionData in ipairs(result.alsoOptions or {}) do
            alsoActive[optionData] = true
        end

        for _, optionData in ipairs(ns.Triggers:GetOptions(category.triggerID)) do
            local marks = ""
            if ns.OutfitCache.IsAssigned(optionData) then
                marks = marks .. " |cff00ff00[assigned]|r"
            end
            if result.option and optionData.option == result.option then
                marks = marks .. " |cff00ccff[current]|r"
            elseif alsoActive[optionData] then
                marks = marks .. " |cff0099cc[also active]|r"
            end

            ns.Print(string.format("   %s%s", optionData.name, marks))
        end
    end
end

-- Raw ground truth, for working out what the client actually reports rather than what the
-- generated API docs imply. Prints every option's real IDs next to the resolver's answer,
-- plus the raw player-state calls the resolvers are built on.
function Diagnostics:PrintRawDump()
    local caps = ns.Capabilities
    ns.Print("|cffffd100-- capabilities --|r")
    ns.Print(
        string.format(
            "situations=%s weather=%s(C_Weather=%s Enum.WeatherType=%s) equipmentSets=%s delves=%s housing=%s",
            tostring(caps.hasSituations),
            tostring(caps.hasWeather),
            type(C_Weather),
            type(Enum and Enum.WeatherType),
            tostring(caps.hasEquipmentSets),
            tostring(caps.hasDelves),
            tostring(caps.hasHousing)
        )
    )

    ns.Print("|cffffd100-- raw player state --|r")
    local inInstance, instanceType = IsInInstance()
    ns.Print(
        string.format(
            "IsInInstance=%s/%s IsResting=%s IsIndoors=%s",
            tostring(inInstance),
            tostring(instanceType),
            tostring(IsResting()),
            tostring(IsIndoors())
        )
    )
    ns.Print(
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
        ns.Print(
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
    ns.Print(
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
        ns.Print(
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
            ns.Print(
                string.format(
                    "|cffffd100-- equipment sets (%d), lastApplied=%s specAssigned=%s --|r",
                    #setIDs,
                    tostring(ns.Triggers:GetLastAppliedSetID()),
                    tostring(ns.Triggers:GetSpecAssignedSetID())
                )
            )
            for _, setID in ipairs(setIDs) do
                local okInfo, name, _icon, realSetID, isEquipped, numItems, numEquipped, _numInv, numLost, numIgnored =
                    ns.Util.SafeCallAll(C_EquipmentSet.GetEquipmentSetInfo, setID)
                ns.Print(
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

    if caps.hasSituations then
        local _okActive, activeID = SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
        local _okViewed, viewedID = SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
        local outfits = ns.OutfitCache:GetOutfits()

        ns.Print(
            string.format(
                "|cffffd100-- outfits (active id=%s, viewed id=%s) --|r",
                tostring(activeID),
                tostring(viewedID)
            )
        )

        for _, info in ipairs(outfits) do
            local marks = ""
            if info.outfitID == activeID then
                marks = marks .. " |cff00ff00[active]|r"
            end
            if info.outfitID == viewedID then
                marks = marks .. " |cff00ccff[viewed]|r"
            end

            ns.Print(
                string.format(
                    "   #%s id=%s %s | situations: %s | event=%s disabled=%s%s",
                    tostring(info.playerFacingOutfitIndex),
                    tostring(info.outfitID),
                    tostring(info.name),
                    table.concat(info.situationCategories or {}, " / "),
                    tostring(info.isEventOutfit),
                    tostring(info.isDisabled),
                    marks
                )
            )
        end
    end

    -- Two assignment columns on purpose: `value` is the flag on the option tree, `api` is
    -- what GetOutfitSituation(option) answers -- the call Blizzard's own dropdown uses. The
    -- cache trusts the api column; this is where a disagreement between them would show.
    ns.Print("|cffffd100-- categories (name | situationID spec loadout equipSet | value api) --|r")
    for _, category in ipairs(ns.Triggers:GetCategories()) do
        local result = ns.Triggers:Resolve(category.triggerID)
        ns.Print(
            string.format(
                "|cffffd100[%d] %s|r radio=%s -> state=%s situationID=%s specID=%s loadoutID=%s equipSetID=%s",
                category.triggerID,
                category.name,
                tostring(category.isRadioButton),
                tostring(result.state),
                tostring(result.situationID),
                tostring(result.specID),
                tostring(result.loadoutID),
                tostring(result.equipmentSetID)
            )
        )

        for _, groupData in ipairs(category.groupData or {}) do
            for _, optionData in ipairs(groupData.optionData or {}) do
                local option = optionData.option or {}
                local assigned, source = ns.OutfitCache.IsAssigned(optionData)
                ns.Print(
                    string.format(
                        "   %-28s | %s %s %s %s | value=%s api=%s%s",
                        tostring(optionData.name),
                        tostring(option.situationID),
                        tostring(option.specID),
                        tostring(option.loadoutID),
                        tostring(option.equipmentSetID),
                        tostring(optionData.value),
                        source == "api" and tostring(assigned) or "-",
                        assigned and " |cff00ff00[assigned]|r" or ""
                    )
                )
            end
        end
    end
end

-- Phase 4 reporting. Eligibility is reconstructed from a cache the player
-- fills by browsing outfits, so the output always says how complete that cache is.
function Diagnostics:PrintEligible()
    if not ns.Capabilities.hasSituations then
        ns.Print("Situations are not available on this client.")
        return
    end

    local eligible, rejected = ns.Eligibility:GetEligible()

    if #eligible == 0 then
        ns.Print("No outfit matches the current situation.")
    else
        -- Unranked on purpose: Blizzard picks among every eligible outfit at random. The
        -- marker is the one it actually applied, not one we prefer.
        local okActive, activeOutfitID = SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
        ns.Print(
            #eligible > 1 and "Eligible outfits (Blizzard picks one at random):" or "Eligible outfit:"
        )
        for _, entry in ipairs(eligible) do
            local marker = (okActive and entry.outfitID == activeOutfitID) and "|cff00ff00>|r" or " "
            ns.Print(
                string.format(
                    "  %s %s (#%s) |cff808080- %s|r",
                    marker,
                    entry.name,
                    tostring(entry.index),
                    #entry.matched > 0 and table.concat(entry.matched, ", ") or "nothing constrained"
                )
            )
        end
    end

    -- Named, not just counted: "never viewed" and "changed since" call for different checks,
    -- and a bare count cannot say which outfit it means.
    local notRecorded = {}
    for _, entry in ipairs(rejected) do
        if ns.Eligibility.IsCacheGap(entry.reason) then
            table.insert(notRecorded, entry)
        end
    end

    if #notRecorded > 0 then
        ns.Print(
            string.format(
                "|cffffcc00%d of %d outfits have never been viewed or changed since, so they cannot be matched yet:|r",
                #notRecorded,
                #eligible + #rejected
            )
        )
        for _, entry in ipairs(notRecorded) do
            ns.Print(
                string.format("  |cffffcc00%s (#%s) - %s|r", entry.name, tostring(entry.index), entry.reason)
            )
        end
        ns.Print("Open the transmog Situations tab and click through them, or use /bs scan.")
    end

    if ns.BetterSituation.db.debug and #rejected > 0 then
        ns.Print("Rejected:")
        for _, entry in ipairs(rejected) do
            ns.Print(string.format("  |cff808080%s - %s|r", entry.name, tostring(entry.reason)))
        end
    end

    if #notRecorded == 0 then
        ns.Print(string.format("|cff808080All %d outfits recorded.|r", ns.OutfitCache:Count()))
    end
end

function Diagnostics:PrintVerify()
    if not ns.Capabilities.hasSituations then
        ns.Print("Situations are not available on this client.")
        return
    end

    local report = ns.Eligibility:Verify()
    if not report then
        ns.Print("Could not read the active outfit.")
        return
    end

    local outfitsByID = self:GetOutfitsByID()

    ns.Print("Blizzard applied: " .. self:DescribeOutfit(report.activeOutfitID, outfitsByID))

    local names = {}
    for _, entry in ipairs(report.eligible) do
        table.insert(names, string.format("%s (#%s)", tostring(entry.name), tostring(entry.index)))
    end
    ns.Print("Eligible: " .. (#names > 0 and table.concat(names, ", ") or "none"))

    if report.agrees then
        if #report.eligible > 1 then
            ns.Print(
                string.format(
                    "|cff00ff00Consistent: the applied outfit is one of the %d eligible (Blizzard picks among them at random).|r",
                    #report.eligible
                )
            )
        else
            ns.Print("|cff00ff00Consistent with our rules.|r")
        end
    elseif not report.activeRecorded then
        -- Not a disagreement: the outfit Blizzard applied has no usable cache entry, so it
        -- was rejected before a single rule was consulted. Saying "the rules are incomplete"
        -- here would be an accusation the run cannot support.
        ns.Print(
            string.format(
                "|cffffcc00Not scored: %s has never been viewed, or has changed since, so it could not be matched at all.|r",
                self:DescribeOutfit(report.activeOutfitID, outfitsByID)
            )
        )
        ns.Print("Open the transmog Situations tab and click through your outfits, or use /bs scan, then try again.")
    else
        -- The one outcome that indicts the rules: the outfit Blizzard applied is recorded and
        -- current, yet we say it does not fit the situation.
        ns.Print(
            string.format(
                "|cffff5555Disagrees - the outfit Blizzard applied does not match our rules: %s.|r",
                tostring(report.activeReason or "not in the outfit list")
            )
        )
        ns.Print("The pick only changes when a situation does, so if one changed since, trigger it again first.")
    end

    ns.Print(
        string.format(
            "|cff808080%d outfits recorded, %d never viewed or changed since.|r",
            report.recorded,
            report.unrecorded
        )
    )
end

