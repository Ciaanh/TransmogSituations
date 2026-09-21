local _, ns = ...

-- Phase 4, part one: reconstruct the outfit -> situation mapping the client never exposes.
--
-- There is no API that answers "which situations is outfit N bound to". GetOutfitSituation
-- only ever answers for the *currently viewed* outfit, and GetOutfitsInfo's
-- situationCategories is a table of localized category names -- lossy, and useless for
-- matching. What we do have is that every option in the category tree carries a `value` flag
-- which IS the viewed outfit's assignment. So each time the player looks at an outfit we can
-- write its whole assignment down, and the picture fills in as they browse.

local OutfitCache = {}
ns.OutfitCache = OutfitCache

-- Spec and equipment-set options share one situationID and differ only by a secondary id, so
-- an option's identity is the triple. Anything comparing assignments must use this.
function OutfitCache.OptionKey(option)
    if not option then
        return nil
    end

    return string.format(
        "%d:%d:%d",
        tonumber(option.situationID) or 0,
        tonumber(option.specID) or 0,
        tonumber(option.equipmentSetID) or 0
    )
end

local function CharacterKey()
    local name = UnitName and UnitName("player") or nil
    if not name then
        return nil
    end

    return string.format("%s-%s", name, (GetRealmName and GetRealmName()) or "")
end

function OutfitCache:GetStore(create)
    local db = ns.BetterSituation and ns.BetterSituation.db
    local key = CharacterKey()
    if not db or not key then
        return nil
    end

    if not db.outfitSituations then
        if not create then
            return nil
        end
        db.outfitSituations = {}
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

    local categories = ns.Triggers:GetCategories()
    if #categories == 0 then
        return nil
    end

    local entry = { at = time(), categories = {} }
    local sawAny = false

    for _, category in ipairs(categories) do
        local selected = { wildcard = false, keys = {} }
        local any = false

        for _, optionData in ipairs(ns.Triggers:GetOptions(category.triggerID)) do
            if optionData.value then
                local key = OutfitCache.OptionKey(optionData.option)
                if key then
                    selected.keys[key] = true
                    any = true
                    sawAny = true

                    if ns.Triggers.WILDCARD_SITUATIONS[optionData.option.situationID] then
                        selected.wildcard = true
                    end
                end
            end
        end

        -- A category with nothing selected is unconstrained, which is a real state; it is
        -- stored so we can tell it apart from "never recorded".
        selected.any = any
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

-- Outfits the client knows about that we have never seen the player view.
function OutfitCache:GetUnrecordedOutfits()
    local missing = {}

    local ok, outfits = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitsInfo)
    if not ok or type(outfits) ~= "table" then
        return missing
    end

    for _, info in ipairs(outfits) do
        if not self:Get(info.outfitID) then
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

function OutfitCache:Scan(onDone)
    local function Report(msg)
        if self.api then
            self.api:Print(msg)
        end
    end

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
    if not (TransmogFrame and TransmogFrame.IsShown and TransmogFrame:IsShown()) then
        Report("Open the transmog window first - the scan drives its outfit selection.")
        return false
    end

    local okOriginal, original = ns.Util.SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
    if not okOriginal or type(original) ~= "number" then
        Report("Could not read the currently viewed outfit.")
        return false
    end

    local pending = self:GetUnrecordedOutfits()
    if #pending == 0 then
        Report("Every outfit is already recorded.")
        if onDone then
            onDone(0, 0)
        end
        return true
    end

    Report(string.format("Scanning %d outfit(s)...", #pending))

    self.scanning = true
    local index, recorded, failed = 0, 0, 0

    local function Finish()
        self.scanning = false
        ns.Util.SafeCall(C_TransmogOutfitInfo.ChangeViewedOutfit, original)

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

        if onDone then
            onDone(recorded, failed)
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

            local target = pending[index].outfitID
            ns.Util.SafeCall(C_TransmogOutfitInfo.ChangeViewedOutfit, target)

            -- Verify rather than assume: if the client refused, recording now would write
            -- the previous outfit's assignments under the target's id.
            local okViewed, viewed = ns.Util.SafeCall(C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID)
            if not okViewed or viewed ~= target then
                failed = failed + 1
                return
            end

            ns.Triggers:InvalidateCategories()
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

function OutfitCache:Init(api)
    self.api = api

    if not ns.Capabilities.hasSituations then
        return
    end

    -- Record whenever the viewed outfit or its assignments change. The category tree is
    -- invalidated on these same events, so by the time we read it the flags are fresh.
    local watcher = CreateFrame("Frame")
    watcher:SetScript(
        "OnEvent",
        function()
            self:RecordViewed()
        end
    )
    ns.Util.RegisterEventsSafely(
        watcher,
        { "VIEWED_TRANSMOG_OUTFIT_CHANGED", "VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED" }
    )
    self.watcher = watcher
end
