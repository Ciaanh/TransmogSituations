---@diagnostic disable: undefined-global, lowercase-global
-- Phase 4: the outfit cache and the eligibility matcher.
--
-- This proves the rules behave as designed, NOT that they are Blizzard's. /ts verify is what
-- scores them against reality.
local H = dofile((arg[1] or ".") .. "/tests/harness.lua")

H.categories = {
    H.Category(3, "Locations", { H.Opt("All Locations", 3), H.Opt("Rest Area", 4), H.Opt("World", 5),
        H.Opt("Raids", 10) }),
    H.Category(4, "Movement", { H.Opt("All Movement", 13), H.Opt("Unmounted", 14), H.Opt("Ground Mount", 16) }),
    H.Category(5, "Specializations", { H.Opt("All Specializations", 1),
        H.Opt("Assassination", 2, { specID = 259 }), H.Opt("Outlaw", 2, { specID = 260 }) }),
    -- No C_Weather: Weather resolves as unsupported, the Retail situation. An outfit ticked
    -- "All Weather" must still be able to match.
    H.Category(11, "Weather", { H.Opt("All Weather", 32), H.Opt("Clear", 33), H.Opt("Rain", 34) }),
}
H.outfits = {
    { outfitID = 2, name = "Combat", playerFacingOutfitIndex = 1 },
    { outfitID = 3, name = "Rest", playerFacingOutfitIndex = 2 },
    { outfitID = 4, name = "Raiding", playerFacingOutfitIndex = 3 },
    { outfitID = 5, name = "Unseen", playerFacingOutfitIndex = 4 },
}
H.activeOutfitID = 3
H.W.resting = true
H.W.specIndex, H.W.specID = 1, 259

local ns = H.Load()

-- "Viewing" an outfit with the given assignments. GetOutfitSituation answers for the viewed
-- outfit, so nothing here needs to drop the category tree first.
local function Record(outfitID, keys)
    H.viewedOutfitID = outfitID
    H.assigned[outfitID] = keys
    return ns.OutfitCache:RecordViewed()
end

local function EligibleNames()
    local names = {}
    for _, e in ipairs((ns.Eligibility:GetEligible())) do table.insert(names, e.name) end
    return table.concat(names, ", ")
end

-- The option tree's `value` flag is false everywhere: Blizzard's own dropdown never reads it,
-- it asks GetOutfitSituation(option), and so must the cache or nothing below records.
Record(2, { ["10:0:0:0"] = true })                      -- Combat: Raids only
Record(3, { ["4:0:0:0"] = true, ["32:0:0:0"] = true })    -- Rest: Rest Area + All Weather
Record(4, { ["10:0:0:0"] = true, ["2:259:0:0"] = true })  -- Raiding: Raids AND Assassination
H.viewedOutfitID = 3

H.Section("cache")
H.Check("outfits recorded", ns.OutfitCache:Count(), 3)
H.Check("never-viewed outfit is absent", ns.OutfitCache:Get(5), nil)
H.Check("unrecorded reported", #ns.OutfitCache:GetUnrecordedOutfits(), 1)
H.Check("assignment read through the api", ns.OutfitCache:Get(3).categories[3].keys["4:0:0:0"], true)
H.Check("wildcard flagged on the category", ns.OutfitCache:Get(3).categories[11].wildcard, true)

-- Mid-edit, GetOutfitSituation answers with the pending state. Nothing may be recorded then.
H.Section("pending edits")
H.pending = true
H.Check("recording is skipped while pending", Record(5, { ["5:0:0:0"] = true }), nil)
H.Check("outfit 5 still absent", ns.OutfitCache:Get(5), nil)

-- Pressing Apply commits the edit. The events fired during it were all skipped as pending, so
-- the commit itself must record, or the entry keeps the pre-edit assignment.
H.Section("apply records the committed edit")
H.viewedOutfitID = 3
H.assigned[3] = { ["5:0:0:0"] = true, ["32:0:0:0"] = true } -- Rest edited to World
C_TransmogOutfitInfo.CommitPendingSituations()
H.Check("recorded on commit", ns.OutfitCache:Get(3).categories[3].keys["5:0:0:0"], true)
H.Check("old assignment gone", ns.OutfitCache:Get(3).categories[3].keys["4:0:0:0"], nil)
Record(3, { ["4:0:0:0"] = true, ["32:0:0:0"] = true }) -- back to Rest Area for what follows
H.assigned[5] = nil

-- Resting, unmounted, Assassination. Rest also ticks "All Weather", and Weather is
-- unsupported here, so this doubles as the wildcard-over-unsupported check.
H.Section("resting in the world")
local eligible, rejected = ns.Eligibility:GetEligible()
H.Check("eligible", EligibleNames(), "Rest")
H.Check("wildcards do not count as constraints", eligible[1] and eligible[1].specificity, 1)
local combatReason
for _, r in ipairs(rejected) do if r.name == "Combat" then combatReason = r.reason end end
H.Check("Combat rejected on Locations", combatReason, "Locations is Rest Area")

-- In a raid both Combat (Raids) and Raiding (Raids + Assassination) match. They are not
-- ranked: Blizzard picks among every eligible outfit at random, so the list keeps list order.
H.W.inInstance, H.W.instanceType, H.W.resting = true, "raid", false
ns.Triggers:InvalidateCategories()
H.Section("in a raid as Assassination")
H.Check("eligible, in outfit order", EligibleNames(), "Combat, Raiding")

H.W.specID = 260
ns.Triggers:InvalidateCategories()
H.Section("in a raid as Outlaw")
H.Check("the spec-constrained outfit drops out", EligibleNames(), "Combat")
H.W.specID = 259

-- A wildcard selection satisfies its category whatever the live value is.
Record(2, { ["3:0:0:0"] = true }) -- Combat: All Locations
H.W.inInstance, H.W.instanceType, H.W.resting = false, "none", true
ns.Triggers:InvalidateCategories()
H.Section("wildcard selection")
H.Check("All Locations matches while resting", EligibleNames(), "Combat, Rest")

-- Verification against the outfit Blizzard applied: membership, not rank.
H.Section("verify")
local report = ns.Eligibility:Verify()
H.Check("active outfit read", report and report.activeOutfitID, 3)
H.Check("unrecorded counted", report and report.unrecorded, 1)
H.Check("applied outfit among the eligible agrees", report and report.agrees, true)
H.Check("verdict", report and report.verdict, "agrees")

-- Switched off, Blizzard picks nothing: whatever is applied says nothing about the rules.
H.situationsEnabled = false
report = ns.Eligibility:Verify()
H.Check("situations off is not scored", report.verdict, "disabled")
H.Check("and is not an agreement", report.agrees, false)
H.ClearChat()
ns.Diagnostics:PrintEligible()
H.Check("/ts eligible says situations are off", H.ChatText():find("switched off", 1, true) ~= nil, true)
H.situationsEnabled = true

-- Nothing applied while outfits are eligible: a moment without a pick, not a cache gap.
H.activeOutfitID = 0
H.Check("nothing applied is not scored", ns.Eligibility:Verify().verdict, "none-applied")
H.ClearChat()
ns.Diagnostics:PrintVerify()
H.Check("and says so", H.ChatText():find("no outfit is applied", 1, true) ~= nil, true)
H.Check("not blamed on the cache", H.ChatText():find("never been viewed, or has changed", 1, true), nil)
H.activeOutfitID = 3

H.activeOutfitID = 2 -- Combat: eligible, and constrains less than Rest
H.Check("any eligible outfit agrees", ns.Eligibility:Verify().agrees, true)

H.activeOutfitID = 4 -- Raiding: recorded, current, and not eligible out here
report = ns.Eligibility:Verify()
H.Check("disagreement is detected", report.agrees, false)
H.Check("a recorded active outfit scores the rules", report.activeRecorded, true)
H.Check("verdict", report.verdict, "disagrees")

-- Outfit 5 was never recorded, so it could not have been matched whatever the rules say.
H.activeOutfitID = 5
report = ns.Eligibility:Verify()
H.Check("unrecorded active outfit is not scorable", report.activeRecorded, false)
H.Check("verdict", report.verdict, "not-recorded")
H.activeOutfitID = 3

-- An edit committed while the cache was not looking leaves an entry describing assignments the
-- outfit no longer has (seen in game: an outfit reset to Defaults kept its old entry).
-- situationCategories names the constrained categories, so the contradiction is detectable.
H.Section("stale entries")
local rest = H.outfits[2]
rest.situationCategories = {} -- reset to all wildcards; the cache still says Rest Area
H.Check("entry contradicting situationCategories is stale", ns.OutfitCache:IsStale(3, rest), true)
local _, staleReason = ns.Eligibility:Match(3, ns.Eligibility:GetCurrentKeys(), rest)
H.Check("stale entry is not matched", staleReason, "changed since last viewed")
H.Check("stale entry counts as unrecorded", #ns.OutfitCache:GetUnrecordedOutfits(), 2)
H.Check("stale active outfit is not scorable", ns.Eligibility:Verify().activeRecorded, false)
rest.situationCategories = { "Locations" }
H.Check("agreeing entry is not stale", ns.OutfitCache:IsStale(3, rest), false)
rest.situationCategories = nil

-- /ts scan steps the viewed outfit through every unrecorded one, then restores the original.
H.Section("scan")
H.Check("refuses without the transmog window", ns.OutfitCache:Scan(), false)
TransmogFrame = { IsShown = function() return true end }
H.assigned[5] = { ["5:0:0:0"] = true } -- Unseen: World
H.viewedOutfitID = 3
H.Check("starts with the window open", ns.OutfitCache:Scan(), true)
H.RunTickers()
H.Check("the unrecorded outfit is recorded", ns.OutfitCache:Get(5) ~= nil, true)
H.Check("the original viewed outfit is restored", H.viewedOutfitID, 3)

-- Switching outfits throws away unapplied edits; Blizzard's own list asks first. A scan refuses.
H.pending = true
H.Check("refuses with unapplied situation edits", ns.OutfitCache:Scan(), false)
H.pending, H.pendingTransmogs = false, true
H.Check("refuses with unapplied appearance edits", ns.OutfitCache:Scan(), false)
H.pendingTransmogs, H.inTransmogEvent = false, true
H.Check("refuses during a transmog event", ns.OutfitCache:Scan(), false)
H.inTransmogEvent = false

-- The same holds between two steps, and closing the window stops the sweep. Either way the
-- viewed outfit is left alone rather than switched back under the player.
local windowShown = true
TransmogFrame = { IsShown = function() return windowShown end }
for _, case in ipairs({
    { "window closes", function() windowShown = false end, "transmog window closed" },
    { "player starts editing", function() H.pending = true end, "unapplied changes" },
}) do
    ns.OutfitCache:Forget(5)
    H.viewedOutfitID = 3
    H.ClearChat()
    ns.OutfitCache:Scan()
    case[2]()
    H.RunTickers()
    H.Check("mid-scan, " .. case[1] .. ": stops", ns.OutfitCache.scanning, false)
    H.Check("mid-scan, " .. case[1] .. ": records nothing more", ns.OutfitCache:Get(5), nil)
    H.Check("mid-scan, " .. case[1] .. ": viewed outfit untouched", H.viewedOutfitID, 3)
    H.Check("mid-scan, " .. case[1] .. ": says why", H.ChatText():find(case[3], 1, true) ~= nil, true)
    windowShown, H.pending = true, false
end
ns.OutfitCache:Scan()
H.RunTickers()
H.Check("an uninterrupted scan records it", ns.OutfitCache:Get(5) ~= nil, true)
TransmogFrame = nil

-- Deleting an outfit must drop its cache entry when the client says the list changed -- and
-- only then: reports read the list without side effects, and an empty answer is not a wipe.
H.Section("prune")
local fullList = H.outfits
table.remove(H.outfits, 3) -- Raiding (id 4) is gone
ns.Eligibility:Verify()
H.Check("a report does not prune", ns.OutfitCache:Get(4) ~= nil, true)
H.outfits = {}
H.Fire("TRANSMOG_OUTFITS_CHANGED")
H.Check("an empty outfit list prunes nothing", ns.OutfitCache:Count(), 4)
H.outfits = fullList
H.Fire("TRANSMOG_OUTFITS_CHANGED")
H.Check("deleted outfit pruned on TRANSMOG_OUTFITS_CHANGED", ns.OutfitCache:Get(4), nil)
H.Check("count follows", ns.OutfitCache:Count(), 3)

-- The reason Blizzard's pick disagrees is part of the report.
H.Section("verify reasons")
H.activeOutfitID = 2
H.W.resting, H.W.inInstance, H.W.instanceType = false, true, "raid"
Record(2, { ["4:0:0:0"] = true }) -- Combat: Rest Area only
H.viewedOutfitID = 3
local disagreement = ns.Eligibility:Verify()
H.Check("disagrees", disagreement.agrees, false)
H.Check("says why", disagreement.activeReason, "Locations is Raids")

H.Done()
