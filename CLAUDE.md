# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Parse Partout is the addon of the owner's guild, **Parse Partout**, for **World of Warcraft:
Forever 1.60.1** (Interface `16001`), written in **Lua 5.1**. It has a single owner (Spotnick)
and uses the same stack and conventions as the sibling Forever addons, above all `..\GlassMail`
(the template for this repo's tooling, tests and CI) and `..\GuildSpy` (guild roster work). When
this file doesn't cover something, check how those handle it before you invent a new idiom.

**Status: scaffold** (2026-11-06): the addon loads, `/partout` opens an empty glass window, an
options page with the language choice, French and English strings. No guild feature yet: they
come as issues, one at a time.

The name is a pun on *passe-partout* (a master key): the emblem (`docs/images/logo.png`) is a glass
sack tied with a gold ring, a gold key hanging from it. The brand colour is the key's gold,
`|cffe8b03a`.

## Language: French first

**French is the addon's main language; English is supported.** Every player-facing string lives
in `Locale.lua`, written in French first, then in English, under the same key, with the same
format specifiers (`test_locale` checks both). Never put a player-facing literal in another file.
- `PP.L(key, ...)` returns the current language's text (`string.format` with arguments). A key
  missing in English falls back to the French text, then to the key.
- The language is `ParsePartoutDB.language`: `auto` (the default: a `frFR` client gets French,
  every other locale English), `fr` or `en`. There is **no `frCA` client locale** (Blizzard's
  UI source lists none); players in Québec run `frFR`. The French is ours to write, so it can be
  the guild's own French.
- Every slash command has a French and an English name (`aide`/`help`, `langue`/`language`,
  `erreurs`/`failures`), whatever the language. Help lines name the French one in French.
- Windows and the options page re-read their texts on every show and on a language change
  (`Window.Refresh`, `Options.Refresh`).
- The README, CHANGELOG and issue templates are French first, then English.
- Code, comments, commit messages, issues and PRs on GitHub stay in English (the owner's other
  repos do the same), unless the owner asks otherwise.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Compat.lua` → `Locale.lua` → `Glass.lua` →
`Window.lua` → `Options.lua` → `ParsePartout.lua`.

- **`Compat.lua`**: `ParsePartout.API`, the only route to client APIs that moved or may be absent:
  `Print`, `IsSecret`, `ClientBuild`, `RegisterEvents` (reports failures), `Fail(key, err)` (the
  **one** failure recorder, read by `/partout erreurs`), `SafeFrame`, `AddOnVersion`;
  `MEASURED_ON_BUILD`. A subset of GlassMail's (itself GlassChat's); lift more from there.
- **`Locale.lua`**: the strings (`STRINGS.fr`, `STRINGS.en`), `Locale.Current()`, `PP.L`.
- **`Glass.lua`**: `ParsePartout.Glass = LibStub("LibGlass-1.0"):New({ preset = "pearl" })`
  (LibGlass r11's Pearl, the Glass suite's theme), this addon's instance of the material.
  Material changes are LibGlass PRs.
- **`Window.lua`**: the main window (`ParsePartoutWindow`), glass, the emblem and the title, built
  on first open, movable, closed by Esc (`UISpecialFrames`). Features add their sections here.
- **`Options.lua`**: the Esc > Options > AddOns page, built with the porting guide's recipe.
  Choices are radio groups (`radios`), not dropdowns.
- **`ParsePartout.lua`**: bootstrap, saved settings (only what the player set is saved),
  `PP.Settings` (every setting goes through it), `/partout` (`/parsepartout`).
- **`Media\Logo.tga`**: the TOC icon and the window's emblem: 256×256, 32-bit uncompressed TGA,
  a crop of `docs/images/logo.png` without the lettering
  (`magick docs/images/logo.png -crop 900x900+177+40 +repage -resize 256x256 -alpha set -type TrueColorAlpha -compress none Media/Logo.tga`).
  A new texture needs a full client restart, not a `/reload`.

## Forever basics (shared with the siblings)

- One plain `ParsePartout.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**). Never
  commit a literal version over `@project-version@`; the deploy script writes `dev` into its copy.
- One global namespace, `ParsePartout`; files start `ParsePartout = ParsePartout or {}` and alias
  it `local PP = ParsePartout`. A `_test` seam table exposes file-local internals to tests.
- **Secret values:** test with `issecretvalue(v)` **before** any other use; never save one.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals**: always
  `API.RegisterEvents`.
- `ReloadUI()` is protected. Options use `Settings.RegisterCanvasLayoutCategory`.
- SavedVariables persist; read them at `ADDON_LOADED` / `PLAYER_LOGIN`, cope when they're absent,
  and **verify persistence only with a full client exit**.
- **IDs, never names**: never compare against or save an English display string (localized
  clients: this addon's players are French first). Names are "First Surname", no realm (Forever);
  key characters by **GUID**.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field notes.
  Treat them as fact. New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\WoW\References\Forever\api\forever-api-<version>.<build>.md` (the highest build; it
  was `1.60.1.70790` at the scaffold): the API dump. **Presence is not a contract.**
- `C:\Projects\WoW\References\Docs\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`: library rules.
- `C:\Projects\WoW\wow-ui-source` (branch `forever`): the client's own FrameXML.
- `..\GuildSpy`: the guild roster, its events and their quirks on Forever, already measured.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                  # luac -p on the TOC files, then every tests\test_*.lua, through WowTestKit at its pin (needs ..\LibGlass or $env:LIBGLASS)
pwsh tests\run.ps1 -KitDev                                          # the same against the ..\WowTestKit working copy
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua     # one test, from the repo root (once run.ps1 has fetched the kit)
pwsh Tools\deploy.ps1                                               # copy the addon (+ LibGlass) into the _forever_ AddOns folder
```

- In game: `/console scriptErrors 1` first, then `/reload`.
- Shell heredocs in this environment can collapse `\\` to `\`: write files that contain Lua
  backslash escapes or Windows paths with the Write/Edit tools.

## Testing

The test scaffolding is WowTestKit (`C:\Projects\WoW\WowTestKit`; its README is the reference)
at the commit and client build `tests\kit.pin` names. `tests\run.ps1` puts that commit in
`%LOCALAPPDATA%\WowTestKit\<sha>` and hands off to the kit's runner; CI fetches it with
`tests\fetch_kit.sh`. `tests\kit.lua`, `kit.ps1` and `fetch_kit.sh` are the kit's bootstrap
copies: never edit them here. A kit need is an issue on the kit, worked around in
`tests\wow_stubs.lua` with a `-- WowTestKit #N:` comment meanwhile. `tests\run.ps1 -KitDev`
runs against the `..\WowTestKit` working copy instead of the pin.

`tests\wow_stubs.lua` adds the client APIs the addon touches (the stub client is **French**,
`WoW.locale = "frFR"`); `tests\harness.lua` has `loadAddon`, `newChat`, `chatHas`;
`test_methods.lua` checks every `Type:Method` called exists on that widget type in the pinned
build (`Kit.checkMethods`); `test_locale.lua` checks both languages have every key.
**Mutation-test every new test**: break the behaviour, confirm it goes red.

## Workflow and releasing

- The repo is public: `github.com/Spotnick2/ParsePartout`. **Every change goes through an issue
  and a pull request**: issue → branch off `main` → PR with `Closes #N`. Never commit to `main`;
  commit or push only when asked. `luac -p` clean and tests green before committing; check the
  PR's `package-check` run after pushing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding (the `codex-consult` skill). Hand it this
  file and the porting guide. Verify its claims; push back on complexity.
- **Releasing**: `C:\Projects\WoW\References\Docs\RELEASING.md`. CurseForge project **1787925**
  (the TOC's `X-Curse-Project-ID`), built by CurseForge's packager from the tag webhook through
  `.pkgmeta`. CI's `release` job makes the GitHub Release. **No Wago project yet**: until the
  owner creates one, the TOC has no `X-Wago-ID` and a tag's `wago` job fails; create it, add the
  ID and the `WAGO_API_TOKEN` secret (RELEASING.md §0) before the first tag.
- `CHANGELOG.md`: one `## vX.Y.Z` section per release, French then English. The next release's
  section is written as work lands.

## Conventions

- **Right-size for a single maintainer.** The simplest thing that works; no speculative
  abstraction.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
