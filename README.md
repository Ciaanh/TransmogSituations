# BetterSituation

A World of Warcraft addon that shows the *live values* of the transmog "situation" triggers
(location, movement, specialization, equipment set, racial form, weather, time of day).
Blizzard's Situations tab lets you configure these triggers but never displays what they
currently evaluate to; BetterSituation does.

Targets the **WoW Forever beta** and stays compatible with **live Retail**. Where a client lacks a
system (Retail has no weather API) the value is reported as unavailable rather than guessed.

## Features

- Live trigger values rendered inline on the transmog **Situations tab**, under each category title.
- A movable standalone panel with the same values, for use outside the transmog window.
- Chat commands to inspect values, options and raw ids.
- Experimental: a client-side reconstruction of which outfits are eligible right now, with a
  command that scores the prediction against the outfit Blizzard actually applied.

## Slash commands

`/bs` and `/bettersituation` are equivalent.

| Command | Purpose |
| --- | --- |
| `/bs` | Current value of every situation trigger |
| `/bs panel` | Toggle the standalone panel |
| `/bs eligible` | Outfits matching the current situation (experimental) |
| `/bs verify` | Compare the prediction against the outfit Blizzard applied |
| `/bs scan` | Record every outfit's situations; transmog window must be open |
| `/bs list` | Trigger options for the viewed outfit, with the live value marked |
| `/bs dump` | Raw option ids and player state, for diagnosing mismatches |
| `/bs debug` | Toggle extra output |
| `/bs help` | Command list |

## Development

There is no test runner inside the game client. `docs/tests/run.sh` replays two real in-game
captures and drives every resolver branch under a stub environment; run it after any change to
the trigger model. `docs/ROADMAP.md` tracks what has and has not been verified in game.

`.\make-release.ps1` stages the shipped files and zips them into `.build/`.
