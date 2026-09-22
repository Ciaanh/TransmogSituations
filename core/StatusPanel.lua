local _, ns = ...

-- Phase 3: the same trigger values as /bs, in a frame that works anywhere, rather than only
-- inside Blizzard's transmog window. Reads ns.Triggers like every other consumer, so it
-- tracks the conditional categories and the two clients' differences for free.

local StatusPanel = {}
ns.StatusPanel = StatusPanel

local PANEL_NAME = "BetterSituationStatusPanel"
local POLL_INTERVAL = 1.5
local WIDTH, ROW_HEIGHT, PADDING, HEADER = 260, 16, 12, 28

local function EnsureSaved()
    local db = ns.BetterSituation and ns.BetterSituation.db
    if not db then
        return nil
    end

    db.panel = db.panel or {}
    return db.panel
end

-- BackdropTemplate does not exist everywhere, and a missing template makes CreateFrame raise.
local function CreatePanelFrame()
    local ok, frame = pcall(CreateFrame, "Frame", PANEL_NAME, UIParent, "BackdropTemplate")
    if not ok or not frame then
        frame = CreateFrame("Frame", PANEL_NAME, UIParent)
    end

    if frame.SetBackdrop then
        pcall(
            frame.SetBackdrop,
            frame,
            {
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true,
                tileSize = 32,
                edgeSize = 16,
                insets = { left = 5, right = 5, top = 5, bottom = 5 }
            }
        )
    else
        -- No backdrop support: a plain dark panel is still readable.
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
    end

    return frame
end

function StatusPanel:Create()
    if self.frame then
        return self.frame
    end

    local frame = CreatePanelFrame()
    frame:SetSize(WIDTH, 120)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript(
        "OnDragStop",
        function(f)
            f:StopMovingOrSizing()
            self:SavePosition()
        end
    )

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("BetterSituation")
    frame.Title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript(
        "OnClick",
        function()
            self:Hide()
        end
    )

    -- Persist visibility from the frame's own scripts, not from Show()/Hide(): Escape closes
    -- the panel through UISpecialFrames without going through our methods, and the saved
    -- state must follow whichever path hid it or the panel comes back on the next login.
    frame:SetScript(
        "OnShow",
        function()
            self:SaveShown(true)
            self:StartTracking()
        end
    )
    frame:SetScript(
        "OnHide",
        function()
            self:SaveShown(false)
            self:StopTracking()
        end
    )

    frame.rows = {}
    frame:Hide()

    self.frame = frame

    -- Escape closes it, like Blizzard's own panels.
    if type(UISpecialFrames) == "table" then
        local present = false
        for _, name in ipairs(UISpecialFrames) do
            if name == PANEL_NAME then
                present = true
            end
        end
        if not present then
            table.insert(UISpecialFrames, PANEL_NAME)
        end
    end

    self:RestorePosition()
    return frame
end

function StatusPanel:SavePosition()
    local saved = EnsureSaved()
    if not saved or not self.frame then
        return
    end

    local point, _relativeTo, relativePoint, x, y = self.frame:GetPoint()
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

function StatusPanel:RestorePosition()
    local saved = EnsureSaved()
    self.frame:ClearAllPoints()

    if saved and saved.point then
        self.frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x or 0, saved.y or 0)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- One row per category the client offers. Rebuilt whenever that set changes.
function StatusPanel:AcquireRow(index)
    local frame = self.frame
    local row = frame.rows[index]
    if row then
        return row
    end

    row = {}
    row.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("TOPLEFT", PADDING, -(HEADER + (index - 1) * ROW_HEIGHT))
    row.label:SetJustifyH("LEFT")

    row.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("TOPRIGHT", -PADDING, -(HEADER + (index - 1) * ROW_HEIGHT))
    row.value:SetJustifyH("RIGHT")

    frame.rows[index] = row
    return row
end

function StatusPanel:Refresh()
    if not self.frame or not self.frame:IsShown() then
        return
    end

    local entries = ns.Triggers:ResolveAll()
    local count = 0

    for index, entry in ipairs(entries) do
        local row = self:AcquireRow(index)
        row.label:SetText(entry.categoryName)
        row.label:Show()

        local result = entry.result
        local text, r, g, b

        if result.state == ns.Triggers.STATE_OK and result.optionName then
            text = result.optionName
            if result.alsoOptions and #result.alsoOptions > 0 then
                text = string.format("%s +%d", text, #result.alsoOptions)
            end
            if result.approximate or result.ambiguous then
                text = text .. " ~"
            end
            r, g, b = HIGHLIGHT_FONT_COLOR:GetRGB()
        elseif result.state == ns.Triggers.STATE_UNSUPPORTED then
            text = "n/a"
            r, g, b = GRAY_FONT_COLOR:GetRGB()
        else
            text = "?"
            r, g, b = GRAY_FONT_COLOR:GetRGB()
        end

        row.value:SetText(text)
        row.value:SetTextColor(r, g, b)
        row.value:Show()
        count = index
    end

    -- Categories can disappear (deleting the last equipment set); hide the leftovers.
    for index = count + 1, #self.frame.rows do
        self.frame.rows[index].label:Hide()
        self.frame.rows[index].value:Hide()
    end

    if count == 0 then
        self.frame.Title:SetText("BetterSituation - no situations")
    else
        self.frame.Title:SetText("BetterSituation")
    end

    self.frame:SetHeight(HEADER + math.max(count, 1) * ROW_HEIGHT + PADDING)
end

function StatusPanel:StartTracking()
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function() self:Refresh() end)
    end

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

    if ns.Triggers:NeedsPolling() and not self.ticker then
        self.ticker = C_Timer.NewTicker(POLL_INTERVAL, function() self:Refresh() end)
    end

    self:Refresh()
end

function StatusPanel:StopTracking()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
end

function StatusPanel:SaveShown(shown)
    local saved = EnsureSaved()
    if saved then
        saved.shown = shown
    end
end

function StatusPanel:Show()
    self:Create():Show()
end

function StatusPanel:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function StatusPanel:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function StatusPanel:Init()

    local saved = EnsureSaved()
    if saved and saved.shown then
        self:Show()
    end
end
