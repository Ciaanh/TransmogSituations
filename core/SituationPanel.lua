local _, ns = ...

local SituationPanel = {}
ns.SituationPanel = SituationPanel

local REFRESH_INTERVAL = 2

local function IsBlizzardTransmogLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Blizzard_Transmog")
    end

    return IsAddOnLoaded and IsAddOnLoaded("Blizzard_Transmog")
end

local function BuildLines(env)
    local specText = string.format("%s (%s)", tostring(env.specializationName), tostring(env.specializationID or "n/a"))
    local zoneText = (env.subZone and env.subZone ~= "") and string.format("%s - %s", tostring(env.zone), tostring(env.subZone)) or
        tostring(env.zone)
    local weatherText = ns.Diagnostics.FormatWeather(env.weather)
    local timeText = string.format(
        "%s (%02d:%02d)",
        tostring(env.timeOfDay),
        tonumber(env.serverHour) or 0,
        tonumber(env.serverMinute) or 0
    )

    return {
        "Location: " .. tostring(env.location),
        "Movement: " .. tostring(env.movement),
        "Spec: " .. specText,
        "Weather: " .. weatherText,
        "Forms: " .. tostring(env.forms),
        "Time: " .. timeText,
        "Zone: " .. zoneText
    }
end

function SituationPanel:Refresh()
    if not self.body or not ns.Diagnostics then
        return
    end

    local env = ns.Diagnostics:CollectEnvironmentSnapshot()

    local lines = BuildLines(env)
    self.body:SetText(table.concat(lines, "\n"))
end

function SituationPanel:CreateOverlay(situationsFrame)
    -- Anchor above the fixed Apply Changes button.
    local anchorFrame = situationsFrame.ApplyButton or situationsFrame

    local overlay = CreateFrame("Frame", nil, situationsFrame)
    overlay:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 12)
    overlay:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 12)
    overlay:SetHeight(120)

    local header = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", 0, -4)
    header:SetText("Current Conditions")

    local body = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", overlay, "TOPLEFT")
    body:SetPoint("RIGHT", overlay, "RIGHT")
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")

    self.overlay = overlay
    self.body = body
end

function SituationPanel:StartTicking()
    self:Refresh()

    if self.ticker then
        return
    end

    self.ticker = C_Timer.NewTicker(REFRESH_INTERVAL, function()
        self:Refresh()
    end)
end

function SituationPanel:StopTicking()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function SituationPanel:AttachToSituationsFrame()
    
    if self.attached then
        return
    end

    -- WardrobeCollection/TabContent/SituationsFrame only exist once Blizzard_Transmog is loaded (retail only).
    local wardrobeCollection = TransmogFrame and TransmogFrame.WardrobeCollection
    local situationsFrame = wardrobeCollection and wardrobeCollection.TabContent and wardrobeCollection.TabContent.SituationsFrame
    if not situationsFrame then
        return
    end

    self:CreateOverlay(situationsFrame)

    situationsFrame:HookScript("OnShow", function()
        self:StartTicking()
    end)

    situationsFrame:HookScript("OnHide", function()
        self:StopTicking()
    end)

    self.attached = true
end

function SituationPanel:Init(api)
    self.api = api

    if C_TransmogOutfitInfo then
        local situationsData = C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions()
        if situationsData then
            for index, data in ipairs(situationsData) do
                local situationData = {
                    triggerID = data.triggerID,
                    name = data.name,
                    description = data.description,
                    isRadioButton = data.isRadioButton,
                    groupData = data.groupData
                };

                print("Situation Data:", situationData.triggerID, situationData.name)
            end
        end
        
        local situationsEnabled = C_TransmogOutfitInfo.GetOutfitSituationsEnabled()
        if situationsEnabled then
            for triggerID, enabled in pairs(situationsEnabled) do
                print("Situation Enabled:", triggerID, enabled)
            end
        end
    end


    



    if IsBlizzardTransmogLoaded() then
        self:AttachToSituationsFrame()
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript(
        "OnEvent",
        function(_, event, loadedAddon)
            if event == "ADDON_LOADED" and loadedAddon == "Blizzard_Transmog" then
                self:AttachToSituationsFrame()
            end
        end
    )
end
