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
    return value
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

                if result.state == ns.Triggers.STATE_OK and displayName then
                    value:SetText(displayName)
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

    -- GetAllEvents only covers the categories that exist right now, so on its own it would
    -- miss the event that makes a new category appear -- saving a first equipment set while
    -- the tab is open. Always take the category events too.
    local events = ns.Triggers:GetAllEvents()
    local seen = {}
    for _, event in ipairs(events) do
        seen[event] = true
    end
    for _, event in ipairs(ns.Triggers.CATEGORY_EVENTS) do
        if not seen[event] then
            table.insert(events, event)
        end
    end

    ns.Util.RegisterEventsSafely(self.eventFrame, events)

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
