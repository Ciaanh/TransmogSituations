---
paths:
  - "**/*.lua"
  - "**/*.toc"
  - "**/*.xml"
---

# WoW addon rules (all of Ciaanh's addons)

Vendored from `Ciaanh/wow-dev` (`repo-slice/`): edit it there and sync, not here. The repo's own
CLAUDE.md wins where it is more specific.

## Language and files

- **Lua 5.1** (the CI runs `luac5.1 -p`). No `goto`, `//`, bitwise operators (use `bit.band` &
  co.), `<const>`, integer division or `utf8`. No `require`, `io`, `os`, `debug`, `loadfile` in
  addon code. `#t` on a table with holes is undefined.
- Every file starts with `local addonName, ns = ...` (or `local _, ns = ...`) and adds itself to
  `ns`. The only globals are the toc's `## SavedVariables*`, `SLASH_*` and `BINDING_*`. Frames
  get a name only when Blizzard needs one, prefixed with the addon name.
- **Load order is the toc's.** A module that captures another's functions at file scope must load
  after it. A new file goes into the toc **and** under a folder `make-release.ps1` ships
  (`$includes`). A new *top-level* file or folder goes into `$includes` (ships) or into
  `.pkgmeta`'s `ignore` (does not); the two lists are exact complements.
- Player-facing strings go through the locale table (`ns.L`); debug / probe output may stay
  English.
- `/reload` picks up Lua changes; a changed toc needs a full client restart.

## Clients

- The toc's `## Interface:` lists every targeted client. Before relying on any Blizzard symbol
  (API, event, enum, mixin, template, atlas), check it **in every targeted client**:
  `/wow-dev:ref <Symbol>` locally (the plugin), else the repo CLAUDE.md's notes, else Gethe's
  `wow-ui-source` (Retail only) — and write "to check locally" for Forever facts you could not
  verify.
- Forever (`16001`, a Classic client on the 12.x Mainline UI) and Retail both report
  `WOW_PROJECT_ID == 1`: tell them apart by interface version (`select(4, GetBuildInfo())`).
- An optional system is probed **once** at load (the repo's capability module) and asked
  afterwards; call sites do not re-test globals. A missing system is reported as *unsupported*,
  never an error or a silent wrong default.
- Never index `Enum.X.Y` at file scope without a nil check: a missing enum errors on load and no
  `pcall` can catch a file-scope index. Never hardcode an enum's max value.

## Secret values (12.x) and taint

- A value read from the game may be secret (combat, instances, identity restrictions). Pass every
  game value through the repo's plain-ing helper (`Util.Plain` / `Util.Flatten` where they exist)
  before comparing, formatting, printing, storing or using it as a key. Test the **type**, not the
  value. `issecretvalue` / `canaccesstable` may be missing on a client: check they exist.
- Never key a table by GUID or unit name (secret for enemy NPCs under restrictions); key by unit
  token. Anchoring to a FontString with secret text makes the anchored frame's geometry secret.
- Hook Blizzard code with `hooksecurefunc` / `:HookScript`; never replace a Blizzard function or
  a method of a secure frame. No `loadstring` / `setfenv` on code.
- Protected work (secure frames' `Show`/`Hide`/`SetPoint`/`SetAttribute`, secure templates)
  only out of combat: check `InCombatLockdown()` and queue to `PLAYER_REGEN_ENABLED`.

## Events and performance

- One event listener per model (the repo's controller or trigger module); other modules
  subscribe to it. `RegisterUnitEvent` for unit events. Register events through the repo's safe
  helper (an unknown event raises on some clients).
- `OnUpdate` only while there is work (a queue that drains, then the script is removed);
  throttle on accumulated `elapsed`. No table allocation per frame: reuse with `wipe`.
- `C_Timer.After` cannot be cancelled; use `C_Timer.NewTimer` when it may need to be.

## Settings

- The Blizzard Settings API (`Settings.RegisterVerticalLayoutCategory`,
  `Settings.RegisterAddOnSetting`, `Settings.RegisterAddOnCategory`); the workspace digest is
  `Blizzard_UI_refs/Blizzard_Settings_API_Guide.md`. Every setting goes through the repo's config
  module (validation + notification); the panel, slash commands and tests all use it.

## Verify

- `./tests/run.sh` after any change to addon Lua (the Stop hook runs it for you when you edited
  Lua). A new Blizzard API call needs its stub in `tests/harness.lua`, once.
- The suite proves the mapping given an input, not that the game supplies it. Anything only the
  game can confirm goes on the in-game checklist for the user, and the result into the repo
  CLAUDE.md's "Confirmed in game" section. After the user's `/reload` or logout,
  `/wow-dev:errors` reads what BugSack caught.
