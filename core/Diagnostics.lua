local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        return false, nil
    end

    return true, result
end

local function InferTimeOfDay(hour)
    if type(hour) ~= "number" then
        return "Unknown"
    end

    if hour >= 6 and hour < 12 then
        return "Morning"
    end

    if hour >= 12 and hour < 17 then
        return "Midday"
    end

    if hour >= 17 and hour < 21 then
        return "Evening"
    end

    return "Night"
end

-- C_Weather.GetCurrentWeather() returns { type = Enum.WeatherType, intensity = 0-1 };
local WEATHER_TYPE_NAMES = {
    [Enum.WeatherType.Clear] = "Clear",
    [Enum.WeatherType.Rain] = "Rain",
    [Enum.WeatherType.Snow] = "Snow",
    [Enum.WeatherType.Sandstorm] = "Sandstorm",
    [Enum.WeatherType.Miscellaneous] = "Miscellaneous"
}

local function FormatWeather(weather)
    if type(weather) ~= "table" then
        return "Unknown"
    end

    local name = WEATHER_TYPE_NAMES[weather.type]
    if not name then
        return string.format("Unknown (type %s)", tostring(weather.type))
    end

    if weather.type == Enum.WeatherType.Clear then
        return name
    end

    return string.format("%s (%d%%)", name, math.floor((tonumber(weather.intensity) or 0) * 100 + 0.5))
end

Diagnostics.FormatWeather = FormatWeather

local function DetectForms()
    local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
    if not hasAlternateForm then
        return "N/A"
    end

    return inAlternateForm and "Alternate Form" or "Native Form"
end

local function DetectMovement()
    if IsSwimming("player") then
        return "Swimming"
    end

    if IsMounted() then
        if IsFlying("player") then
            return "Flying Mount"
        end
        return "Ground Mount"
    end

    return "Unmounted"
end

local function DetectLocation()
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "arena" then
            return "Arenas"
        end

        if instanceType == "pvp" then
            return "Battlegrounds"
        end

        if instanceType == "raid" then
            return "Raids"
        end

        if instanceType == "party" then
            local hasActiveDelve = false
            if C_DelvesUI and C_DelvesUI.HasActiveDelve then
                local okDelve, result = SafeCall(C_DelvesUI.HasActiveDelve)
                hasActiveDelve = okDelve and result and true or false
            end

            if hasActiveDelve then
                return "Delves"
            end

            return "Dungeons"
        end
    end

    if IsResting() then
        return "Rest Area"
    end

    if IsIndoors() then
        return "House"
    end

    return "World"
end

function Diagnostics:CollectEnvironmentSnapshot()
    local hour, minute = GetGameTime()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID, specName = nil, "Unknown"
    if specIndex then
        specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end

    local weather = C_Weather.GetCurrentWeather()

    local okOutfit, activeOutfitID = SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)

    return {
        collectedAt = date("%Y-%m-%d %H:%M:%S"),
        activeOutfitID = okOutfit and activeOutfitID or 0,
        location = DetectLocation(),
        movement = DetectMovement(),
        specializationName = specName or "Unknown",
        specializationID = specID,
        weather = weather,
        forms = DetectForms(),
        serverHour = hour,
        serverMinute = minute,
        timeOfDay = InferTimeOfDay(hour),
        zone = GetRealZoneText() or "Unknown",
        subZone = GetSubZoneText() or ""
    }
end

function Diagnostics:PrintEnvironmentSnapshot()
    local env = self:CollectEnvironmentSnapshot()

    self.api:Print("Environment " .. env.collectedAt)
    self.api:Print("Active outfit ID: " .. tostring(env.activeOutfitID))
    self.api:Print("Location: " .. tostring(env.location))
    self.api:Print("Movement: " .. tostring(env.movement))
    self.api:Print(
        string.format(
            "Specialization: %s (%s)",
            tostring(env.specializationName),
            tostring(env.specializationID or "n/a")
        )
    )
    self.api:Print("Weather: " .. FormatWeather(env.weather))
    self.api:Print("Forms: " .. tostring(env.forms))
    self.api:Print(
        string.format(
            "Time of Day: %s (server %02d:%02d)",
            tostring(env.timeOfDay),
            tonumber(env.serverHour) or 0,
            tonumber(env.serverMinute) or 0
        )
    )
    if env.subZone and env.subZone ~= "" then
        self.api:Print(string.format("Zone: %s - %s", tostring(env.zone), tostring(env.subZone)))
    else
        self.api:Print("Zone: " .. tostring(env.zone))
    end
end

function Diagnostics:Init(api)
    self.api = api

    self.watching = false
    self.lastSnapshot = nil
end

function Diagnostics:CollectSnapshot()
    local snapshot = {
        collectedAt = date("%Y-%m-%d %H:%M:%S"),
        situationsEnabled = false,
        activeOutfitID = 0,
        categories = {},
        activeCriteria = {}
    }

    local okEnabled, situationsEnabled = SafeCall(C_TransmogOutfitInfo.GetOutfitSituationsEnabled)
    if okEnabled then
        snapshot.situationsEnabled = situationsEnabled and true or false
    end

    local okOutfit, activeOutfitID = SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
    if okOutfit and type(activeOutfitID) == "number" then
        snapshot.activeOutfitID = activeOutfitID
    end

    local okCategories, categories = SafeCall(C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions)
    if okCategories and type(categories) == "table" then
        for _, category in ipairs(categories) do
            local categoryEntry = {
                triggerID = category.triggerID,
                name = category.name,
                isRadioButton = category.isRadioButton and true or false,
                options = {}
            }

            for _, groupData in ipairs(category.groupData or {}) do
                for _, optionData in ipairs(groupData.optionData or {}) do
                    local option = optionData.option or {}
                    local okActive, isActive = SafeCall(C_TransmogOutfitInfo.GetOutfitSituation, option)
                    local isSelected = optionData.value and true or false
                    local optionEntry = {
                        name = optionData.name or "Unknown",
                        active = isSelected,
                        resolved = okActive and (isActive and true or false) or nil,
                        situationID = option.situationID,
                        specID = option.specID,
                        loadoutID = option.loadoutID,
                        equipmentSetID = option.equipmentSetID
                    }

                    table.insert(categoryEntry.options, optionEntry)

                    if optionEntry.active then
                        table.insert(
                            snapshot.activeCriteria,
                            {
                                triggerID = categoryEntry.triggerID,
                                triggerName = categoryEntry.name,
                                optionName = optionEntry.name,
                                situationID = optionEntry.situationID
                            }
                        )
                    end
                end
            end

            table.insert(snapshot.categories, categoryEntry)
        end
    end

    self.lastSnapshot = snapshot
    return snapshot
end

function Diagnostics:PrintCategoriesList()
    local snapshot = self:CollectSnapshot()

    self.api:Print("Trigger Categories and Options:")
    self.api:Print("================================")

    for _, category in ipairs(snapshot.categories) do
        self.api:Print("")
        self.api:Print(string.format("[Trigger %d] %s:", category.triggerID, category.name))

        for _, option in ipairs(category.options) do
            local marker = option.active and "|cff00ff00[SELECTED]|r" or "  "
            self.api:Print(string.format("  %s %s", marker, option.name))
        end
    end

    self.api:Print("")
    self.api:Print("================================")
end
