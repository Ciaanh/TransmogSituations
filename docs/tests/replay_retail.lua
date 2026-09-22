---@diagnostic disable: undefined-global, lowercase-global
-- Replays the /bs dump captured on live Retail: real situationIDs, real option names and
-- order, real player state. A Dracthyr in visage, outdoors in a neighborhood while resting, on
-- a ground mount, no C_Weather.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

H.categories = H.RetailTree()
H.W.inInstance, H.W.instanceType, H.W.resting = true, "neighborhood", true
H.W.mounted = true
H.W.hasAltForm, H.W.inAltForm = true, true
H.W.specIndex, H.W.specID = 1, 259
H.W.hour, H.W.minute = 23, 3
-- "Rest" is second on screen but carries outfitID 3.
H.outfits = {
    { outfitID = 2, name = "Combat", playerFacingOutfitIndex = 1, situationCategories = { "Locations" } },
    { outfitID = 3, name = "Rest", playerFacingOutfitIndex = 2, situationCategories = { "Locations" } },
}
H.activeOutfitID, H.viewedOutfitID = 3, 3

local ns = H.Load()

H.Section("resolved values")
local EXPECTED = {
    [3] = "Rest Area", -- in the neighborhood but NOT inside the house
    [4] = "Ground Mount",
    [5] = "Assassination",
    [7] = "Visage",
    [12] = "Night",
}
for _, entry in ipairs(ns.Triggers:ResolveAll()) do
    if entry.triggerID == 11 then
        H.Check("[11] Weather is unsupported (no C_Weather)", entry.result.state, "unsupported")
    else
        H.Check(string.format("[%d] %s", entry.triggerID, entry.categoryName), entry.result.optionName,
            EXPECTED[entry.triggerID])
    end
end

-- Inside the house, as captured on Retail 2026-09-22: the instance type switches to "interior"
-- (not "neighborhood"), IsInsideHouse goes true, and the player is still resting.
H.Section("inside the house")
H.W.instanceType, H.W.insideHouse = "interior", true
ns.Triggers:InvalidateCategories()
local inside = ns.Triggers:Resolve(3)
H.Check("value", inside.optionName, "House")
H.Check("also active", H.AlsoNames(inside), "Rest Area")

H.Section("/bs renders without error")
H.ClearChat()
ns.Diagnostics:PrintEnvironmentSnapshot()
H.Check("prints the Locations line", H.ChatText():find("Locations: House", 1, true) ~= nil, true)

H.Section("slash commands")
H.ClearChat()
SlashCmdList.BETTERSITUATION("help")
local help = H.ChatText()
for _, name in ipairs({ "panel", "eligible", "verify", "scan", "list", "dump", "debug", "help" }) do
    H.Check("/bs help lists " .. name, help:find("/bs " .. name, 1, true) ~= nil, true)
end
H.ClearChat()
SlashCmdList.BETTERSITUATION("nonsense")
H.Check("an unknown command says so", H.ChatText():find("Unknown command", 1, true) ~= nil, true)
H.ClearChat()
SlashCmdList.BETTERSITUATION("  VERIFY  ")
H.Check("commands are trimmed and case-insensitive", H.ChatText():find("Blizzard applied", 1, true) ~= nil, true)

H.Done()
