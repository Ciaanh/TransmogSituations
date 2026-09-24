local _, ns = ...

-- Phase 4, part two: which outfits match the situation the player is in right now.
--
-- This is a reconstruction. Blizzard resolves the real answer server-side and reports it
-- through GetActiveOutfitID, so the rules can be checked against the truth -- see Verify().
-- Blizzard picks at random among the eligible outfits, so the check is whether its pick is
-- one of ours. Treat a disagreement as a fact about rules we have not learned, not as noise.

local Eligibility = {}
ns.Eligibility = Eligibility

-- Why an outfit could not even be compared: a gap in the cache, not a verdict of the rules.
Eligibility.NOT_RECORDED = "not recorded"
Eligibility.STALE = "changed since last viewed"

function Eligibility.IsCacheGap(reason)
    return reason == Eligibility.NOT_RECORDED or reason == Eligibility.STALE
end

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
            valueName = result.optionName
        }
    end

    return current
end

-- An outfit matches when every category it constrains is satisfied. `info` is the outfit's
-- GetOutfitsInfo entry, used to catch a cache entry the outfit has since outgrown. Returns
-- true plus the names of the categories it pins, or false/nil plus the reason.
function Eligibility:Match(outfitID, current, info)
    local entry = ns.OutfitCache:Get(outfitID)
    if not entry then
        return nil, Eligibility.NOT_RECORDED
    end

    if ns.OutfitCache:IsStale(outfitID, info) then
        return nil, Eligibility.STALE
    end

    local matched = {}

    for triggerID, selected in pairs(entry.categories) do
        -- Nothing selected in a category, or an "All ..." selection, means the outfit does
        -- not care about it. Wildcards are decided before anything is asked of the live
        -- value: on Retail the Weather trigger is permanently unsupported, and an outfit
        -- ticked "All Weather" must still match there.
        if ns.OutfitCache.Constrains(selected) then
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
                return false, string.format("%s is %s", live.categoryName, tostring(live.valueName))
            end

            table.insert(matched, live.categoryName)
        end
    end

    return true, nil, matched
end

-- All matching outfits, in the outfit list's order, and all the others with the reason each was
-- rejected. The eligible ones are not ranked: Blizzard treats every eligible outfit as equal and
-- picks one at random. Its own Situations tab says "If multiple outfits are equally valid, one
-- will be chosen randomly", and the Retail tiebreak run (2026-09-23) confirmed that "equally
-- valid" means *every* match -- five re-picks with three outfits eligible, constraining 3, 2 and
-- 1 categories, landed on all three. `specificity` is a plain count of the categories an outfit
-- pins, for display only.
function Eligibility:GetEligible()
    local current = self:GetCurrentKeys()
    local eligible, rejected = {}, {}

    for _, info in ipairs(ns.OutfitCache:GetOutfits()) do
        local isMatch, reason, matched = self:Match(info.outfitID, current, info)
        local row = { outfitID = info.outfitID, name = info.name, index = info.playerFacingOutfitIndex }

        if isMatch then
            row.matched = matched
            row.specificity = #matched
            table.insert(eligible, row)
        else
            row.reason = reason
            table.insert(rejected, row)
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
-- among equals there is no single outfit to predict, so the test is membership: the rules hold
-- when the applied outfit is one of the eligible ones. The pick is also sticky -- no situation
-- change, no re-pick, and /reload keeps it (Retail, 2026-09-23) -- so a verify taken long after
-- the last trigger scores the pick made then, against the rules as they are now.
--
-- GetEligible already sorted every outfit into eligible or rejected-with-a-reason, so the verdict
-- is read off the applied outfit's row. Only one verdict indicts the rules; the rest say why this
-- run cannot score them:
--   "agrees"       the applied outfit is eligible, or none is applied and none is eligible
--   "disabled"     situations are switched off, so Blizzard is not picking at all
--   "none-applied" nothing is applied although outfits are eligible. The pick is only made on a
--                  situation change, so this is a moment without a pick, not a wrong one
--   "not-recorded" the applied outfit has a cache gap (never viewed, changed since), so it
--                  could not have been matched at all
--   "disagrees"    the applied outfit is recorded and current, and the rules reject it
Eligibility.VERDICT_AGREES = "agrees"
Eligibility.VERDICT_DISABLED = "disabled"
Eligibility.VERDICT_NONE_APPLIED = "none-applied"
Eligibility.VERDICT_NOT_RECORDED = "not-recorded"
Eligibility.VERDICT_DISAGREES = "disagrees"

function Eligibility:Verify()
    local okActive, activeOutfitID = ns.Util.SafeCall(C_TransmogOutfitInfo.GetActiveOutfitID)
    if not okActive then
        return nil
    end

    local eligible, rejected = self:GetEligible()
    local report = {
        activeOutfitID = activeOutfitID,
        eligible = eligible,
        recorded = ns.OutfitCache:Count(),
        unrecorded = 0,
        activeEligible = false,
        activeRecorded = false
    }

    for _, row in ipairs(eligible) do
        if row.outfitID == activeOutfitID then
            report.activeEligible = true
            report.activeRecorded = true
        end
    end

    for _, row in ipairs(rejected) do
        if Eligibility.IsCacheGap(row.reason) then
            report.unrecorded = report.unrecorded + 1
        end
        if row.outfitID == activeOutfitID then
            report.activeReason = row.reason
            report.activeRecorded = not Eligibility.IsCacheGap(row.reason)
        end
    end

    -- Only a definite false counts: a client that will not say is scored as usual.
    local okEnabled, enabled = ns.Util.SafeCall(C_TransmogOutfitInfo.GetOutfitSituationsEnabled)
    report.situationsDisabled = okEnabled and enabled == false

    report.noneApplied = type(activeOutfitID) ~= "number" or activeOutfitID == 0

    if report.situationsDisabled then
        report.verdict = Eligibility.VERDICT_DISABLED
    elseif report.activeEligible or (report.noneApplied and #eligible == 0) then
        report.verdict = Eligibility.VERDICT_AGREES
    elseif report.noneApplied then
        report.verdict = Eligibility.VERDICT_NONE_APPLIED
    elseif not report.activeRecorded then
        report.verdict = Eligibility.VERDICT_NOT_RECORDED
    else
        report.verdict = Eligibility.VERDICT_DISAGREES
    end
    report.agrees = report.verdict == Eligibility.VERDICT_AGREES

    return report
end
