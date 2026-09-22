# Tests

A Lua 5.1 suite that loads the addon exactly as the client does — the files `BetterSituation.toc`
lists, in its order, then `ADDON_LOADED` through the real bootstrap — against stubbed WoW apis.

Run it from the repo root (override the interpreter with `LUA=` and `LUAC=` if it is not under
`C:\Program Files (x86)\Lua\5.1`):

```sh
./docs/tests/run.sh
```

## The harness

`harness.lua` holds every stub, the loader and `Check`. A test sets state on the harness and then
loads the addon:

```lua
local H = dofile((arg[1] or ".") .. "/docs/tests/harness.lua")
H.categories = H.RetailTree()        -- or H.ForeverTree(), or built with H.Category / H.Opt
H.W.resting, H.W.mounted = true, true -- world state the stubbed game functions read
local ns = H.Load()
H.Check("Locations", ns.Triggers:Resolve(3).optionName, "Rest Area")
H.Done()
```

- **State, not redefinition.** `IsResting`, `C_Housing`, `GetOutfitSituation` and the rest read
  fields on `H` (`H.W`, `H.categories`, `H.outfits`, `H.assigned`, `H.sets`, ...), so a test
  changes the world by assigning, and a new api call added to the addon needs a stub in one place.
- **Frames are real enough.** `CreateFrame` returns frames that register events and run scripts;
  `H.Fire(event, ...)` delivers an event to every registered frame, so the event wiring is under
  test, not just the handlers. `Show`/`Hide` run `OnShow`/`OnHide` and their hooks.
- **`hooksecurefunc` is a real post-hook**, and raises on a missing method as the client does.
- **Time only passes when a test says so.** `H.RunTickers()` advances `C_Timer` tickers; `After`
  runs at once.
- `Enum.TransmogSituation` is empty on purpose: the documented enum disagrees with both live
  clients, so a test that let the code fall back to it would prove nothing. Retail has no
  `C_Weather`; `H.EnableWeather()` adds the Forever one.

## Files

| File | Covers |
| --- | --- |
| `replay_retail.lua` | Retail capture: Dracthyr in visage, outdoors in a neighborhood while resting, no `C_Weather`; inside the house (`interior`) House is the value with Rest Area alongside |
| `replay_retail_loadouts.lua` | Retail capture, a mage with four saved talent loadouts and "Home" viewed: per-loadout spec options, the loadout as the value with the spec alongside, fallbacks, 4-part option keys, House assigned through the api, spec-bound vs loadout-bound outfits |
| `replay_forever.lua` | Forever capture: Locations omits House (7) and Delves (6) — the case that rules out position-based matching |
| `replay_forever_viewed.lua` | Forever capture with an outfit viewed: `GetOutfitSituation` true for every "All" while `value` is false everywhere; equipment set id 0 equipped; the all-wildcard outfit matches |
| `resolvers.lua` | Every branch of every resolver: each instance type (including `interior` and a delve reported as `scenario`), swimming over mounted, flying over ground, the specless character, each weather type, each time band |
| `equipment_sets.lua` | Eight ways the client reports sets: exact, ambiguous tie, tie broken by the applied set or the spec's set, the last-applied fallback, unknown, an id with no option |
| `cache_invalidation.lua` | Categories appearing and disappearing mid-session, driven through the real events; an empty answer is never cached |
| `attach_retry.lua` | The Situations tab attach keeps retrying until the frame exists |
| `list_marking.lua` | `/bs list` marks the current and also-active options from the resolver's own answer |
| `panels.lua` | Both panels: the tab row shows the value alone and the panel the compact form; both follow a dismount and the poll live while shown, stop when hidden, and the panel remembers being closed by Escape |
| `eligibility.lua` | The outfit cache (read through the api, skipped while pending, recorded on Apply, stale entries, scan, pruning) and the matcher: wildcards, unranked eligibility, verify by membership |

What this suite cannot do: prove the game supplies the inputs the stubs assume, or that the
matching rules are Blizzard's. `docs/ROADMAP.md` lists the in-game checks that settle those.
