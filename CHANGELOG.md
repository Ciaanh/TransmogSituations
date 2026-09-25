# Changelog

All notable changes to TransmogSituations will be documented in this file.

## [0.2.0-beta1] - 2026-09-25

First public beta. Targets the WoW Forever beta and live Retail.

### Added

- **Situations tab values**: the transmog Situations tab shows the current value of each situation trigger (location, movement, specialization, equipment set, racial form, weather, time of day) under its category title.
- **Standalone panel**: `/ts panel` opens a movable panel with the same values, for use outside the transmog window.
- **Chat commands**: `/ts` prints every trigger's current value; `/ts list` shows the viewed outfit's options with the live value marked; `/ts dump` prints raw option ids and player state for reporting mismatches.
- **Eligible outfits** (experimental): `/ts eligible` lists the outfits that match the current situation, and `/ts verify` checks that the outfit Blizzard applied is one of them. Blizzard picks at random among eligible outfits.
- **Outfit recording**: each outfit's situations are recorded when you view it on the Situations tab; `/ts scan` records every outfit in one go.

### Known limitations

- Weather shows `n/a` on Retail, which has no API to read the current weather.
- Time of Day band boundaries are an estimate and are marked `*` in `/ts`.
- The equipped equipment set is inferred from the last set you applied, and shown with `~` once an item is swapped out.
