# BetterSituation — implementation plan

Living plan for the addon's evolution. Phases are ordered by dependency: Phase 1 produces the
trigger model that Phases 2, 3 and 4 all consume. Phase 0 is a blocker.

Terminology used throughout:

- **trigger / category** — a row on the Situations tab, identified by `triggerID`
  (from `GetUISituationCategoriesAndOptions()`). UI `triggerID`s are their own namespace and do
  **not** match `Enum.TransmogSituationTrigger`; see CLAUDE.md.
- **option** — one selectable entry inside a category, carrying a
  `TransmogSituationOption { situationID, specID, loadoutID, equipmentSetID }`.
- **current value** — the option a category resolves to *right now*, given the player's state.

---

## Phase 0 — Unbreak the Retail client (blocker) — DONE

`core/Diagnostics.lua:41` builds `WEATHER_TYPE_NAMES` at file scope by indexing
`Enum.WeatherType.Clear`. `C_Weather` and `Enum.WeatherType` do not exist on Retail, so this
throws while the file is loading and takes the whole addon down — not a missing weather line, a
total failure.

1. Guard the table behind `if Enum.WeatherType then ... end`, or build it lazily on first use.
2. Make `CollectEnvironmentSnapshot` treat weather as an optional subsystem: `C_Weather` absent →
   the Weather trigger reports *unsupported*, distinct from *unknown*.
3. Add a one-time capability probe (`ns.Capabilities`) resolved at load: `hasWeather`,
   `hasSituations`, `hasDelves`. Everything downstream asks the probe instead of re-testing globals
   ad hoc.

**Verify:** load on Retail with `/console scriptErrors 1` — no Lua error, `/bs` prints every line
with Weather marked unsupported.

---

## Phase 1 — A single trigger model — DONE

Today the "current value" logic lives in `Diagnostics.lua` as ad-hoc detector functions returning
**English display strings** (`"Rest Area"`, `"Flying Mount"`, `"Midday"`). Three problems: the
strings can't be compared to anything, they are not localized, and `"Midday"` doesn't even
correspond to the enum's `TimeDay`. Every later phase needs a comparable, localization-free value.

**Target shape.** One module, `core/Triggers.lua`, exposing a registry keyed by `triggerID`:

```lua
ns.Triggers:Resolve(triggerID)
  --> { situationID = <Enum.TransmogSituation>, extra = { specID?, equipmentSetID?, loadoutID? },
  --    state = "ok" | "unsupported" | "unknown" }
```

Rules:

- The canonical output is a **`situationID`**, never a string.
- Display text is looked up from the option names the client already returned in
  `GetUISituationCategoriesAndOptions()` — so the UI is localized for free and can never drift
  from Blizzard's own wording. Fall back to a neutral placeholder if no option matches.
- Each resolver declares the events that invalidate it, so refreshes are event-driven rather than
  a blanket 2-second ticker (see Phase 2).

**Resolvers, and what is actually known about each:**

| Trigger | Source | Status |
| --- | --- | --- |
| Locations | `IsInInstance()` → Arenas / Battlegrounds / Raids / Dungeons, `C_DelvesUI.HasActiveDelve()` → Delves, `IsResting()` → Rested, else World | `LocationHouse` mapping is **a guess** — current code uses `IsIndoors()`, but the enum name suggests player housing. Must be confirmed in game. `LocationCharacterSelect` is unreachable from an addon. |
| Movement | `IsSwimming()`, `IsMounted()` + `IsFlying()` | Solid. Note dragonriding/skyriding may need to report as flying — verify. |
| Specializations | `C_SpecializationInfo.GetSpecialization()` → `specID`, matched against `option.specID` | Options also carry `loadoutID`, so this category can be **per-talent-loadout**, not just per-spec. Cross-check against `C_ClassTalents.GetActiveConfigID()`. Not currently handled. |
| Equipment Sets | `C_EquipmentSet.GetEquipmentSetIDs()` + `GetEquipmentSetInfo(id)` → `isEquipped`, matched against `option.equipmentSetID` | **Not implemented at all today.** Zero or several sets may be equipped; define the "none equipped" result explicitly. |
| Racial Forms | `C_PlayerInfo.GetAlternateFormInfo()` → `FormNative` / `FormNonNative` | Solid. Category is absent for races without alternate forms. |
| Weather | `C_Weather.GetCurrentWeather()` → Clear/Rain/Snow/Sandstorm | `Enum.WeatherType.Miscellaneous` (4) has **no** `TransmogSituation` counterpart — decide whether it degrades to Clear or reports unknown. Unsupported on Retail. |
| Time of Day | `GetGameTime()` hour → Morning / Day / Evening / Night | Thresholds in the current code are **invented** (6/12/17/21) and the labels don't match the enum. Derive the real boundaries empirically by sampling, then hardcode with a comment recording how they were found. |

**Verify:** `/bs` prints, per category the client actually offers, the resolved option name plus its
`situationID`. Compare each against what Blizzard's own dropdown shows as selectable.

---

## Phase 2 — Inline current value on the Situations tab — DONE, pending in-game check

Replaces the current detached "Current Conditions" block, which fights the situation list for
space.

Blizzard's row template (`TransmogSituationTemplate`, `Blizzard_TransmogTemplates.xml:1309`) is
554×50 with `Title` (`GameFontNormal`, 170 wide, `maxLines="2"`) at `TOPLEFT (35, -19)` and
`Dropdown` (305 wide) anchored `RIGHT (-35, -2)`. That leaves roughly 9px of horizontal gap
between title and dropdown — so the value has to go **under the title**, anchored to
`Title`'s `BOTTOMLEFT` so it flows correctly when a title wraps to two lines.

1. Attach lazily, once per pooled row: keep the FontString on the frame object itself
   (`frame.BetterSituationValue`), because `SituationFramePool` reuses frames across
   `ReleaseAll()` / `Acquire()` cycles.
2. Read `frame.elementData.triggerID` and render `ns.Triggers:Resolve(triggerID)` in a small
   font (`GameFontHighlightSmall`), greyed when the category is unsupported.
3. Refresh on Blizzard's own lifecycle rather than a timer.

**Gotcha that will bite:** the existing plan note in `_refs/` says the mixin is "hookable via
`hooksecurefunc`". That is wrong for the *mixin table* — XML `mixin="..."` copies the functions
onto the frame at creation, so hooking `TransmogWardrobeSituationsMixin` afterwards affects
nothing. Hook the **instance**: `hooksecurefunc(situationsFrame, "Init", ...)` and
`hooksecurefunc(situationsFrame, "Refresh", ...)`.

4. Keep a ticker only for triggers with no backing event (mount/swim state). Weather has
   `WEATHER_CHANGED`; spec, zone and equipment sets all have events. Drop the blanket 2s poll to
   just the movement resolver, and only while the tab is visible.

**Verify:** open the tab on a Worgen with equipment sets (maximum row count), confirm no overlap
with a two-line wrapped title, confirm values update on mount/dismount/zone change without
reopening, and confirm no taint when opening the dropdowns afterwards.

---

## Where this stands

All five phases are implemented and committed on `feat/situation-diagnostics`. Phases 0-2 have
been exercised in game on both clients; **phases 3 and 4 have never been run in game at all.**

Automated coverage is `./docs/tests/run.sh` — 18 checks: syntax, replays of the two real `/bs dump`
captures, every resolver branch, the category cache, the attach lifecycle, `/bs list` marking, the
eligibility matcher and eight equipment-set shapes. Run it after any change to the trigger model.

What that suite can and cannot do is worth stating plainly, because it has been mistaken for more
than once: it proves the mapping behaves as designed given an input. It does **not** prove the game
supplies the input we assume, and it cannot prove the matching rules are Blizzard's. Three
confidently-wrong mappings have already shipped in this project — the documented enum, ordinal
position, and the equipment-set id-0 guard — and each was caught only by a real `/bs dump`.

---

## In-game checks still outstanding

### Phases 3 and 4 — entirely unverified

- [ ] **`/bs panel`** renders (seen on Forever, 2026-09-22) and updates live (confirmed on Retail,
      2026-09-22). Still to check: drags, and remembers its position and shown state across `/reload`.
      The `BackdropTemplate` `pcall` fallback has never been taken.
- [x] **The passive cache populates.** CONFIRMED on Forever, 2026-09-22: clicking through the
      Situations tab took `/bs eligible` from "1 of 2 never viewed" to "All 2 outfits recorded",
      and the recorded assignments agree with `situationCategories` (`Situations Data.txt`, last
      section). Still open: that merely *opening* the tab records the outfit already selected
      (the `StartTracking` call), and a Retail run. Originally: click through several outfits on
      the Situations tab, then `/bs eligible` and confirm the "never viewed" count falls. Assignments are read through
      `GetOutfitSituation(option)`, the call Blizzard's dropdown uses; if the client refuses that
      call from an addon (it is `AllowedWhenUntainted`) the cache falls back to the tree's `value`
      flag, which has never been observed true. `/bs dump` shows both columns.
- [ ] **`/bs verify` agrees.** The single most valuable check in this document: it scores the
      reverse-engineered matcher against the outfit Blizzard actually applied. Run it in several
      situations. Disagreements are where the real rule is hiding.
      It only scores anything once the **active** outfit is in the cache: until then the matcher
      rejects it as "not recorded" before a rule is consulted, and `/bs verify` says
      "Not scored" rather than claiming the rules are wrong. Record first, then score.
      First results, Forever 2026-09-22: **two agreements** (an all-wildcard outfit alone; then
      Outfit 1 bound to equipment set "test" over two all-wildcard outfits). **One disagreement,
      caused by the cache, not the rules:** "hoo" had been reset to Defaults and applied, the
      cache still held its old Rest Area + Unmounted, and it outranked the real pick. Fixed two
      ways, both unverified in game: `CommitPendingSituations` is now post-hooked so an Apply is
      recorded, and an entry that contradicts the outfit's `situationCategories` is treated as
      stale (`OutfitCache:IsStale`) — not matched, counted as unrecorded, re-recorded by scan.
      `/bs verify` now also separates "applied outfit not eligible" (rules wrong) from "applied
      outfit eligible, different pick" (tiebreak).
      Retail, 2026-09-22: **agrees** with 7 outfits recorded — Blizzard applied "Mount" (id 39),
      we predicted it. First Retail score. Second agreement after logout/login ("Frost", id 2).
- [x] **`/bs scan`** WORKS on **both** clients, 2026-09-22 (Retail: "Scanning 6 outfit(s)... 6 recorded"). Forever: "Scanning 1 outfit(s)... Scan finished: 1 outfit(s)
      recorded", so `ChangeViewedOutfit` is honoured from an addon. The outfit it re-recorded was the
      one `IsStale` had flagged, which is also the first sign the stale check works in game. Still
      to check: the original viewed outfit is restored afterwards. It may refuse outright — `ChangeViewedOutfit` is `AllowedWhenUntainted`, so the
      client may not honour it from an addon. It guards and verifies each step, so a refusal should
      report "could not be viewed" rather than corrupt the cache. Confirm that is what happens.
- [ ] **Specificity ranking is a guess.** When several outfits match, we prefer the one constraining
      the most categories. Blizzard's actual tiebreak is unknown; `/bs verify` is how to find it.
      Blizzard's own Situations tab text (both screenshots, 2026-09-22): *"If multiple outfits are
      equally valid, one will be chosen randomly."* Whether "equally valid" means *every* match or
      only matches of equal specificity is exactly the open question — "Tiebreak disagrees" from
      `/bs verify` is evidence for the former. Also worth ruling out: Blizzard may keep the current
      outfit while it stays valid rather than re-picking.
- [ ] **The cache must survive a relog.** `/reload` CONFIRMED on Retail, 2026-09-22: scan, `/reload`,
      and `/bs verify` still saw all 7 outfits. Logout/login CONFIRMED on Retail the same day: still 7
      recorded, and `/bs verify` agreed again (Blizzard applied "Frost", id 2; we predicted it).
      **Blocked on Forever, a known client bug:** The Forever
      beta does not reliably persist SavedVariables across `/reload` or logout (known beta issue,
      2026-09-22). Seen: the account file written at 23:26:41 with three outfits, rewritten at
      23:29:06 with only `debug` and `panel`. Nothing in the addon is at fault. Until Blizzard fixes
      it, on Forever the cache, `lastAppliedSet` and the panel position last one session: run
      `/bs scan` after each login. Persistence can only be verified on Retail for now.
- [ ] **Recording after Apply** (new, 2026-09-22). Edit an outfit, press Apply, and without clicking
      another outfit run `/bs eligible`: nothing should be reported as changed. Then reset one
      with Defaults + Apply and confirm `/bs dump` / `/bs list` show the new assignment.

### Phase 2 UI behaviour, still unverified

- [ ] Value updates live on mount/dismount and zone change **without** reopening the tab.
- [ ] No overlap when a localized category title wraps to two lines (the row is 50px with the title
      capped at `maxLines=2`); worth a look in French, which has the longest labels.
- [ ] The FontString survives Blizzard's pool cycle: open the tab, switch tabs, return, and confirm
      values are still there and not duplicated.
- [ ] No taint — open the situation dropdowns after our hooks have run, with
      `/console scriptErrors 1`.
- [ ] Layout with the Equipment Sets row present, which is the maximum row count.

### Equipment sets — one assumption left

- [x] ~~Equipment Sets resolve.~~ DONE on **both** clients. Ids start at 0, the All row shares
      equipmentSetID 0 so matching needs situationID 19 as well, and 18/19 are confirmed.
- [ ] **Last-applied fallback.** Apply a set, swap one item, confirm `/bs` still names the set with
      the `~` marker rather than going `?`. Then relog and confirm it survives.
      Half done, Forever 2026-09-22: `/bs` showed `test ~ (last applied, 7/8 worn)`. Relog not yet
      checked. Oddity from the same session: `test ~ (8/8 worn)` in Stormwind — every item worn yet
      `isEquipped=false`, so something other than the slot count fails the check (swimming? a
      durability or bag state?). Needs a `/bs dump` taken at that moment.
- [ ] **Does Blizzard agree with the fallback?** Bind an outfit to an equipment set, apply the set,
      swap one item. If Blizzard's own situation stops matching, strict `isEquipped` is right and
      the fallback should be removed. This decides an assumption, not a bug.

### Values seen for only one member of their set

Every one of these is handled by `docs/tests/resolvers.lua`, so the *mapping* is proven. What is
unproven is that the game reports what the resolver expects.

- [ ] **Locations:** seen — Rest Area, neighborhood outdoors, House inside the house (Retail,
      2026-09-22: type `interior`, `IsInsideHouse=true`, still resting), World (Forever,
      2026-09-22, Elwynn Forest). Unseen — Dungeons, Raids, Arenas, Battlegrounds, Delves.
      `Character Select` is unreachable from an addon.
- [ ] **Neighborhood outdoors → Rest Area** is a judgement call. If a neighborhood is ever
      un-rested it would fall through to World; unverified whether that matches Blizzard.
- [ ] **Movement:** seen — Unmounted, Ground Mount, Swimming (Forever, Stormwind canals, together
      with Rest Area). Unseen — Flying Mount, and whether
      skyriding/dragonriding makes `IsFlying()` true.
- [ ] **Weather:** seen — Clear only. Unseen — Rain, Snow, Sandstorm, the intensity percentage, and
      whether `Miscellaneous` (4) has any counterpart (open question 5). Untestable on Retail,
      which has no `C_Weather` — but the Weather *category* does exist there; only the API to read
      it is missing. So on Retail Blizzard can match an outfit bound to a specific weather while we
      cannot, and `/bs verify` will report that as a rules disagreement.
- [ ] **Time of Day:** seen — 23:03, 00:11 and 03:30 = Night, 13:41 and 14:08 = Midday. The band boundaries are still
      invented (open question 2); Morning and Evening have never been observed.
- [ ] **Racial Forms:** seen — Dracthyr visage. Unseen — Dracthyr dragon form, and Worgen, where the
      `inAlternateForm` polarity may not hold.
- [ ] **Specializations:** on Forever the category holds a single option named after the
      **class** ("Hunter", specID 1485; "Mage" on another character), and it resolves correctly —
      the class name is the client's own option name, not a resolver miss. Seen — one spec per client, and on Retail a mage with saved loadouts
      (per-loadout options confirmed). Unseen — switching spec or loadout live and watching the
      value follow, whether a loadout with unsaved changes still counts for Blizzard, what the
      starter build maps to, and a character under level 10 where the category should be absent.

---

## Housekeeping, not blocked on a game client

All done in the 2026-09-22 review pass: `CLAUDE.md` rewritten against the current module list,
`README.md` lists every command, toc bumped to `0.2.0`, dead code removed (`lastSnapshot`, the
unconditional `*` legend), `docs/` and `CLAUDE.md` are now tracked in git. `loadoutID` was removed
as dead the same day and then reinstated hours later when a Retail dump showed per-loadout options
(open question 3) — a reminder that "never matched" meant "never seen", not "never exists".

### Fixed by the 2026-09-22 review, still to confirm in game

- [x] ~~**Assignments are now read through `GetOutfitSituation(option)`**~~ CONFIRMED on Forever,
      2026-09-22 (`Situations Data.txt`, last section): with "Outfit 2" viewed, every "All" option
      answered `api=true` while `value=false` on every option. The api call works from an addon;
      the tree flag is dead. Two more facts fell out of the same dump: an outfit with an empty
      `situationCategories` has **every "All" ticked** (so the client's default is all wildcards,
      not "nothing selected"), and `situationCategories` therefore names exactly the categories
      with a non-wildcard selection — a free consistency check on a recorded entry. Confirmed on
      Retail too the same day ("Home" viewed: House `api=true`, `situationCategories = Locations`).
- [ ] **Recording is skipped while `HasPendingOutfitSituations()` is true**, since the api call
      answers with the pending state mid-edit. Confirm the commit (Apply button) triggers a
      record — if `VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED` does not fire on commit, the outfit
      is only recorded on the next view.
- [x] **Wildcards are decided before the live value is consulted.** An outfit ticked "All
      Weather" now matches on Retail, where Weather is unsupported. Wildcards also no longer
      count toward specificity. The Forever dump confirmed the premise: defaults tick every
      "All", so under the old order every outfit on Retail would have been rejected on Weather.
- [x] ~~**`instanceType == "interior"` is treated as housing**~~ CONFIRMED on Retail, 2026-09-22:
      inside a house `IsInInstance()` reports `interior` and `IsInsideHouse()` is true, and
      Locations resolved to House (7). Under the pre-review resolver, which only consulted
      `IsInsideHouse` under `neighborhood`, this would have been unknown. The Retail replay now
      switches to `interior` for its inside-house check.
- [ ] **Delves are detected via `HasActiveDelve()` before the instance type is examined**, as
      Blizzard's banner does. Enter a delve and confirm Locations reads Delves whether the type is
      `party` or `scenario`.
- [ ] **The panel persists visibility from OnShow/OnHide**, so closing it with Escape no longer
      brings it back on the next login.

### Deliberately closed, do not reopen without a reason

- The inline row on the Situations tab shows **only** the value: no reason, no also-active list, no
  approximate/ambiguous marker, no tooltip. That was a decision, not an oversight. `/bs` is where
  the detail lives.

---

## Phase 3 — Standalone panel — IMPLEMENTED, not yet verified in game

Same data as `/bs`, in a frame, for users who don't want chat spam.

1. `/bs panel` toggles it; persist shown/hidden plus position in `BetterSituationDB`.
2. Build it from the **same** `ns.Triggers` registry as Phase 2 — one row per category the client
   offers, so the panel automatically tracks conditional categories (Equipment Sets, Racial Forms,
   Specializations) and client differences.
3. Movable, closable, `UISpecialFrames` for Escape, no combat restrictions needed since nothing
   here is protected.
4. Refresh only while shown, driven by the same event set as Phase 2.

Deliberately excluded: minimap button, options UI. Not requested.

---

## Phase 4 — Dynamic eligible-set resolution — IMPLEMENTED, not yet verified in game

The stated end goal, and the part with a genuine API obstacle.

### The obstacle

There is **no API mapping an outfit to its situation options.** Specifically:

- `GetOutfitsInfo()` returns `TransmogOutfitEntryInfo`, whose `situationCategories` is a table of
  **localized display strings** — Blizzard just concatenates them for the outfit list label
  (`Blizzard_TransmogTemplates.lua:101`). Category-level and lossy; it cannot tell you *which*
  location was picked.
- `GetOutfitSituation(option)` returns a bool for the **currently viewed outfit only**.
- `UpdatePendingSituation` mutates the viewed outfit's pending state.

So the outfit→situation mapping has to be reconstructed client-side. Three strategies:

| Strategy | How | Verdict |
| --- | --- | --- |
| **A. Sweep** | `ChangeViewedOutfit(id)` across every outfit, read all options, restore the original | Complete and exact, but mutates UI state, fires events, and both calls are `SecretArguments = "AllowedWhenUntainted"` so addon taint can break them. Only ever on explicit user action, transmog frame open, out of combat. |
| **B. Passive cache** | Record the full option map for whichever outfit the user views, into SavedVariables keyed by `outfitID` | Zero intrusion, builds up naturally, survives sessions. Incomplete until the user has visited each outfit. |
| **C. Parse strings** | Read `situationCategories` | **Rejected** — localized and category-level. |

**Recommendation: B as the default, A as an explicit opt-in** (`/bs scan`) for users who want the
table filled immediately. Invalidate cache entries on
`VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED` and stamp each with a timestamp so staleness is
visible rather than silent.

**How the implementation reads an assignment.** An earlier revision of this section claimed the
option tree's `value` flag "is what Blizzard's checkboxes are driven from". It is not: Blizzard's
dropdown calls `C_TransmogOutfitInfo.GetOutfitSituation(option)` for every option
(`Blizzard_TransmogTemplates.lua`, `TransmogSituationMixin:Init`) and never reads `value`, and no
in-game capture has ever shown `value` true. `core/OutfitCache.lua` therefore asks
`GetOutfitSituation` per option and falls back to `value` only if that call is missing or refuses
us. It records on `VIEWED_TRANSMOG_OUTFIT_CHANGED` / `..._SITUATIONS_CHANGED`, skipping the calls
made while `HasPendingOutfitSituations()` is true, because the api answers with the pending state
mid-edit.

The tree is still fetched per viewed outfit and the cached copy is dropped on those events — which
is why they are in `Triggers.CATEGORY_EVENTS`, and why `RecordViewed` invalidates it itself rather
than relying on handler order. Forgetting that once made `/bs list` report the previous outfit's
assignments.

Assignments are keyed by the `situationID:specID:equipmentSetID` triple, not by `situationID`
alone: spec and equipment-set options all share one `situationID` and differ only in the secondary
id.

### The matching rules

An outfit is eligible when, for every category it constrains, the current value satisfies it:

- Each category is independent; an outfit unconstrained in a category matches any value there.
- The `All*` options are wildcards. **Use `Triggers.WILDCARD_SITUATIONS`, never a literal here.**
  The real ids are `AllSpecs=1`, `AllLocations=3`, `AllMovement=13`, `AllEquipmentSets=18`,
  `AllRacialForms=20`, `AllWeather=32`, `AllTime=37`. An earlier revision of this document listed
  the *generated enum* values (`0, 2, 12, 17, 19, 22, 27`) — exactly what the client contradicts.
  That version was actively dangerous: its `AllRacialForms=19` collides with the real
  `EquipmentSets=19`, so a matcher written from it would treat every specific equipment set as a
  wildcard that matches everything. Treat a wildcard as "category satisfied" without comparing
  further.
- Radio categories (`isRadioButton`) have exactly one selection; checkbox categories have a set,
  and match if the current value is in it.
- Several outfits can be eligible at once. Blizzard must have a tiebreak (specificity? outfit
  order?) — this is **unknown** and has to be reverse-engineered.

### Validating the model instead of trusting it

Blizzard resolves the active outfit server-side, and `GetActiveOutfitID()` reports the answer. That
makes the whole thing self-checking, which should be built in from the start rather than bolted on:

1. Every time the resolver runs, compare the prediction against `GetActiveOutfitID()`.
2. Log mismatches (behind the existing `BetterSituationDB.debug` flag) with the full trigger
   snapshot that produced them.
3. Ship the mismatch log as `/bs verify`. The tiebreak rule and the unknowns from Phase 1
   (`LocationHouse`, time-of-day boundaries) will fall out of the collected mismatches far faster
   than from guessing.

Only once mismatches are near zero is it worth exposing eligibility in the UI (highlighting
candidate outfits in the outfit list).

---

## Cross-cutting

- **Never hardcode English.** Every user-visible situation name comes from
  `GetUISituationCategoriesAndOptions()`. The French dump in `Situations Data.txt` is the
  regression case.
- **Never assume a category exists.** Drive everything off what the client returns.
- **Retail parity is a release gate,** not an afterthought — see CLAUDE.md, Client targets.
- **No taint.** Child frames and `hooksecurefunc` only; never replace pooled frames or touch the
  dropdown menu descriptions.
- **Everything reads `ns.Triggers`.** Chat, the tab overlay, the standalone panel and the
  eligibility matcher are four renderers over one model. Adding a fifth consumer means reading
  `ResolveAll()`, never re-deriving a value.

## Module map

```text
core/Util.lua          SafeCall / SafeCallAll / RegisterEventsSafely
core/Capabilities.lua  one-time probe of the optional systems (C_Weather, C_Housing, ...)
core/Triggers.lua      THE model: situationID table, resolvers, category cache
core/OutfitCache.lua   per-outfit situation assignments, recorded as the player browses
core/Eligibility.lua   matching, specificity ranking, and Verify() against GetActiveOutfitID
core/Diagnostics.lua   all chat output: /bs, list, dump, eligible, verify
core/StatusPanel.lua   the standalone /bs panel frame
core/SituationPanel.lua the inline values on Blizzard's Situations tab
BetterSituation.lua    bootstrap, slash commands, module Init order
```

Load order is fixed in the toc and matters: `Util` first (others capture its functions at file
scope), `Capabilities` before anything that probes, `Triggers` before its consumers.

## Open questions to settle in game

0. **What is Blizzard's tiebreak when several outfits match?** Still unknown, and now the largest
   open question: `core/Eligibility.lua` ranks by specificity (most categories constrained wins),
   which is a guess. `/bs verify` exists to find the real rule from disagreements.

1. ~~Does `LocationHouse` mean player housing or any indoor space?~~ ANSWERED: player
   housing. `IsInInstance()` reports `"neighborhood"` on the outdoor plots and `"interior"`
   inside the house (both confirmed on Retail); `C_Housing.IsInsideHouse()` is what decides House.
   `IsIndoors()` is not involved. Locations is also multi-valued — both the plots and the house
   interior are simultaneously a rest area.
2. What are the real Time of Day boundaries? (Datapoints: 23:03, 00:11, 03:30 = Night; 13:41,
   14:08 = Midday.)
3. ~~Does the Specializations category expose per-loadout options, or only per-spec?~~
   ANSWERED, and the first answer was wrong. Both early captures (a rogue, a Classic hunter) had
   no saved loadouts, so every option carried `loadoutID = 0` and the category looked per-spec.
   A Retail mage with four saved loadouts (2026-09-22) lists **one option per saved loadout**
   (`specID` + the loadout's configID as `loadoutID`) next to the per-spec option (`loadoutID 0`).
   Option names are not unique ("wowhead" three times, "Frost" as both spec and loadout), so only
   the ids identify an option. The resolver reads the selected loadout with
   `C_ClassTalents.GetLastSelectedSavedConfigID(specID)` (what Blizzard's talent frame uses); the
   loadout option becomes the value with the spec option alongside, and the cache key is now the
   4-tuple `situationID:specID:loadoutID:equipmentSetID`. Still open: whether Blizzard counts a
   loadout with unsaved changes, and what the starter build maps to.
4. What does Blizzard do when several outfits are eligible at once?
5. Does `Enum.WeatherType.Miscellaneous` map to a situation, or to nothing? (Untestable on
   Retail, which has no `C_Weather` at all; needs a Forever run.)
