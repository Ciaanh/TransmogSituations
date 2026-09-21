local _, ns = ...

-- Phase 4, part two: which outfits match the situation the player is in right now.
--
-- This is a prediction. Blizzard resolves the real answer server-side and reports it through
-- GetActiveOutfitID, so every prediction can be checked against the truth -- see Verify().
-- Treat a disagreement as a fact about the rules we have not learned yet, not as noise.

local Eligibility = {}
ns.Eligibility = Eligibility

-- Every option key that is true right now, per category. Locations is multi-valued (a
-- neighborhood is also a rest area), so a category can contribute more than one key.
function Eligibility:GetCurrentKeys()
    local current = {}

    for _, entry in ipairs(ns.Triggers:ResolveAll()) do
        local result = entry.result
        local keys = {}

        if result.state == ns.Triggers.STATE_OK and result.option then
            keys[ns.OutfitCache.OptionKey(result.option)] = true
        end

        for _, situationID in ipairs(result.also or {}) do
            local optionData = ns.Triggers:FindOptionBySituation(entry.triggerID, situationID)
            if optionData then
                keys[ns.OutfitCache.OptionKey(optionData.option)] = true
            end
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

-- An outfit matches when every category it constrains is satisfied.
function Eligibility:Match(outfitID, current)
    local entry = ns.OutfitCache:Get(outfitID)
    if not entry then
        return nil, "not recorded"
    end

    local matched, unconstrained = {}, 0

    for triggerID, selected in pairs(entry.categories) do
        -- Nothing selected in a category means the outfit does not care about it.
        if selected.any then
            local live = current[triggerID]

            if not live then
                -- The outfit constrains a category this client no longer offers. It cannot
                -- be satisfied, so it cannot match.
                return false, string.format("constrains trigger %d, which this client has no category for", triggerID)
            end

            if not live.resolved then
                return false, string.format("%s could not be determined", live.categoryName)
            end

            if selected.wildcard then
                -- An "All ..." selection satisfies the category without comparing.
                table.insert(matched, live.categoryName)
            else
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
            end
        else
            unconstrained = unconstrained + 1
        end
    end

    return true, nil, matched, unconstrained
end

-- All matching outfits, most specific first. Specificity is the number of categories the
-- outfit actually constrains: an outfit pinned to Raids beats one that matches everything.
function Eligibility:GetEligible()
    local current = self:GetCurrentKeys()
    local eligible, rejected = {}, {}

    local ok, outfits = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitsInfo)
    if not ok or type(outfits) ~= "table" then
        return eligible, rejected, current
    end

    for _, info in ipairs(outfits) do
        local isMatch, reason, matched = self:Match(info.outfitID, current)

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

    return {
        activeOutfitID = activeOutfitID,
        predictedOutfitID = predicted and predicted.outfitID or nil,
        agrees = (predicted and predicted.outfitID or nil) == activeOutfitID,
        eligible = eligible,
        recorded = ns.OutfitCache:Count(),
        unrecorded = #ns.OutfitCache:GetUnrecordedOutfits()
    }
end

function Eligibility:Init(api)
    self.api = api
end
