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

-- Triggers is the only listener. It handles an event before any subscriber hears of it, so a
-- subscriber reading the model inside its callback already sees the new category tree -- the
-- ordering four separate event frames only got right by accident of creation order.
H.Section("the event hub")
local seenCategories, seenEvent
local function Subscriber(event)
    seenEvent = event
    seenCategories = #ns.Triggers:GetCategories()
end
ns.Triggers:Subscribe(Subscriber)
H.categories = { LOCATIONS }
H.sets = {}
H.Fire("EQUIPMENT_SETS_CHANGED")
H.Check("subscriber is told", seenEvent, "EQUIPMENT_SETS_CHANGED")
H.Check("...after the category cache was dropped", seenCategories, 1)
H.Fire("ZONE_CHANGED")
H.Check("resolver events reach subscribers too", seenEvent, "ZONE_CHANGED")
ns.Triggers:Unsubscribe(Subscriber)
seenEvent = nil
H.Fire("ZONE_CHANGED")
H.Check("an unsubscribed callback hears nothing", seenEvent, nil)

-- One poll for the whole addon, only while a subscriber that wants it is listening and a
-- category with no usable event exists (Movement, Time of Day).
H.Section("polling")
local polls = 0
local function Poller(event)
    if event == "POLL" then polls = polls + 1 end
end
ns.Triggers:Subscribe(Poller, true)
H.Check("no polled category, no ticker", H.LiveTickers(), 0)
H.categories = { LOCATIONS, H.Movement() }
H.Fire("PLAYER_ENTERING_WORLD")
H.Check("a polled category starts it", H.LiveTickers(), 1)
H.RunTickers(3)
H.Check("the poll reaches the subscriber", polls, 3)
ns.Triggers:Unsubscribe(Poller)
H.Check("the last poller leaving stops it", H.LiveTickers(), 0)

H.Done()
