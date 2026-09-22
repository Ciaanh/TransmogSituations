local _, ns = ...

-- Phase 4, part two: which outfits match the situation the player is in right now.
--
-- This is a prediction. Blizzard resolves the real answer server-side and reports it through
-- GetActiveOutfitID, so every prediction can be checked against the truth -- see Verify().
-- Treat a disagreement as a fact about the rules we have not learned yet, not as noise.

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

-- All matching outfits, most specific first. Specificity is the number of categories the
-- outfit pins to a real value -- wildcards do not count, since "All Weather" says nothing.
-- An outfit pinned to Raids beats one that matches everything.
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
            if a.specificity ~= b.specificity then
                return a.specificity > b.specificity
            end
            return (a.index or 0) < (b.index or 0)
        end
    )

    return eligible, rejected, current
end

-- The single outfit we would predict, or nil when nothing matches.
function Eligibility:Predict()
    local eligible = self:GetEligible()
    return eligible[1], eligible
end

-- Compare the prediction against the outfit Blizzard actually applied. This is the whole
-- point of the exercise: the rules are reverse-engineered, so they have to be scored.
function Eligibility:Verify()
    local okActive, activeOutfitID = ns.Util.SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
    if not okActive then
        return nil
    end

    local predicted, eligible = self:Predict()

    -- A prediction can only be scored against an outfit we could have predicted. While the
    -- active outfit has no usable cache entry (never viewed, or changed since), Match rejects
    -- it out of hand, the prediction is forced to something else -- usually nothing -- and the
    -- resulting disagreement says nothing whatever about the matching rules. Report the
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

    -- Blizzard's own Situations tab says "If multiple outfits are equally valid, one will be
    -- chosen randomly." So a miss where the applied outfit is itself eligible is a question
    -- about the tiebreak, not the matching rules, and the two must be reported apart.
    local activeEligible = nil
    for _, entry in ipairs(eligible) do
        if entry.outfitID == activeOutfitID then
            activeEligible = entry
        end
    end

    return {
        activeOutfitID = activeOutfitID,
        activeRecorded = activeRecorded,
        activeSpecificity = activeEligible and activeEligible.specificity or nil,
        predictedOutfitID = predicted and predicted.outfitID or nil,
        predictedSpecificity = predicted and predicted.specificity or nil,
        agrees = (predicted and predicted.outfitID or nil) == activeOutfitID,
        eligible = eligible,
        recorded = ns.OutfitCache:Count(),
        unrecorded = #ns.OutfitCache:GetUnrecordedOutfits()
    }
end

function Eligibility:Init(api)
    self.api = api
end
