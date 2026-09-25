local _, ns = ...

-- Phase 3: the same trigger values as /ts, in a frame that works anywhere, rather than only
-- inside Blizzard's transmog window. Reads ns.Triggers like every other consumer, so it
-- tracks the conditional categories and the two clients' differences for free.

local StatusPanel = {}
ns.StatusPanel = StatusPanel

local PANEL_NAME = "TransmogSituationsStatusPanel"
local WIDTH, ROW_HEIGHT, PADDING, HEADER = 260, 16, 12, 28

-- Two columns that never overlap: labels get the width of the widest one (capped, so a very long
-- localized name truncates rather than squeezing the values out), values get what is left and
-- truncate with an ellipsis. The panel only grows past WIDTH for labels, which change when the
-- category set does, not with every value -- so it does not jitter as values change.
local GAP, MAX_LABEL_WIDTH, MIN_VALUE_WIDTH = 8, 150, 130

-- Width of the text on one line. GetStringWidth is bounded by a width already set on the
-- FontString, which after the first layout is exactly the value being measured for.
local function TextWidth(fontString)
    local ok, width = ns.Util.SafeCall(fontString.GetUnboundedStringWidth or fontString.GetStringWidth, fontString)
    return ok and tonumber(width) or 0
end

local function EnsureSaved()
    local db = ns.TransmogSituations and ns.TransmogSituations.db
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
    title:SetText("TransmogSituations")
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
    row.label:SetWordWrap(false)
    row.label:SetMaxLines(1)

    row.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("TOPRIGHT", -PADDING, -(HEADER + (index - 1) * ROW_HEIGHT))
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    row.value:SetMaxLines(1)

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

        ns.Diagnostics:SetValueText(row.value, entry.result, "compact")
        row.value:Show()
        count = index
    end

    -- Categories can disappear (deleting the last equipment set); hide the leftovers.
    for index = count + 1, #self.frame.rows do
        self.frame.rows[index].label:Hide()
        self.frame.rows[index].value:Hide()
    end

    if count == 0 then
        self.frame.Title:SetText("TransmogSituations - no situations")
    else
        self.frame.Title:SetText("TransmogSituations")
    end

    self:Layout(count)
end

function StatusPanel:Layout(count)
    local rows = self.frame.rows

    local labelWidth = 0
    for index = 1, count do
        labelWidth = math.max(labelWidth, TextWidth(rows[index].label))
    end
    labelWidth = math.min(math.ceil(labelWidth), MAX_LABEL_WIDTH)

    local width = math.max(WIDTH, 2 * PADDING + labelWidth + GAP + MIN_VALUE_WIDTH)
    local valueWidth = width - 2 * PADDING - labelWidth - GAP

    for index = 1, count do
        rows[index].label:SetWidth(labelWidth)
        rows[index].value:SetWidth(valueWidth)
    end

    self.frame:SetSize(width, HEADER + math.max(count, 1) * ROW_HEIGHT + PADDING)
end

-- Live while shown: every change Triggers hears of, plus its poll for the values that have no
-- event (mount, swim and fly state, the clock).
function StatusPanel:StartTracking()
    ns.Triggers:Subscribe(self.onChange, true)
    self:Refresh()
end

function StatusPanel:StopTracking()
    ns.Triggers:Unsubscribe(self.onChange)
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
    self.onChange = function()
        self:Refresh()
    end

    local saved = EnsureSaved()
    if saved and saved.shown then
        self:Show()
    end
end
