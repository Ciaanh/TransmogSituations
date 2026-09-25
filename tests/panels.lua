---@diagnostic disable: undefined-global, lowercase-global
-- The two panels: what each renders, and that both follow the model live through the Triggers
-- hub while shown and stop listening when hidden. Stubbed frames, so this proves the wiring,
-- not the layout -- the layout still needs a look in game.
local H = dofile((arg[1] or ".") .. "/tests/harness.lua")

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

local function RowText(i) return rows[i].TransmogSituationsValue:GetText() end

H.Section("Situations tab: the value alone")
H.Check("attached at load", ns.SituationPanel.attached, true)
situationsFrame:Show()
H.Check("Locations shows the value, no markers", RowText(1), "House")
H.Check("Movement", RowText(2), "Ground Mount")
H.Check("an unsupported trigger says n/a", RowText(3), "n/a")
H.Check("a placeholder is greyed", rows[3].TransmogSituationsValue.color[1], 0.5)
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
H.Check("remembers it is shown", ns.TransmogSituations.db.panel.shown, true)
H.W.mounted = false
H.Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
H.Check("follows a dismount", panelRows[2].value:GetText(), "Unmounted")

-- Unit events come for every unit in range; another player's form change is not ours.
local formsRow = panelRows[4]
H.W.hasAltForm, H.W.inAltForm = true, false
H.Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
H.Check("Racial Forms", formsRow.value:GetText(), "Dracthyr")
H.W.inAltForm = true
H.Fire("UNIT_FORM_CHANGED", "party1")
H.Check("ignores another unit's form change", formsRow.value:GetText(), "Dracthyr")
H.Fire("UNIT_FORM_CHANGED", "player")
H.Check("follows the player's", formsRow.value:GetText(), "Visage")

ns.StatusPanel.frame:Hide() -- as Escape would, without going through our Hide()
H.Check("remembers it was closed", ns.TransmogSituations.db.panel.shown, false)
H.Check("and stops polling", H.LiveTickers(), 0)

-- Labels and values sit in two columns that never overlap, whatever the locale. The harness
-- measures 6px a character.
H.Section("standalone panel: layout")
ns.StatusPanel:Show()
local panel = ns.StatusPanel.frame
local function ColumnsFit()
    for i = 1, #H.categories do
        local row = panel.rows[i]
        if row.label.width + 8 + row.value.width > panel.width - 24 then return false end
    end
    return true
end
H.Check("label column is the widest label", panel.rows[1].label.width, 6 * #"Specializations")
H.Check("default width kept", panel.width, 260)
H.Check("columns fit", ColumnsFit(), true)

H.categories[1].name = string.rep("x", 40) -- a long localized category name
ns.Triggers:InvalidateCategories()
ns.StatusPanel:Refresh()
H.Check("a long label is capped", panel.rows[1].label.width, 150)
H.Check("the panel grows to keep room for values", panel.width, 24 + 150 + 8 + 130)
H.Check("columns still fit", ColumnsFit(), true)

H.Done()
