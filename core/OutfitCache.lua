local _, ns = ...

-- Phase 4, part one: reconstruct the outfit -> situation mapping the client never exposes.
--
-- There is no API that answers "which situations is outfit N bound to". GetOutfitSituation
-- only ever answers for the *currently viewed* outfit, and GetOutfitsInfo's
-- situationCategories is a table of localized category names -- lossy, and useless for
-- matching. So each time the player looks at an outfit we write its whole assignment down,
-- and the picture fills in as they browse.
--
-- How an assignment is read matters. Blizzard's own dropdown decides whether an option is
-- ticked by calling C_TransmogOutfitInfo.GetOutfitSituation(option)
-- (Blizzard_TransmogTemplates.lua, TransmogSituationMixin:Init); it never reads the `value`
-- flag the option tree also carries. Confirmed in game on Forever (2026-09-22): with an outfit
-- viewed, the api answered true for every "All" option while `value` was false on all of them.
-- So GetOutfitSituation is the source of truth and `value` is only the fallback for a client
-- where that call is missing or refuses us (it is declared AllowedWhenUntainted).
--
-- The same capture shows what "unconstrained" means to the client: an outfit whose
-- situationCategories list is empty has every "All" option ticked. So a fresh outfit is all
-- wildcards, never "nothing selected", and situationCategories names exactly the categories
-- with a non-wildcard selection.

local OutfitCache = {}
ns.OutfitCache = OutfitCache

-- The viewed outfit's assignment for one option, the way Blizzard reads it. Returns the
-- boolean plus which source answered, so /bs dump can show both side by side.
function OutfitCache.IsAssigned(optionData)
    if not optionData or not optionData.option then
        return false, "none"
    end

    if ns.Capabilities.hasSituations and type(C_TransmogOutfitInfo.GetOutfitSituation) == "function" then
        local ok, assigned = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitSituation, optionData.option)
        if ok and type(assigned) == "boolean" then
            return assigned, "api"
        end
    end

    return optionData.value and true or false, "value"
end

-- Spec, loadout and equipment-set options share one situationID and differ only by their
-- secondary ids, so an option's identity is the full 4-tuple. loadoutID is not optional: a
-- saved talent loadout's option carries the same specID as its spec's option and differs only
-- there (confirmed on Retail). Anything comparing assignments must use this.
function OutfitCache.OptionKey(option)
    if not option then
        return nil
    end

    return string.format(
        "%d:%d:%d:%d",
        tonumber(option.situationID) or 0,
        tonumber(option.specID) or 0,
        tonumber(option.loadoutID) or 0,
        tonumber(option.equipmentSetID) or 0
    )
end

-- Bumped whenever the key format or the entry shape changes. Entries written by an older
-- format are dropped rather than misread: a 3-part key would silently merge every loadout of a
-- spec into the spec itself.
local STORE_VERSION = 2

function OutfitCache:GetStore(create)
    local db = ns.BetterSituation and ns.BetterSituation.db
    local key = ns.Util.CharacterKey()
    if not db or not key then
        return nil
    end

    if db.outfitSituations and db.outfitSituationsVersion ~= STORE_VERSION then
        db.outfitSituations = nil
    end

    if not db.outfitSituations then
        if not create then
            return nil
        end
        db.outfitSituations = {}
        db.outfitSituationsVersion = STORE_VERSION
    end

    if not db.outfitSituations[key] then
        if not create then
            return nil
        end
        db.outfitSituations[key] = {}
    end

    return db.outfitSituations[key]
end

-- Snapshot the assignments of whichever outfit is being viewed right now.
function OutfitCache:RecordViewed()
    if not ns.Capabilities.hasSituations then
        return nil
    end

    local okViewed, outfitID = ns.Util.SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
    if not okViewed or type(outfitID) ~= "number" or outfitID == 0 then
        return nil
    end

    -- GetOutfitSituation answers with the *pending* state while the player is editing on the
    -- Situations tab, and VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED fires for every such
    -- edit. Recording then would store what they might never apply. Wait for the commit.
    local okPending, pending = ns.Util.SafeCall(C_TransmogOutfitInfo.HasPendingOutfitSituations)
    if okPending and pending then
        return nil
    end

    -- The category tree is current: Triggers drops it on the viewed-outfit events before any
    -- subscriber, this one included, hears of them.
    local categories = ns.Triggers:GetCategories()
    if #categories == 0 then
        return nil
    end

    local entry = { categories = {} }
    local sawAny = false

    for _, category in ipairs(categories) do
        local selected = { wildcard = false, keys = {} }

        for _, optionData in ipairs(ns.Triggers:GetOptions(category.triggerID)) do
            if OutfitCache.IsAssigned(optionData) then
                local key = OutfitCache.OptionKey(optionData.option)
                if key then
                    selected.keys[key] = true
                    sawAny = true

                    if ns.Triggers.WILDCARD_SITUATIONS[optionData.option.situationID] then
                        selected.wildcard = true
                    end
                end
            end
        end

        -- A category with nothing selected is unconstrained, which is a real state; it is
        -- stored (with empty keys) so we can tell it apart from "never recorded".
        entry.categories[category.triggerID] = selected
    end

    local store = self:GetStore(true)
    if not store then
        return nil
    end

    store[outfitID] = entry

    return outfitID, sawAny
end

function OutfitCache:Get(outfitID)
    local store = self:GetStore(false)
    return store and store[outfitID] or nil
end

-- Whether a recorded entry no longer describes the outfit. An entry is written only while the
-- outfit is viewed, so an edit committed without a later recording -- Defaults + Apply, then
-- clicking straight to another outfit -- leaves it describing assignments the outfit no longer
-- has. Confirmed in game on Forever (2026-09-22): "hoo" was reset to all wildcards, the cache
-- still held Rest Area + Unmounted, and /bs verify predicted hoo over the real active outfit.
--
-- GetOutfitsInfo's situationCategories names exactly the categories with a non-wildcard
-- selection (confirmed on both clients), so it is a free check on every entry. The names are
-- localized, but so are the category names they are compared with, from the same session.
-- Returns false whenever the check cannot be made, so it can only ever demote an entry.
function OutfitCache:IsStale(outfitID, info)
    local entry = self:Get(outfitID)
    if not entry or type(info) ~= "table" or type(info.situationCategories) ~= "table" then
        return false
    end

    local categories = ns.Triggers:GetCategories()
    if #categories == 0 then
        return false
    end

    local names = {}
    for _, category in ipairs(categories) do
        names[category.triggerID] = category.name
    end

    local expected = {}
    for _, name in ipairs(info.situationCategories) do
        expected[name] = true
    end

    local recorded = {}
    for triggerID, selected in pairs(entry.categories) do
        if OutfitCache.Constrains(selected) then
            local name = names[triggerID]
            if not name or not expected[name] then
                return true
            end
            recorded[name] = true
        end
    end

    for name in pairs(expected) do
        if not recorded[name] then
            return true
        end
    end

    return false
end

-- Whether a recorded category selection actually constrains anything: something is selected,
-- and it is not an "All ..." wildcard.
function OutfitCache.Constrains(selected)
    return selected ~= nil and next(selected.keys) ~= nil and not selected.wildcard
end

-- The client's outfit list, or an empty one. Every consumer reads it through here.
function OutfitCache:GetOutfits()
    if not ns.Capabilities.hasSituations then
        return {}
    end

    local ok, outfits = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitsInfo)
    return (ok and type(outfits) == "table") and outfits or {}
end

function OutfitCache:Count()
    local store = self:GetStore(false)
    if not store then
        return 0
    end

    local n = 0
    for _ in pairs(store) do
        n = n + 1
    end

    return n
end

function OutfitCache:Forget(outfitID)
    local store = self:GetStore(false)
    if store then
        store[outfitID] = nil
    end
end

function OutfitCache:Clear()
    local store = self:GetStore(false)
    if not store then
        return
    end

    for outfitID in pairs(store) do
        store[outfitID] = nil
    end
end

-- Drop entries for outfits the client no longer lists. Deleted outfits would otherwise sit in
-- SavedVariables forever, inflate Count(), and -- should the client ever reuse an id -- hand a
-- new outfit a dead one's assignments. Returns how many were dropped.
--
-- An empty list is never taken as "every outfit was deleted": the client can answer with
-- nothing before its outfit data has arrived, and pruning then would wipe the whole cache.
function OutfitCache:Prune(outfits)
    outfits = outfits or self:GetOutfits()
    local store = self:GetStore(false)
    if not store or #outfits == 0 then
        return 0
    end

    local live = {}
    for _, info in ipairs(outfits or {}) do
        live[info.outfitID] = true
    end

    local dropped = 0
    for outfitID in pairs(store) do
        if not live[outfitID] then
            store[outfitID] = nil
            dropped = dropped + 1
        end
    end

    return dropped
end

-- Outfits the client knows about that we have no usable entry for: never viewed, or changed
-- since they were (IsStale). /bs scan re-records whatever this returns.
function OutfitCache:GetUnrecordedOutfits()
    local missing = {}

    for _, info in ipairs(self:GetOutfits()) do
        if not self:Get(info.outfitID) or self:IsStale(info.outfitID, info) then
            table.insert(missing, info)
        end
    end

    return missing
end

-- Opt-in sweep: step the viewed outfit through the ones we have never seen, recording each.
--
-- Deliberately not automatic. ChangeViewedOutfit mutates UI state the player can see, and is
-- declared SecretArguments = "AllowedWhenUntainted", so it may simply refuse to work when
-- called from an addon. Every step is therefore verified rather than assumed, and the
-- original viewed outfit is restored at the end.
local SCAN_STEP = 0.2

local function IsTransmogFrameShown()
    return TransmogFrame and TransmogFrame.IsShown and TransmogFrame:IsShown() and true or false
end

-- Both checks exist on both clients. A client that refuses to answer is treated as having
-- pending changes: the cost of a wrong "no" is the player's unsaved work.
local function HasPendingChanges()
    for _, fn in ipairs({ C_TransmogOutfitInfo.HasPendingOutfitTransmogs, C_TransmogOutfitInfo.HasPendingOutfitSituations }) do
        if type(fn) == "function" then
            local ok, pending = ns.Util.SafeCall(fn)
            if not ok or pending then
                return true
            end
        end
    end

    return false
end

function OutfitCache:Scan()
    local Report = ns.Print

    if self.scanning then
        Report("A scan is already running.")
        return false
    end

    if not ns.Capabilities.hasSituations then
        Report("Situations are not available on this client.")
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        Report("Not during combat.")
        return false
    end

    if type(C_TransmogOutfitInfo.ChangeViewedOutfit) ~= "function" then
        Report("This client has no ChangeViewedOutfit.")
        return false
    end

    -- Changing the viewed outfit only makes sense while the transmog window is driving it.
    if not IsTransmogFrameShown() then
        Report("Open the transmog window first - the scan drives its outfit selection.")
        return false
    end

    -- Blizzard's own outfit list never switches outfits during a transmog event
    -- (TransmogOutfitEntryMixin:OnClick, both clients); the list is locked to the event outfit.
    local okEvent, inEvent = ns.Util.SafeCall(C_TransmogOutfitInfo.InTransmogEvent)
    if okEvent and inEvent then
        Report("Not during a transmog event.")
        return false
    end

    -- Switching the viewed outfit discards unapplied edits. Blizzard's list asks first
    -- (TransmogOutfitEntryMixin:CheckPendingAction shows TRANSMOG_PENDING_CHANGES); a scan has
    -- no business deciding that for the player, so it refuses instead.
    if HasPendingChanges() then
        Report("You have unapplied transmog or situation changes. Apply or undo them first.")
        return false
    end

    local okOriginal, original = ns.Util.SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
    if not okOriginal or type(original) ~= "number" then
        Report("Could not read the currently viewed outfit.")
        return false
    end

    self:Prune()
    local pending = self:GetUnrecordedOutfits()
    if #pending == 0 then
        Report("Every outfit is already recorded.")
        return true
    end

    Report(string.format("Scanning %d outfit(s)...", #pending))

    self.scanning = true
    local index, recorded, failed = 0, 0, 0

    local function Finish(abortReason)
        self.scanning = false

        -- An aborted scan leaves the viewed outfit alone: the player is editing it now, or the
        -- window is shut and Blizzard re-selects on the next open.
        if abortReason then
            Report(string.format("Scan stopped (%s): %d outfit(s) recorded.", abortReason, recorded))
            return
        end

        if original ~= 0 then
            ns.Util.SafeCall(C_TransmogOutfitInfo.ChangeViewedOutfit, original)
        end

        if failed > 0 then
            Report(
                string.format(
                    "Scan finished: %d recorded, %d could not be viewed (the client may not allow an addon to change outfits).",
                    recorded,
                    failed
                )
            )
        else
            Report(string.format("Scan finished: %d outfit(s) recorded.", recorded))
        end
    end

    local ticker
    ticker = C_Timer.NewTicker(
        SCAN_STEP,
        function()
            index = index + 1

            if index > #pending then
                ticker:Cancel()
                Finish()
                return
            end

            -- The player can close the window or start editing between two steps.
            local abortReason = nil
            if not IsTransmogFrameShown() then
                abortReason = "transmog window closed"
            elseif HasPendingChanges() then
                abortReason = "unapplied changes"
            end
            if abortReason then
                ticker:Cancel()
                Finish(abortReason)
                return
            end

            local target = pending[index].outfitID
            ns.Util.SafeCall(C_TransmogOutfitInfo.ChangeViewedOutfit, target)

            -- Verify rather than assume: if the client refused, recording now would write
            -- the previous outfit's assignments under the target's id.
            local okViewed, viewed = ns.Util.SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
            if not okViewed or viewed ~= target then
                failed = failed + 1
                return
            end

            if self:RecordViewed() then
                recorded = recorded + 1
            else
                failed = failed + 1
            end
        end,
        #pending + 1
    )

    return true
end

function OutfitCache:Init()
    if not ns.Capabilities.hasSituations then
        return
    end

    -- Record whenever the viewed outfit or its assignments change. RecordViewed itself skips
    -- the calls made mid-edit, so the commit (or the next view) is what gets written down.
    -- TRANSMOG_OUTFITS_CHANGED fires when the outfit list is rebuilt, which is how the list label
    -- picks up a committed edit: cheap insurance for the commit path below, and the one moment
    -- to forget outfits that are gone.
    ns.Triggers:Subscribe(
        function(event)
            if event == "TRANSMOG_OUTFITS_CHANGED" then
                self:Prune()
                self:RecordViewed()
            elseif event == "VIEWED_TRANSMOG_OUTFIT_CHANGED" or event == "VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED" then
                self:RecordViewed()
            end
        end
    )

    -- The Situations tab's Apply button calls CommitPendingSituations and nothing else
    -- (Blizzard_Transmog.lua, TransmogWardrobeSituationsMixin:OnLoad, both clients). Every
    -- event fired during the edit was skipped as pending, so without this the committed
    -- assignment is only written down if the player happens to view the outfit again.
    -- A post-hook on the api table does not taint the caller. Deferred one frame so the
    -- pending state has certainly cleared.
    if type(C_TransmogOutfitInfo.CommitPendingSituations) == "function" then
        hooksecurefunc(
            C_TransmogOutfitInfo,
            "CommitPendingSituations",
            function()
                if C_Timer and C_Timer.After then
                    C_Timer.After(
                        0,
                        function()
                            self:RecordViewed()
                        end
                    )
                else
                    self:RecordViewed()
                end
            end
        )
    end
end
