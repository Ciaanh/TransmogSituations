# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

**TransmogSituations** — a World of Warcraft addon targeting the **WoW Forever beta** (a Classic
client running the modern retail UI). It surfaces the *live values* of transmog "situation"
triggers, which Blizzard's own Situations tab configures but never displays.

Goals, in order:
1. Show current situation-trigger values on the transmog **Situations tab**
   (`SituationsFrame`, `TransmogWardrobeSituationsMixin`).
2. Provide `/ts` (`/transmogsituations`) to read those values from chat at any time.
3. Resolve the **eligible transmog set** from the current trigger values, client-side.

All four phases of `_refs/ROADMAP.md` are implemented. Phases 0–2 have run in game on both
clients. Phases 3 and 4 (standalone panel, outfit cache, eligibility) have run **in part**: the
passive cache and `/ts scan` work on both clients, `/ts verify` has agreed on both, the panel
renders and updates live. Much is still unverified (panel persistence, recording on Apply, most
Location / Movement / Weather values). The roadmap's "In-game checks still outstanding" list is
the current to-do.

## Client targets

Forever beta is the **target**, but the addon must stay **compatible with live Retail**. The two
clients do not expose the same API surface, and Forever is the richer one — so anything discovered
in the Forever source must be treated as *possibly absent* until checked against the Retail source
too. Confirmed divergences:

| Symbol | Forever | Retail | Consequence |
| --- | --- | --- | --- |
| `C_Weather.GetCurrentWeather()` / `Enum.WeatherType` | yes | **no** | Weather trigger is *unsupported* on Retail. The Weather *category* still exists there — only the read API is missing, so Blizzard can match a specific weather that we cannot |
| `Enum.TransmogSituationTrigger.SettingsUpdate` (11) | yes | **no** (enum stops at 10) | never hardcode the enum's max value |
| House option (7) in Locations | **no** | yes | Locations has 8 options on Forever, 10 on Retail |
| Delves option (6) in Locations | **no** | yes | same |

`C_Housing` and `C_DelvesUI` **exist on both** clients (confirmed by `/ts dump`), so a
capability probe cannot tell you whether the option exists. Only the category tree can.

The situation APIs the addon depends on — `GetUISituationCategoriesAndOptions`,
`GetOutfitSituation`, `GetOutfitSituationsEnabled`, `GetActiveOutfitID`,
`GetCurrentlyViewedOutfitID`, `GetOutfitsInfo`, `HasPendingOutfitSituations`,
`ChangeViewedOutfit` — exist on both.

Practical rules:
- `core/Capabilities.lua` probes every optional system once at load (`hasWeather`, `hasHousing`,
  `hasDelves`, `hasEquipmentSets`, ...). Ask it; do not re-test globals at call sites.
- Enum members need their own nil check — `Enum.WeatherType.Clear` at file scope errors on load
  when the enum is missing, and no `pcall` can protect a file-scope index.
- A missing system means the value is reported as **unsupported** (distinct from **unknown**),
  never an error and never a hidden wrong default.
- Drive the UI off whatever `GetUISituationCategoriesAndOptions()` actually returns on the running
  client rather than a compile-time list of triggers.

## Layout

```
TransmogSituations.toc       # load order + Interface versions (120100 retail, 16001 classic)
TransmogSituations.lua       # addon namespace, SavedVariables, slash commands, ADDON_LOADED bootstrap
core/Util.lua                # SafeCall / SafeCallAll / RegisterEventsSafely / CharacterKey
core/Capabilities.lua        # one-time probe of the optional systems
core/Triggers.lua            # THE model: situationID table, resolvers, category cache
core/OutfitCache.lua         # per-outfit situation assignments, recorded as the player browses
core/Eligibility.lua         # matching, Verify() against GetActiveOutfitID
core/Diagnostics.lua         # all chat output: /ts, list, dump, eligible, verify
core/StatusPanel.lua         # the standalone /ts panel frame
core/SituationPanel.lua      # inline values on Blizzard's Situations tab
make-release.ps1             # stages + zips a release into .build/
tests/                       # Lua 5.1 replay tests, run with ./tests/run.sh
_refs/                       # local-only research notes (gitignored, never shipped), including:
  ROADMAP.md                 #   phased plan + the list of in-game checks still outstanding
  Situations Data.txt        #   captured in-game output + enum dumps (see Domain reference)
```

Load order is declared in `TransmogSituations.toc` and matters: `Util` first (others capture its
functions at file scope), `Capabilities` before anything that probes, `Triggers` before its
consumers, `OutfitCache` before `Diagnostics`. Adding a new file means adding it to the toc
**and** to `$includes` in `make-release.ps1` (which ships only the listed files, so `tests/` never
reaches the zip).

Module pattern: every file does `local _, ns = ...` and assigns a table onto `ns`. A module with
setup to do exposes `Module:Init()`, which `TransmogSituations.lua` calls from its `ADDON_LOADED`
handler. Chat output goes through `ns.Print(msg)`, never bare `print`. Slash commands are one
`COMMANDS` table in `TransmogSituations.lua` that drives both the dispatch and `/ts help`.

A resolved value is `{ state, situationID, optionName, option, alsoOptions, ... }`; `ResolveAll()`
wraps each in `{ triggerID, categoryName, result }`. Options are looked up with one function,
`Triggers:FindOption(triggerID, situationID, fields)`. The outfit list is read through
`OutfitCache:GetOutfits()`; reports never prune the cache (that happens on
`TRANSMOG_OUTFITS_CHANGED` and at the start of `/ts scan`, and never on an empty list).

**Everything reads `ns.Triggers`.** Chat, the tab overlay, the standalone panel and the
eligibility matcher are four renderers over one model. A new consumer reads `ResolveAll()` or
`Resolve(triggerID)`; it never re-derives a value.

**Triggers is also the only event listener.** It registers every event any resolver or consumer
needs, handles each one first (drops the category cache, remembers an applied equipment set),
then calls its subscribers in order. A module that needs to react calls
`Triggers:Subscribe(fn, wantsPolling)` and gets `fn(event, ...)`, plus `fn("POLL")` from the
single shared ticker while it asked for polling and a polled category exists. Never create
another event frame for game events; subscribe. (The bootstrap's `ADDON_LOADED` frame and
`SituationPanel`'s attach loader are the two exceptions: they run before or outside the model.)

## Build / test / release

```powershell
.\make-release.ps1            # PowerShell 7+; reads "## Version" from the toc -> .build/TransmogSituations-v<version>.zip
```

```sh
./tests/run.sh                # Lua 5.1 replay suite; LUA= / LUAC= override the interpreter path
```

Run the suite after any change under `core/`. It loads the addon through the toc and the real
`ADDON_LOADED` bootstrap against the stubs in `tests/harness.lua`, replays four real
`/ts dump` captures and drives every resolver branch. A new Blizzard api call needs its stub added
to the harness, once. See `tests/README.md`. It proves the mapping behaves as designed given an input; it cannot prove the game
supplies that input, and it cannot prove the matching rules are Blizzard's. Three
confidently-wrong mappings have shipped in this project and each was caught only by a real
`/ts dump` in game.

In-game verification: `/reload`, and `/console scriptErrors 1` when touching UI code.
`.vscode/settings.json` configures the Lua language server for Lua 5.1 with the ketho WoW API
annotations.

## Blizzard references

Two read-only UI source trees live outside the repo. Check a symbol in **both** before relying on it:

- Forever (target): `G:\Dev\WoW\_Workspace\Blizzard_UI_refs\Forever\BlizzardInterfaceCode\`
- Retail (compatibility floor): `G:\Dev\WoW\_Workspace\Blizzard_UI_refs\Retail\BlizzardInterfaceCode\`

Most relevant files, at the same relative paths in each tree:
- `Interface/AddOns/Blizzard_Transmog/Blizzard_Transmog.lua` — `TransmogWardrobeSituationsMixin`
  (~line 3030): `OnLoad` / `OnShow` / `OnHide` / `Init` / `Refresh`, `SituationFramePool`.
- `Interface/AddOns/Blizzard_Transmog/Blizzard_TransmogTemplates.lua` — `TransmogSituationMixin`
  (~line 1815): the row template; its dropdown reads selection via `GetOutfitSituation(option)`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/TransmogOutfitInfoDocumentation.lua` —
  authoritative signatures for `C_TransmogOutfitInfo.*`.
- `Interface/AddOns/Blizzard_FrameXML/InstanceDifficulty.lua` — how Blizzard detects delves
  (`HasActiveDelve()`, type-independent) and which instance types are housing. Confirmed in game
  on Retail: outdoor plots report `"neighborhood"`, the inside of a house reports `"interior"`,
  and `C_Housing.IsInsideHouse()` is what decides House.

## Domain reference

Frame path (only exists once `Blizzard_Transmog` is loaded):
`TransmogFrame.WardrobeCollection.TabContent.SituationsFrame`

The situation list is built from `C_TransmogOutfitInfo.GetUISituationCategoriesAndOptions()`, which
returns `TransmogSituationCategory` entries `{ triggerID, name, description, isRadioButton, groupData }`.
Observed in game (names are localized — never match on `name`, always on `triggerID`):

```
3  Locations        4  Movement       5  Specializations
6  Equipment Sets   7  Racial Forms   11 Weather          12 Time of Day
```

**Caveat:** these UI `triggerID`s do not line up with `Enum.TransmogSituationTrigger`, where
`Weather = 9`, `TimeOfDay = 10`, `SettingsUpdate = 11`. Treat the UI `triggerID` as its own
namespace.

### `option.situationID` is NOT an `Enum.TransmogSituation` value

Captured with `/ts dump` on both targets. The real ids are a permutation on a different base,
and they are **identical on Retail and Forever** for every option both clients offer:

```
AllSpecs=1  Spec=2
AllLocations=3  Rested=4  World=5  Delves=6  House=7  CharacterSelect=8
Dungeons=9  Raids=10  Arenas=11  Battlegrounds=12
AllMovement=13  Unmounted=14  Swimming=15  GroundMount=16  FlyingMount=17
AllEquipmentSets=18  EquipmentSet=19
AllRacialForms=20  FormNative=21  FormNonNative=22
AllWeather=32  Clear=33  Rain=34  Snow=35  Sand=36
AllTime=37  Morning=38  Midday=39  Evening=40  Night=41
```

The generated docs say `LocationHouse=4`, `LocationWorld=6`, `TimeNight=31` — wrong on both live
clients. **Treat the generated `Enum.TransmogSituation` as unusable** and use `Triggers.SITUATION`.

**What varies between clients is which options exist, not their ids.** Never identify an option by
its index in the category; match on `situationID`, and when no option carries it, report unknown
rather than falling back to a neighbour.

Specializations and Equipment Sets are variable-length and share one `situationID` across their
entries, so those are matched on `situationID` **plus** the secondary ids. Equipment set ids start
at 0 and the "All Equipment Sets" row also carries `equipmentSetID 0`, so the field alone is
ambiguous. **Specializations also lists one option per saved talent loadout** (`specID` + the
loadout's configID as `loadoutID`) next to the per-spec option (`loadoutID 0`); a character with
no saved loadouts shows only the per-spec options, which is how this was missed at first. Option
names are not unique, so only the ids identify an option. An option's identity for caching is the
4-tuple `situationID:specID:loadoutID:equipmentSetID` (`OutfitCache.OptionKey`).

Multi-valued categories: a house is also a rest area, and a selected loadout is also its spec.
`Triggers:AttachOption` normalises the secondary options into `result.alsoOptions`; consumers read
that, never the resolver's raw `also` list.

Categories are conditionally present — code must not assume a fixed list:
- **Equipment Sets** only if the player has at least one equipment set.
- **Racial Forms** only for races with multiple forms (Worgen, Dracthyr).
- **Specializations** lists only unlocked specs, so nothing before level 10.

The category list also changes mid-session (saving a first equipment set, reaching level 10), so
`Triggers` invalidates its cache on `Triggers.CATEGORY_EVENTS`.

### Outfit assignments (Phase 4)

There is no API mapping an outfit to its situations; only the *currently viewed* outfit can be
read. `OutfitCache` records it whenever it changes, asking `GetOutfitSituation(option)` per option
— the call Blizzard's own dropdown uses. Confirmed in game on Forever: the api answers true for
the assigned options while the option tree's `value` flag is false everywhere, so `value` is only
a fallback. Recording is skipped while `HasPendingOutfitSituations()` is true because the api
answers with the pending state mid-edit.

A fresh outfit has **every "All" option ticked**; "nothing selected" does not occur in practice.
`GetOutfitsInfo().situationCategories` names exactly the categories with a non-wildcard selection.

A cache entry goes stale when an edit is committed while the cache is not looking (seen in game:
Defaults + Apply, then clicking away). `OutfitCache:IsStale` compares the entry against
`situationCategories` and a stale entry is treated as unrecorded; `CommitPendingSituations` is
post-hooked so the Apply button records. Blizzard's own tab text: *"If multiple outfits are equally
valid, one will be chosen randomly."*

`Eligibility` treats an unselected or "All ..." (wildcard) category as unconstrained *before*
looking at the live value — so "All Weather" matches on Retail even though Weather is unsupported
there.

**There is no ranking.** When several outfits are eligible Blizzard picks one at random, however
many categories each constrains (Retail, 2026-09-23: Frost/Mount/Ceremony constraining 3/2/1 were
all picked across five re-picks). The pick happens only on a situation change and survives
`/reload`. So `/ts verify` scores *membership* — is `GetActiveOutfitID()` among the eligible — and
never a single predicted outfit. Do not reintroduce specificity ranking; `specificity` on an
eligible entry is a display count only.

`Verify()` returns a `verdict`, and only `"disagrees"` indicts the rules. `"disabled"` (situations
switched off), `"none-applied"` (no pick made yet) and `"not-recorded"` (cache gap) mean the run
cannot score anything; never report those as a rules failure.

`/ts scan` switches the viewed outfit, which discards unapplied edits. It refuses while
`HasPendingOutfitTransmogs()` / `HasPendingOutfitSituations()` or `InTransmogEvent()` is true,
and stops between steps if the window closes or an edit starts — Blizzard's own outfit list asks
before switching for the same reason.

## Conventions and gotchas

- **Guard every Blizzard API call** with `ns.Util.SafeCall` / `SafeCallAll` (pcall + type check).
  A missing system must no-op, not error.
- **Register events defensively** with `ns.Util.RegisterEventsSafely` — `RegisterEvent` throws on
  an unknown name, and `WEATHER_CHANGED` does not exist on Retail.
- **Wait for `Blizzard_Transmog`.** It loads on demand. `SituationPanel:TryAttach` retries on
  `ADDON_LOADED` / `PLAYER_ENTERING_WORLD` until the frame exists.
- **Never taint.** Attach with `HookScript` / `hooksecurefunc` on the frame *instance* (the XML
  `mixin=` attribute copies functions at creation, so hooking the mixin table does nothing) and
  parent child regions to Blizzard's frames; never replace or reorder `SituationFramePool` entries.
- Live values with no backing event (mount / swim / time) are polled — one ticker in `Triggers`,
  running only while a panel that asked for it is shown, and only if `Triggers:NeedsPolling()`.
- **Formatting lives in `Diagnostics`.** `Diagnostics:FormatValue(result, detail)` is the only
  rendering of a value: `"value"` for the tab row, `"compact"` for the panel (`+N`, `~`), `"full"`
  for chat. The inline row on the Situations tab shows only the value (no reason, no markers, no
  tooltip) — a decision, not an oversight. `/ts` is where detail lives.
- SavedVariables is the single global `TransmogSituationsDB`: `debug`, `panel` (position, shown),
  `lastAppliedSet[charKey]`, `outfitSituations[charKey][outfitID]`. Character-scoped data is keyed
  by `ns.Util.CharacterKey()`.
- The addon was called **BetterSituation** (slash `/bs`, SavedVariables `BetterSituationDB`) until
  just before its first release; the captures in `_refs/Situations Data.txt` still show that prefix.
- `_refs/Situations Data.txt` holds raw in-game dumps (including a French-client run that demonstrates
  the localization problem) plus the generated enum tables.
