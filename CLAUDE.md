# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

**BetterSituation** — a World of Warcraft addon targeting the **WoW Forever beta** (a Classic
client running the modern retail UI). It surfaces the *live values* of transmog "situation"
triggers, which Blizzard's own Situations tab configures but never displays.

Goals, in order:
1. Show current situation-trigger values on the transmog **Situations tab**
   (`SituationsFrame`, `TransmogWardrobeSituationsMixin`).
2. Provide `/bs` (`/bettersituation`) to read those values from chat at any time.
3. Lay the groundwork for **dynamic resolution of the eligible transmog set** from the
   current trigger values.

## Client targets

Forever beta is the **target**, but the addon must stay **compatible with live Retail**. The two
clients do not expose the same API surface, and Forever is the richer one — so anything discovered
in the Forever source must be treated as *possibly absent* until checked against the Retail source
too. Confirmed divergences:

| Symbol | Forever | Retail | Consequence |
| --- | --- | --- | --- |
| `C_Weather.GetCurrentWeather()` / `Enum.WeatherType` | yes | **no** | Weather trigger has no live value on Retail |
| `Enum.TransmogSituationTrigger.SettingsUpdate` (11) | yes | **no** (enum stops at 10) | never hardcode the enum's max value |

The situation APIs the addon actually depends on — `GetUISituationCategoriesAndOptions`,
`GetOutfitSituation`, `GetOutfitSituationsEnabled`, `GetActiveOutfitID` — exist on both.

Practical rules:
- Resolve enum members defensively. `Enum.WeatherType.Clear` at file scope errors on load when the
  enum is missing; build such lookup tables lazily or guard the whole table behind an
  `if Enum.WeatherType then` check. (`core/Diagnostics.lua`'s `WEATHER_TYPE_NAMES` currently does
  this at file scope and needs fixing.)
- A missing system means the value is reported as unavailable, never an error and never a hidden
  wrong default.
- Drive the UI off whatever `GetUISituationCategoriesAndOptions()` actually returns on the running
  client rather than a compile-time list of triggers, which handles both client differences and the
  conditional categories below.

## Layout

```
BetterSituation.toc          # load order + Interface versions (120100 retail, 16001 classic)
BetterSituation.lua          # addon namespace, SavedVariables, slash commands, ADDON_LOADED bootstrap
core/Diagnostics.lua         # environment snapshot + situation category/option snapshot, chat output
core/SituationPanel.lua      # overlay attached to Blizzard's Situations tab
make-release.ps1             # stages + zips a release into .build/
_refs/                       # local-only research notes (gitignored, never shipped)
Situations Data.txt          # captured in-game output + enum dumps (see Domain reference)
```

Load order is declared in `BetterSituation.toc`: `core/` files first, then `BetterSituation.lua`.
Adding a new file means adding it to the toc **and** to `$includes` in `make-release.ps1`.

Module pattern: every file does `local _, ns = ...`, assigns a table onto `ns`
(`ns.Diagnostics`, `ns.SituationPanel`), and exposes `Module:Init(api)`. `BetterSituation.lua`
calls each `Init` from its `ADDON_LOADED` handler and passes the addon table, which provides
`api:Print(msg)` (prefixed chat output). Use `api:Print`, not bare `print` / `DEFAULT_CHAT_FRAME`.

## Build / release

```powershell
.\make-release.ps1            # reads "## Version" from the toc -> .build/BetterSituation-v<version>.zip
```

There is no test suite and no linter; verification is in-game. Reload with `/reload`, and enable
`/console scriptErrors 1` when touching UI code. `.vscode/settings.json` configures the Lua
language server for Lua 5.1 with the ketho WoW API annotations — new WoW globals may need adding
to `Lua.diagnostics.globals` to silence false positives.

## Blizzard references

Two read-only UI source trees live outside the repo. Check a symbol in **both** before relying on it:

- Forever (target): `G:\Dev\WoW\_Workspace\Blizzard_UI_refs\Forever\BlizzardInterfaceCode\`
- Retail (compatibility floor): `G:\Dev\WoW\_Workspace\Blizzard_UI_refs\Retail\BlizzardInterfaceCode\`

Most relevant files, at the same relative paths in each tree:
- `Interface/AddOns/Blizzard_Transmog/Blizzard_Transmog.lua` — `TransmogWardrobeSituationsMixin`
  (~line 3030): `OnLoad` / `OnShow` / `OnHide` / `Init` / `Refresh`, `SituationFramePool`, and the
  `VIEWED_TRANSMOG_OUTFIT_SITUATIONS_CHANGED` event it listens to.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/TransmogOutfitInfoDocumentation.lua` —
  authoritative signatures for `C_TransmogOutfitInfo.*`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/TransmogOutfitConstantsDocumentation.lua` —
  the `TransmogSituation*` enums.

`_refs/AutomationConditions.lua` is a Total RP 3 file kept purely as a *pattern* reference for
condition evaluation. It is not loaded at runtime and must not be edited or integrated.

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
namespace and verify in game before assuming an enum mapping.

`Enum.TransmogSituationTrigger`: `None=0, Manual=1, TransmogUpdate=2, Location=3, Movement=4,
Specialization=5, EquipmentSet=6, Forms=7, EventOutfit=8, Weather=9, TimeOfDay=10, SettingsUpdate=11`
(`SettingsUpdate` is Forever-only — see Client targets.)

`Enum.TransmogSituation` (the per-category options):
`AllSpecs=0, Spec=1, AllLocations=2, LocationRested=3, LocationHouse=4, LocationCharacterSelect=5,
LocationWorld=6, LocationDelves=7, LocationDungeons=8, LocationRaids=9, LocationArenas=10,
LocationBattlegrounds=11, AllMovement=12, MovementUnmounted=13, MovementSwimming=14,
MovementGroundMount=15, MovementFlyingMount=16, AllEquipmentSets=17, EquipmentSets=18,
AllRacialForms=19, FormNative=20, FormNonNative=21, AllWeather=22, WeatherClear=23, WeatherRain=24,
WeatherSnow=25, WeatherSand=26, AllTime=27, TimeMorning=28, TimeDay=29, TimeEvening=30, TimeNight=31`

Categories are conditionally present — code must not assume a fixed list:
- **Equipment Sets** only if the player has at least one equipment set.
- **Racial Forms** only for races with multiple forms (Worgen, Dracthyr).
- **Specializations** lists only unlocked specs, so nothing before level 10.

`Situations Data.txt` holds raw in-game dumps (including a French-client run that demonstrates the
localization problem) plus the generated enum tables.

## Conventions and gotchas

- **Guard every Blizzard API call.** The addon ships for two Interface versions across two clients
  (see Client targets), and `C_Weather` / `C_TransmogOutfitInfo` / `C_DelvesUI` /
  `Blizzard_Transmog` may be absent. `Diagnostics.lua`'s `SafeCall(fn, ...)` wrapper (pcall + type
  check) is the house style for calls; enum *members* need their own nil check, since `SafeCall`
  cannot protect a file-scope table index. A missing system must no-op, not error.
- **Wait for `Blizzard_Transmog`.** It loads on demand. `SituationPanel:Init` checks
  `C_AddOns.IsAddOnLoaded("Blizzard_Transmog")` and otherwise waits on `ADDON_LOADED` for it.
- **Never taint.** Attach with `HookScript` / `hooksecurefunc` and parented child frames; never
  replace or reorder Blizzard's own frames, scripts, or `SituationFramePool` entries.
- Live values with no backing event (mount / swim state) are polled — `SituationPanel` runs a
  `C_Timer.NewTicker(REFRESH_INTERVAL)` started on the tab's `OnShow` and cancelled on `OnHide`.
  Don't leave tickers running while the tab is hidden.
- Formatting helpers are shared, not duplicated: `SituationPanel` calls
  `ns.Diagnostics.FormatWeather` and `ns.Diagnostics:CollectEnvironmentSnapshot`. Keep new
  derivations in `Diagnostics.lua` so chat output and the panel can never disagree.
- SavedVariables is the single global `BetterSituationDB` (currently just `debug`), defaults
  applied in `EnsureDefaults()`.

## Current state and roadmap

Implemented: `/bs` environment snapshot, `/bs list` category + option dump, `/bs situations` raw
dump, `/bs help`, and a "Current Conditions" overlay anchored above the Situations tab's Apply
button.

Open work:
1. **Move the overlay.** The fixed text block conflicts with the situation list's size. It should
   become a single line under each situation's label in the list instead of one detached block.
2. **Cover all trigger types** in current-value detection — `Diagnostics` derives Location /
   Movement / Spec / Weather / Forms / Time of Day and does not properly handle Equipment Sets or
   the non-environmental triggers.
3. **Add a panel command** so users can see current trigger values in a small standalone frame
   instead of chat.
4. **Plan dynamic eligible-set resolution** — matching outfits to live conditions. Per the earlier
   finding in `_refs/plan-envSnapshotSituationPanel.prompt.md`, Blizzard exposes no bulk
   outfit-matching API, so this has to be reconstructed client-side from
   `GetUISituationCategoriesAndOptions` + `GetOutfitsInfo`.

Leftover debug `print()` loops still exist in `SituationPanel:Init` and the `situations` branch of
`HandleSlashCommand` — remove them rather than extending them when touching those functions.
