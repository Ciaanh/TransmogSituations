# Replay tests

Each replay file drives a real `/bs dump` captured in game: the true `situationID` values, the
option lists (including the options a client omits) and the raw player state at capture time.
Expected values are asserted, so they fail loudly if the mapping regresses.

Both declare `Enum.TransmogSituation` empty on purpose. The documented enum disagrees with
both live clients, so a test that let the code fall back to it would prove nothing.

Run the whole suite from the repo root (needs a Lua 5.1 interpreter; override the path with
`LUA=` and `LUAC=` if it is not under `C:\Program Files (x86)\Lua\5.1`):

```sh
./docs/tests/run.sh
```

| File | Client | Notable |
| --- | --- | --- |
| `replay_retail.lua` | Retail | Dracthyr in visage, in a neighborhood while resting, no `C_Weather` |
| `replay_forever.lua` | Forever beta | Locations omits House (7) and Delves (6) — the case that rules out position-based matching |
| `replay_retail_loadouts.lua` | Retail | 2026-09-22, a mage with four saved talent loadouts and "Home" viewed: per-loadout spec options, the loadout as the value with the spec alongside, fallback when no loadout or a deleted one is selected, 4-part option keys, House assigned through the api, spec-bound vs loadout-bound outfits |
| `replay_forever_viewed.lua` | Forever beta | 2026-09-22, transmog window open with an outfit viewed: `GetOutfitSituation` answers true for every "All" while `value` is false everywhere; equipment set id 0 equipped; the all-wildcard outfit matches with specificity 0 |
| `resolvers.lua` | — | Every branch of every resolver: each instance type (including `interior` and a delve reported as `scenario`), the housing indoor/outdoor split, swimming over mounted, flying over ground, each weather type, each time band. Most of these states have never been reached in game, so this proves the mapping, not the inputs. |
| `cache_invalidation.lua` | — | Categories appearing and disappearing mid-session, driven through the real event. Dispatches events rather than calling the invalidation directly, so the wiring is under test too. |
| `attach_retry.lua` | — | The Situations tab attach keeps retrying until the frame exists. |
| `list_marking.lua` | — | `/bs list` marks the current and also-active options from the resolver's own answer. |
| `eligibility.lua` | — | The outfit cache (read through `GetOutfitSituation`, skipped while edits are pending, pruned of deleted outfits) and the matcher: wildcards satisfy an unsupported category, specificity ignores wildcards, verification detects disagreement. |
| `equipment_sets.lua` | — | Eight scenarios; takes the scenario name as its second argument. |

What this suite cannot do: prove the game supplies the inputs the stubs assume, or that the
matching rules are Blizzard's. `docs/ROADMAP.md` lists the in-game checks that settle those.
