---@diagnostic disable: undefined-global, lowercase-global
-- Which categories exist is not fixed for the session: saving a first equipment set adds
-- the Equipment Sets category, deleting the last removes it, and Specializations only
-- appears from level 10. The category list was cached once at load, so those changes never
-- appeared without a /reload. This drives the real events to prove they do now.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

local LOCATIONS = H.Category(3, "Locations", { H.Opt("All Locations", 3), H.Opt("Rest Area", 4) })
local EQUIPMENT = H.Category(6, "Equipment Sets", { H.Opt("All Equipment Sets", 18),
    H.Opt("plop 1", 19, { equipmentSetID = 0 }) })

-- Start with no equipment sets, as a fresh character has.
H.categories = { LOCATIONS }
H.W.resting = true
H.activeOutfitID, H.viewedOutfitID = 1, 1

local ns = H.Load()

H.Section("before any equipment set exists")
H.Check("categories", #ns.Triggers:GetCategories(), 1)
H.Check("Equipment Sets category present", ns.Triggers:GetCategory(6) ~= nil, false)

-- The player saves their first equipment set. The client would now return the category, but
-- nothing has told us to look again. Replace rather than mutate: the client hands back a fresh
-- table each call, so the cache must be holding its own copy for this to be a real test.
H.categories = { LOCATIONS, EQUIPMENT }
H.sets = { { id = 0, name = "plop 1", isEquipped = true, numItems = 15, numEquipped = 15 } }

H.Section("after saving a set, before the event")
H.Check("still stale (cached)", #ns.Triggers:GetCategories(), 1)

H.Section("after EQUIPMENT_SETS_CHANGED")
H.Fire("EQUIPMENT_SETS_CHANGED")
H.Check("categories", #ns.Triggers:GetCategories(), 2)
H.Check("Equipment Sets resolves", ns.Triggers:Resolve(6).optionName, "plop 1")

-- And the reverse: deleting every set removes the category again.
H.categories = { LOCATIONS }
H.sets = {}
H.Fire("EQUIPMENT_SETS_CHANGED")
H.Section("after deleting every set")
H.Check("categories", #ns.Triggers:GetCategories(), 1)

-- The swap event must still record the applied set, and must NOT be swallowed by the
-- invalidation branch.
H.categories = { LOCATIONS, EQUIPMENT }
H.sets = { { id = 0, name = "plop 1", isEquipped = true, numItems = 15, numEquipped = 15 } }
H.Fire("EQUIPMENT_SETS_CHANGED")
H.Fire("EQUIPMENT_SWAP_FINISHED", true, 0)
H.Section("after EQUIPMENT_SWAP_FINISHED")
H.Check("last applied set remembered", ns.Triggers:GetLastAppliedSetID(), 0)

-- An empty answer must not be cached as authoritative: the API may return nothing at any
-- moment, and caching that would pin the addon to "no situations on this client" until one
-- of the category events happened to fire.
H.Section("transient empty answer")
ns.Triggers:InvalidateCategories()
H.returnNothing = true
H.Check("empty while the API is silent", #ns.Triggers:GetCategories(), 0)
H.returnNothing = false
H.Check("recovers with no event needed", #ns.Triggers:GetCategories(), 2)

-- The tree is fetched per viewed outfit, so switching outfit must drop the cached copy.
H.Section("viewed-outfit events invalidate the tree")
for _, event in ipairs({ "VIEWED_TRANSMOG_OUTFIT_CHANGED", "VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED" }) do
    ns.Triggers:GetCategories()
    H.categories = { LOCATIONS, EQUIPMENT } -- a fresh tree, as for the newly viewed outfit
    H.Fire(event)
    H.Check(event .. " refetches", ns.Triggers:GetCategories() == H.categories, true)
end

-- The Situations tab must register the category events even when the category they concern
-- does not exist yet, or creating a first set while the tab is open would go unnoticed.
H.Section("panel event registration")
ns.SituationPanel.eventFrame = H.NewFrame()
ns.SituationPanel.situationsFrame = { SituationFramePool = { EnumerateActive = function() return function() end end } }
ns.SituationPanel:StartTracking()
for _, event in ipairs(ns.Triggers.CATEGORY_EVENTS) do
    H.Check("registers " .. event, ns.SituationPanel.eventFrame.registered[event] == true, true)
end

H.Done()
