---@diagnostic disable: undefined-global, lowercase-global
-- Blizzard_Transmog loads on demand, and being loaded does not guarantee SituationsFrame
-- exists yet. A single attach attempt that gives up, or one that stops listening whether or
-- not it worked, leaves the Situations tab permanently bare for the session.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

H.categories = { H.Category(3, "Locations", { H.Opt("All Locations", 3), H.Opt("Rest Area", 4) }) }
H.W.resting = true

-- The Situations frame, built only when we say so. `withMixin` is whether Blizzard's mixin
-- has been applied: hooksecurefunc raises on a missing method, so attaching early must decline.
local function BuildSituationsFrame(withMixin)
    local frame = H.NewFrame()
    frame.SituationFramePool = { EnumerateActive = function() return function() end end }
    if withMixin then
        frame.Init = function() end
        frame.Refresh = function() end
    else
        -- The stub frame answers any method; a frame without the mixin must really lack these.
        rawset(frame, "Init", false)
        rawset(frame, "Refresh", false)
    end
    TransmogFrame = { WardrobeCollection = { TabContent = { SituationsFrame = frame } } }
end

local ns = H.Load()

-- Transmog not loaded at addon load: must not attach, must keep listening.
H.Check("not attached before Blizzard_Transmog loads", ns.SituationPanel.attached, nil)
H.Check("still listening", ns.SituationPanel.loader ~= nil, true)

-- Addon loads but the frame is not built yet. This is the case the old code broke on: it
-- unregistered ADDON_LOADED whether or not the attach worked.
H.loadedAddons.Blizzard_Transmog = true
TransmogFrame = nil
H.Fire("ADDON_LOADED", "Blizzard_Transmog")
H.Check("frame absent -> still not attached", ns.SituationPanel.attached, nil)
H.Check("still listening after a failed attempt", ns.SituationPanel.loader ~= nil, true)

-- Frame appears without the mixin methods: must decline rather than raise.
BuildSituationsFrame(false)
local ok = pcall(H.Fire, "PLAYER_ENTERING_WORLD")
H.Check("no error when the mixin is missing", ok, true)
H.Check("declined to attach", ns.SituationPanel.attached, nil)

-- Frame is finally complete.
BuildSituationsFrame(true)
H.Fire("PLAYER_ENTERING_WORLD")
H.Check("attached once the frame exists", ns.SituationPanel.attached, true)
H.Check("stopped listening after success", ns.SituationPanel.loader, nil)

H.Done()
