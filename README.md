# TransmogSituations

A World of Warcraft addon that shows the *live values* of the transmog "situation" triggers
(location, movement, specialization, equipment set, racial form, weather, time of day).
Blizzard's Situations tab lets you configure these triggers but never displays what they
currently evaluate to; TransmogSituations does.

Targets the **WoW Forever beta** and stays compatible with **live Retail**.

## Installation

Extract the zip into `World of Warcraft\<client>\Interface\AddOns\`, so that the folder
`Interface\AddOns\TransmogSituations\` contains `TransmogSituations.toc`. `<client>` is `_retail_` for
Retail, or the Forever beta's own client folder. Then restart the game or `/reload`.

## Features

- Live trigger values rendered inline on the transmog **Situations tab**, under each category title.
- A movable standalone panel with the same values, for use outside the transmog window.
- Chat commands to inspect values, options and raw ids.
- Experimental: a client-side reconstruction of which outfits are eligible right now, with a
  command that checks the outfit Blizzard actually applied is one of them (Blizzard picks among
  eligible outfits at random).

## Slash commands

`/ts` and `/transmogsituations` are equivalent.

| Command | Purpose |
| --- | --- |
| `/ts` | Current value of every situation trigger |
| `/ts panel` | Toggle the standalone panel |
| `/ts eligible` | Outfits matching the current situation (experimental) |
| `/ts verify` | Check that the outfit Blizzard applied is one of the eligible ones |
| `/ts scan` | Record every outfit's situations; transmog window must be open |
| `/ts list` | Trigger options for the viewed outfit, with the live value marked |
| `/ts dump` | Raw option ids and player state, for diagnosing mismatches |
| `/ts debug` | Toggle extra output |
| `/ts help` | Command list |

## How eligibility works

The game has no way to ask which situations an outfit is bound to, so TransmogSituations records
each outfit's assignments whenever you view it on the Situations tab. Until an outfit has been
viewed, `/ts eligible` lists it as "never viewed" rather than guessing. `/ts scan` records every
outfit in one go: open the transmog window first, and apply or undo any pending changes (the scan
refuses to run over them, because switching outfits would discard them).

## Known limitations

- **Weather on Retail** shows `n/a`: Retail has no API to read the current weather. An outfit bound
  to a specific weather can still be applied by Blizzard there, but TransmogSituations cannot match it.
- **Time of Day** band boundaries are an estimate and are marked `*` in `/ts`.
- **Equipment sets** have no "currently equipped set" API. When you swap an item out of the set you
  last applied, the value is shown with `~` as an approximation.
- **Forever beta saved data**: the beta client does not reliably keep addon data across `/reload`
  or logout. If the outfit cache or the panel position is gone after a login, run `/ts scan` again.
- Eligibility is a reconstruction of Blizzard's rules. `/ts verify` says whether it agrees with the
  outfit Blizzard applied; a disagreement is worth reporting with a `/ts dump`.

## Development

There is no test runner inside the game client. `docs/tests/run.sh` replays four real in-game
captures and drives every resolver branch under a stub environment; run it after any change under
`core/`. `docs/ROADMAP.md` tracks what has and has not been verified in game.

`.\make-release.ps1` (PowerShell 7+) stages the shipped files and zips them into `.build/`.
