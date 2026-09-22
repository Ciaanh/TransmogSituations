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
                ns.Diagnostics:SetValueText(value, ns.Triggers:Resolve(triggerID), "value")
            end
        end
    end
end

-- Live while the tab is visible: every change Triggers hears of, plus its poll for the values
-- that have no event (mount, swim and fly state, the clock).
function SituationPanel:StartTracking()
    if self.tracking then
        return
    end
    self.tracking = true

    -- Opening the tab is the one moment we know for certain that an outfit is on screen and
    -- readable. OutfitCache otherwise only hears VIEWED_TRANSMOG_OUTFIT_CHANGED, which need
    -- not fire for the outfit that is already selected when the window opens -- leaving the
    -- first outfit the player looks at unrecorded. RecordViewed verifies the viewed id and
    -- the pending state itself, so this can only add what is genuinely there.
    ns.OutfitCache:RecordViewed()

    self:RefreshRows()
    ns.Triggers:Subscribe(self.onChange, true)
end

function SituationPanel:StopTracking()
    self.tracking = false
    ns.Triggers:Unsubscribe(self.onChange)
end

function SituationPanel:AttachToSituationsFrame()
    if self.attached then
        return
    end

    local situationsFrame = GetSituationsFrame()
    if not situationsFrame then
        return
    end

    -- Guard before hooking: hooksecurefunc raises on a nil method, and a client whose mixin
    -- differs would otherwise take the addon down rather than simply going without the
    -- inline values.
    if type(situationsFrame.Init) ~= "function" or type(situationsFrame.Refresh) ~= "function" then
        return
    end

    self.situationsFrame = situationsFrame

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

-- Keeps trying until it succeeds. Blizzard_Transmog loads on demand, and being loaded does
-- not guarantee SituationsFrame is built yet, so a single attempt that gives up -- or one
-- that stops listening whether or not it worked -- leaves the tab permanently bare.
function SituationPanel:TryAttach()
    if self.attached then
        return
    end

    if IsBlizzardTransmogLoaded() then
        self:AttachToSituationsFrame()
    end

    if self.attached then
        if self.loader then
            self.loader:UnregisterAllEvents()
            self.loader = nil
        end
        return
    end

    if not self.loader then
        local loader = CreateFrame("Frame")
        loader:SetScript(
            "OnEvent",
            function()
                self:TryAttach()
            end
        )
        ns.Util.RegisterEventsSafely(loader, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD" })
        self.loader = loader
    end
end

function SituationPanel:Init()
    self.onChange = function()
        self:RefreshRows()
    end


    if not ns.Capabilities.hasSituations then
        return
    end

    self:TryAttach()
end
