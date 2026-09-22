---@diagnostic disable: undefined-global, lowercase-global
-- The two panels: what each renders, and that both follow the model live through the Triggers
-- hub while shown and stop listening when hidden. Stubbed frames, so this proves the wiring,
-- not the layout -- the layout still needs a look in game.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

H.categories = H.RetailTree()
H.W.inInstance, H.W.instanceType, H.W.insideHouse, H.W.resting = true, "interior", true, true
H.W.mounted = true
H.W.specIndex, H.W.specID = 1, 259

-- The Situations tab as Blizzard builds it: pooled rows, each with a Title and its elementData.
local rows = {}
local function BuildSituationsFrame()
    local frame = H.NewFrame()
    for _, triggerID in ipairs({ 3, 4, 11 }) do
        local row = H.NewFrame()
        row.Title = row:CreateFontString()
        row.elementData = { triggerID = triggerID }
        table.insert(rows, row)
    end
    frame.SituationFramePool = {
        EnumerateActive = function()
            local i = 0
            return function() i = i + 1; return rows[i] end
        end,
    }
    frame.Init = function() end
    frame.Refresh = function() end
    TransmogFrame = { WardrobeCollection = { TabContent = { SituationsFrame = frame } } }
    return frame
end
H.loadedAddons.Blizzard_Transmog = true
local situationsFrame = BuildSituationsFrame()

local ns = H.Load()

local function RowText(i) return rows[i].BetterSituationValue:GetText() end

H.Section("Situations tab: the value alone")
H.Check("attached at load", ns.SituationPanel.attached, true)
situationsFrame:Show()
H.Check("Locations shows the value, no markers", RowText(1), "House")
H.Check("Movement", RowText(2), "Ground Mount")
H.Check("an unsupported trigger says n/a", RowText(3), "n/a")
H.Check("a placeholder is greyed", rows[3].BetterSituationValue.color[1], 0.5)
H.Check("polls while shown (Movement has no event)", H.LiveTickers(), 1)

H.Section("Situations tab: live")
H.W.mounted = false
H.Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
H.Check("follows a dismount without reopening", RowText(2), "Unmounted")
H.W.swimming = true
H.RunTickers(1)
H.Check("follows swimming through the poll", RowText(2), "Swimming")
H.W.swimming = false
situationsFrame:Hide()
H.W.mounted = true
H.Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
H.Check("stops following once hidden (keeps its last value)", RowText(2), "Swimming")
H.Check("and stops polling", H.LiveTickers(), 0)

H.Section("standalone panel: compact")
ns.StatusPanel:Show()
local panelRows = ns.StatusPanel.frame.rows
H.Check("Locations shows the other true option as +N", panelRows[1].value:GetText(), "House +1")
H.Check("Movement", panelRows[2].value:GetText(), "Ground Mount")
H.Check("one row per category", #panelRows, #H.categories)
H.Check("remembers it is shown", ns.BetterSituation.db.panel.shown, true)
H.W.mounted = false
H.Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
H.Check("follows a dismount", panelRows[2].value:GetText(), "Unmounted")
ns.StatusPanel.frame:Hide() -- as Escape would, without going through our Hide()
H.Check("remembers it was closed", ns.BetterSituation.db.panel.shown, false)
H.Check("and stops polling", H.LiveTickers(), 0)

H.Done()
