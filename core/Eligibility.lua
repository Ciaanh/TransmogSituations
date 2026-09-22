local _, ns = ...

-- Phase 4, part two: which outfits match the situation the player is in right now.
--
-- This is a reconstruction. Blizzard resolves the real answer server-side and reports it
-- through GetActiveOutfitID, so the rules can be checked against the truth -- see Verify().
-- Blizzard picks at random among the eligible outfits, so the check is whether its pick is
-- one of ours. Treat a disagreement as a fact about rules we have not learned, not as noise.

local Eligibility = {}
ns.Eligibility = Eligibility

-- Every option key that is true right now, per category. Categories can be multi-valued (a
-- house is also a rest area; a talent loadout is also its spec), so a category can contribute
-- more than one key. Triggers already normalised the secondary ones into alsoOptions.
function Eligibility:GetCurrentKeys()
    local current = {}

    for _, entry in ipairs(ns.Triggers:ResolveAll()) do
        local result = entry.result
        local keys = {}

        if result.state == ns.Triggers.STATE_OK and result.option then
            keys[ns.OutfitCache.OptionKey(result.option)] = true
        end

        for _, optionData in ipairs(result.alsoOptions or {}) do
            keys[ns.OutfitCache.OptionKey(optionData.option)] = true
        end

        current[entry.triggerID] = {
            keys = keys,
            resolved = result.state == ns.Triggers.STATE_OK,
            categoryName = entry.categoryName,
            displayName = entry.displayName
        }
    end

    return current
end

-- An outfit matches when every category it constrains is satisfied. `info` is the outfit's
-- GetOutfitsInfo entry, used to catch a cache entry the outfit has since outgrown.
function Eligibility:Match(outfitID, current, info)
    local entry = ns.OutfitCache:Get(outfitID)
    if not entry then
        return nil, "not recorded"
    end

    if ns.OutfitCache:IsStale(outfitID, info) then
        return nil, "changed since last viewed"
    end

    local matched, unconstrained = {}, 0

    for triggerID, selected in pairs(entry.categories) do
        -- Nothing selected in a category, or an "All ..." selection, means the outfit does
        -- not care about it. Wildcards are decided before anything is asked of the live
        -- value: on Retail the Weather trigger is permanently unsupported, and an outfit
        -- ticked "All Weather" must still match there. (If Blizzard's defaults tick every
        -- "All", the old order rejected every outfit on Retail.)
        if selected.any and not selected.wildcard then
            local live = current[triggerID]

            if not live then
                -- The outfit constrains a category this client no longer offers. It cannot
                -- be satisfied, so it cannot match.
                return false, string.format("constrains trigger %d, which this client has no category for", triggerID)
            end

            if not live.resolved then
                return false, string.format("%s could not be determined", live.categoryName)
            end

            local hit = false
            for key in pairs(live.keys) do
                if selected.keys[key] then
                    hit = true
                end
            end

            if not hit then
                return false, string.format("%s is %s", live.categoryName, tostring(live.displayName))
            end

            table.insert(matched, live.categoryName)
        else
            unconstrained = unconstrained + 1
        end
    end

    return true, nil, matched, unconstrained
end

-- All matching outfits, in the outfit list's order. They are not ranked: Blizzard treats every
-- eligible outfit as equal and picks one at random. Its own Situations tab says "If multiple
-- outfits are equally valid, one will be chosen randomly", and the Retail tiebreak run
-- (2026-09-23) confirmed that "equally valid" means *every* match -- five re-picks with three
-- outfits eligible, constraining 3, 2 and 1 categories, landed on all three. Ranking by
-- specificity, as this used to, was wrong. `specificity` is kept on each entry as a plain count
-- of the categories the outfit pins, for display only.
function Eligibility:GetEligible()
    local current = self:GetCurrentKeys()
    local eligible, rejected = {}, {}

    local ok, outfits = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitsInfo)
    if not ok or type(outfits) ~= "table" then
        return eligible, rejected, current
    end

    for _, info in ipairs(outfits) do
        local isMatch, reason, matched = self:Match(info.outfitID, current, info)

        if isMatch then
            table.insert(
                eligible,
                {
                    outfitID = info.outfitID,
                    name = info.name,
                    index = info.playerFacingOutfitIndex,
                    specificity = #matched,
                    matched = matched
                }
            )
        else
            table.insert(
                rejected,
                {
                    outfitID = info.outfitID,
                    name = info.name,
                    index = info.playerFacingOutfitIndex,
                    reason = reason
                }
            )
        end
    end

    table.sort(
        eligible,
        function(a, b)
            return (a.index or 0) < (b.index or 0)
        end
    )

    return eligible, rejected, current
end

-- Score the matching rules against the outfit Blizzard actually applied. With a random pick
-- among equals there is no single outfit to predict, so the test is membership: the rules
-- hold when the applied outfit is one of the eligible ones. The pick is also sticky -- no
-- situation change, no re-pick, and /reload keeps it (Retail, 2026-09-23) -- so a verify taken
-- long after the last trigger scores the pick made then, against the rules as they are now.
function Eligibility:Verify()
    local okActive, activeOutfitID = ns.Util.SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
    if not okActive then
        return nil
    end

    local eligible = self:GetEligible()

    -- The applied outfit can only be scored if we could have matched it. While the
    -- active outfit has no usable cache entry (never viewed, or changed since), Match rejects
    -- it out of hand, so it can never be among the eligible, and the resulting disagreement
    -- says nothing whatever about the matching rules. Report the
    -- difference so a gap in the cache is never read as evidence against the matcher.
    local activeRecorded = false
    if type(activeOutfitID) == "number" and activeOutfitID ~= 0 and ns.OutfitCache:Get(activeOutfitID) then
        local okOutfits, outfits = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitsInfo)
        local activeInfo = nil
        for _, info in ipairs(okOutfits and type(outfits) == "table" and outfits or {}) do
            if info.outfitID == activeOutfitID then
                activeInfo = info
            end
        end
        activeRecorded = not ns.OutfitCache:IsStale(activeOutfitID, activeInfo)
    end

    local activeEligible = false
    for _, entry in ipairs(eligible) do
        if entry.outfitID == activeOutfitID then
            activeEligible = true
        end
    end

    -- No outfit applied and none eligible is agreement too.
    local noneApplied = type(activeOutfitID) ~= "number" or activeOutfitID == 0

    return {
        activeOutfitID = activeOutfitID,
        activeRecorded = activeRecorded,
        activeEligible = activeEligible,
        agrees = activeEligible or (noneApplied and #eligible == 0),
        eligible = eligible,
        recorded = ns.OutfitCache:Count(),
        unrecorded = #ns.OutfitCache:GetUnrecordedOutfits()
    }
end

function Eligibility:Init(api)
    self.api = api
end
