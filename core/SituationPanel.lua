local _, ns = ...

-- Phase 2: render each trigger's live value inline, directly under its label on the
-- Situations tab, instead of as one detached block that fights the list for space.
--
-- Blizzard's row (TransmogSituationTemplate) is 554x50 with Title 170 wide (maxLines=2) at
-- TOPLEFT (35,-19) and a 305-wide dropdown anchored RIGHT (-35,-2). That leaves ~9px of
-- horizontal gap, so the value goes under the title, anchored to the title's BOTTOMLEFT so
-- it still lands correctly when a localized title wraps to two lines.

local SituationPanel = {}
ns.SituationPanel = SituationPanel

local POLL_INTERVAL = 1.5

local function IsBlizzardTransmogLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Blizzard_Transmog")
    end

    return IsAddOnLoaded and IsAddOnLoaded("Blizzard_Transmog")
end

local function GetSituationsFrame()
    local wardrobeCollection = TransmogFrame and TransmogFrame.WardrobeCollection
    local tabContent = wardrobeCollection and wardrobeCollection.TabContent
    return tabContent and tabContent.SituationsFrame
end

-- Frames come from a pool and are reused across ReleaseAll()/Acquire() cycles, so the
-- FontString is cached on the frame itself and only ever created once.
local function AcquireValueText(situationFrame)
    if situationFrame.BetterSituationValue then
        return situationFrame.BetterSituationValue
    end

    local title = situationFrame.Title
    if not title then
        return nil
    end

    local value = situationFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    value:SetWidth(title:GetWidth())
    value:SetJustifyH("LEFT")
    value:SetMaxLines(1)
    value:SetWordWrap(false)

    situationFrame.BetterSituationValue = value

    -- The row is ~170px wide, far too narrow for a reason or the multi-value list, so the
    -- detail lives in a tooltip. Without this a "?" on the tab is undiagnosable without
    -- dropping to chat.
    local hover = CreateFrame("Frame", nil, situationFrame)
    hover:SetPoint("TOPLEFT", value, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", 0, 0)
    hover:SetHeight(14)
    hover:EnableMouse(true)
    hover:SetScript(
        "OnEnter",
        function(self)
            local detail = situationFrame.BetterSituationDetail
            if not detail then
                return
            end

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, detail.categoryName)

            for _, line in ipairs(detail.lines) do
                GameTooltip_AddNormalLine(GameTooltip, line)
            end

            GameTooltip:Show()
        end
    )
    hover:SetScript("OnLeave", GameTooltip_Hide)

    situationFrame.BetterSituationHover = hover
    return value
end

-- Everything the narrow row cannot say.
local function BuildTooltipLines(triggerID, result, displayName)
    local lines = {}

    if result.state == ns.Triggers.STATE_OK then
        table.insert(lines, "Current: " .. tostring(displayName))

        local also = ns.Triggers:GetAlsoNames(triggerID, result)
        if #also > 0 then
            table.insert(lines, "Also active: " .. table.concat(also, ", "))
        end

        if result.specAssigned then
            table.insert(lines, "Chosen because it is assigned to your current specialization.")
        end

        if result.ambiguous then
            table.insert(
                lines,
                string.format("%d sets match at once; this pick is arbitrary.", result.ambiguous)
            )
        end

        if result.approximate then
            table.insert(
                lines,
                string.format(
                    "Last applied set; %s of %s items worn.",
                    tostring(result.numEquipped or "?"),
                    tostring(result.numItems or "?")
                )
            )
        end

        if result.unverified then
            table.insert(lines, "Derived from an unverified heuristic.")
        end
    elseif result.state == ns.Triggers.STATE_UNSUPPORTED then
        table.insert(lines, "Not available on this client.")
    else
        table.insert(lines, "Could not be determined.")
    end

    if result.reason then
        table.insert(lines, "Reason: " .. result.reason)
    end

    return lines
end

function SituationPanel:RefreshRows()
    local situationsFrame = self.situationsFrame
    local pool = situationsFrame and situationsFrame.SituationFramePool
    if not pool then
        return
    end

    for situationFrame in pool:EnumerateActive() do
        local elementData = situationFrame.elementData
        local triggerID = elementData and elementData.triggerID

        if triggerID then
            local value = AcquireValueText(situationFrame)
            if value then
                local result = ns.Triggers:Resolve(triggerID)
                local displayName = ns.Triggers:GetDisplayName(triggerID, result)

                situationFrame.BetterSituationDetail = {
                    categoryName = elementData.name,
                    lines = BuildTooltipLines(triggerID, result, displayName)
                }

                if result.state == ns.Triggers.STATE_OK and displayName then
                    -- A trailing marker keeps an inferred value from reading as an exact
                    -- one; the tooltip explains which inference it was.
                    local marker = ""
                    if result.approximate or result.ambiguous then
                        marker = " |cff808080~|r"
                    elseif result.unverified then
                        marker = " |cff808080*|r"
                    end

                    value:SetText(displayName .. marker)
                    value:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
                elseif result.state == ns.Triggers.STATE_UNSUPPORTED then
                    -- Rendering nothing here would be indistinguishable from a broken row.
                    value:SetText("n/a")
                    value:SetTextColor(GRAY_FONT_COLOR:GetRGB())
                else
                    value:SetText("?")
                    value:SetTextColor(GRAY_FONT_COLOR:GetRGB())
                end
            end
        end
    end
end

function SituationPanel:StartTracking()
    if self.tracking then
        return
    end
    self.tracking = true

    self:RefreshRows()

    ns.Util.RegisterEventsSafely(self.eventFrame, ns.Triggers:GetAllEvents())

    -- Mount/swim/fly state and the clock have no usable event, so those (and only those)
    -- need a poll, and only while the tab is actually visible.
    if ns.Triggers:NeedsPolling() and not self.ticker then
        self.ticker = C_Timer.NewTicker(
            POLL_INTERVAL,
            function()
                self:RefreshRows()
            end
        )
    end
end

function SituationPanel:StopTracking()
    self.tracking = false

    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
end

function SituationPanel:AttachToSituationsFrame()
    if self.attached then
        return
    end

    local situationsFrame = GetSituationsFrame()
    if not situationsFrame then
        return
    end

    self.situationsFrame = situationsFrame

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript(
        "OnEvent",
        function()
            self:RefreshRows()
        end
    )

    -- The XML mixin= attribute copies the mixin's functions onto the frame at creation, so
    -- hooking TransmogWardrobeSituationsMixin here would do nothing. Hook the instance.
    hooksecurefunc(
        situationsFrame,
        "Init",
        function()
            self:RefreshRows()
        end
    )

    hooksecurefunc(
        situationsFrame,
        "Refresh",
        function()
            self:RefreshRows()
        end
    )

    situationsFrame:HookScript(
        "OnShow",
        function()
            self:StartTracking()
        end
    )

    situationsFrame:HookScript(
        "OnHide",
        function()
            self:StopTracking()
        end
    )

    self.attached = true

    -- Blizzard may already have built the rows before we got here.
    self:RefreshRows()

    if situationsFrame:IsVisible() then
        self:StartTracking()
    end
end

function SituationPanel:Init(api)
    self.api = api

    if not ns.Capabilities.hasSituations then
        return
    end

    if IsBlizzardTransmogLoaded() then
        self:AttachToSituationsFrame()
        return
    end

    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript(
        "OnEvent",
        function(_, event, loadedAddon)
            if event == "ADDON_LOADED" and loadedAddon == "Blizzard_Transmog" then
                self:AttachToSituationsFrame()
                loader:UnregisterEvent("ADDON_LOADED")
            end
        end
    )
end
