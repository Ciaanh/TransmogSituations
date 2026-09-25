---@diagnostic disable: undefined-global, lowercase-global
-- The Equipment Sets resolver, one scenario per way the client can report sets. There is no
-- "currently selected set" api: isEquipped means every non-ignored slot is worn, several sets
-- can report it at once, and the tie has to be broken deliberately.
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")

-- Verbatim from the Retail dump: ids start at 0, and the All row also carries 0.
H.categories = { H.Category(6, "Equipment Sets", { H.Opt("All Equipment Sets", 18),
    H.Opt("plop 1", 19, { equipmentSetID = 0 }), H.Opt("prout", 19, { equipmentSetID = 1 }),
    H.Opt("haha", 19, { equipmentSetID = 2 }) }) }
H.W.specIndex, H.W.specID = 1, 259

local function Set(id, name, isEquipped, numItems, numEquipped)
    return { id = id, name = name, isEquipped = isEquipped, numItems = numItems, numEquipped = numEquipped }
end

local function ThreeWorn()
    return { Set(0, "plop 1", true, 16, 16), Set(1, "prout", true, 16, 16), Set(2, "haha", true, 16, 16) }
end

local SCENARIOS = {
    -- Set id 0 is the case an old "value ~= 0" guard silently dropped.
    { "equipped", { Set(0, "plop 1", true, 16, 16), Set(1, "prout", false, 16, 2) }, { name = "plop 1" } },
    -- Verbatim from the second Retail dump: only "plop 1" is fully worn.
    { "distinct", { Set(0, "plop 1", true, 15, 15), Set(1, "prout", false, 15, 14), Set(2, "haha", false, 15, 14) },
        { name = "plop 1" } },
    -- All three report isEquipped, exactly as the first dump did. Nothing breaks the tie.
    { "allequipped", ThreeWorn(), { name = "plop 1", ambiguous = 3 } },
    -- Same tie, but the player applied "haha": what they applied wins.
    { "tiebreak", ThreeWorn(), { name = "haha" }, applied = 2 },
    -- Same tie, nothing applied, but "prout" is assigned to this spec.
    { "specassigned", ThreeWorn(), { name = "prout", specAssigned = true }, specSet = 1 },
    -- Applied "plop 1", then swapped one ring: still worn in any meaningful sense.
    { "swappedring", { Set(0, "plop 1", false, 16, 15), Set(1, "prout", false, 16, 1) },
        { name = "plop 1", approximate = true }, applied = 0 },
    -- Nothing worn, nothing applied: unknown, not a guess.
    { "partial", { Set(0, "plop 1", false, 16, 15), Set(1, "prout", false, 16, 1) }, { state = "unknown" } },
    -- A worn set with no option carrying its id must not borrow a neighbour's.
    { "idmismatch", { Set(77, "Healing", true, 16, 16) }, { state = "unknown" } },
}

local ns = H.Load()

for _, scenario in ipairs(SCENARIOS) do
    local label, sets, want = scenario[1], scenario[2], scenario[3]
    H.sets = sets
    H.specAssignedSet = scenario.specSet
    ns.Triggers.lastAppliedSetID = nil
    ns.TransmogSituations.db.lastAppliedSet = nil
    if scenario.applied then
        ns.Triggers:RememberAppliedSet(scenario.applied) -- as EQUIPMENT_SWAP_FINISHED would
    end
    ns.Triggers:InvalidateCategories()

    local result = ns.Triggers:Resolve(6)
    H.Section(label)
    H.Check("state", result.state, want.state or "ok")
    H.Check("value", result.optionName, want.name)
    H.Check("ambiguous", result.ambiguous, want.ambiguous)
    H.Check("specAssigned", result.specAssigned, want.specAssigned)
    H.Check("approximate", result.approximate, want.approximate)
end

H.Done()
