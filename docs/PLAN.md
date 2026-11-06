# Plan: guild invite requests, relayed to whoever can invite (#9)

The approved plan, kept as it was reviewed. Measured results go in `docs/FOREVER-PROBE.md`;
where they contradict an assumption here, they win and this file is updated in the same PR.

## Context

First feature of Parse Partout (repo `C:\Projects\WoW\ParsePartout`; rules in its CLAUDE.md). The
need (r/wowforever: "whisper a word to get a guild invite" addons are broken on Forever): someone
outside the guild whispers a member "peux-tu m'inviter dans la guilde ?", and that member usually
can't invite. **Owner's assumption: every guild member, officers included, runs Parse Partout.**
So the member's addon turns the request into a guild addon message, and the addon of every online
member who *can* invite shows a dialog: who asks, basic details, their words, who relayed it. One
of them invites; the others' dialogs close; once the player joins, the request is closed
everywhere, including for an officer who logs in later. A member can also file a request by hand
("Demander une invitation de guilde", shaped like Blizzard's add-member box) and is told whether
anyone who can invite answered. After a join, inviters get a chat line with [Bienvenue] (their own
welcome whisper) and [Notes] (a note editor). French first, English supported.

Reviewed adversarially by Codex (gpt-6-astra, high), five rounds to consensus: rounds 1-4
"approve with changes" (all taken: request generations and terminal records, guild-scoped storage,
honest availability wording, two-level detection, isolated dev mode, GUID identity without name
promotion, sync limits and dominance, best-effort corrections), round 5 **APPROVE**, no defect.

### What the design rests on (build 1.60.1.70790 unless noted)
- **Restricted calls, assumed click-only (unmeasured by us).** A guild addon in production on
  Forever (2026-11-05) calls `C_GuildInfo.Invite` and `SendChatMessage` only from a player's click
  (invites, whispers, guild actions). EGI 0.2.5 (beta, ARR) claims invites fail
  even from clicks. Blizzard's annotations: `Invite` has `SecretArguments = AllowedWhenUntainted`,
  no `HasRestrictions` (GuildInfoDocumentation.lua:170); `SendChatMessage` has `HasRestrictions` +
  `RestrictedForMacroChatMessages` (ChatInfoDocumentation.lua:564); `SetNote` and `GetInfoText`
  have `HasRestrictions` (:389, :107). So: every restricted call runs synchronously inside our own
  button/link click, and the invite has a manual fallback (copy `/ginvite First Surname`).
- `CanGuildInvite()` is Blizzard's own gate (CommunitiesFrame.lua:1533); read on each use, at the
  click again; unreadable = unknown = not an inviter. It doesn't promise success (guild full).
- Addon messages on GUILD work and echo to the sender as "First Surname" (porting guide :2511-2527,
  measured on 70205), and reach every sub-realm (a production Forever guild addon, 2026-11-05). Result enum: 0 ok, 3 throttled, 10 not in guild, 11 lockdown
  (ChatConstantsDocumentation.lua:147). 255 bytes max; a 256-byte send *succeeds and truncates*
  (PG :2535): we count encoded bytes ourselves.
- Chat payloads (WHISPER/GUILD/SYSTEM) are `SecretInChatMessagingLockdown`; plain in the open world
  (PG :2093, measured 70205-era). Every consumed argument (text, sender, GUID, system text, addon
  fields) is `issecretvalue`-checked before use. GUID is whisper arg 12.
  `GetPlayerInfoByGUID` may return nothing (PlayerScriptDocumentation.lua:837): details optional.
- Names: "First Surname", no realm (verbatim from the payload, never rebuilt); not globally unique
  across connected realms (PG :2514), but an invite is by name anyway.
- `ERR_GUILD_JOIN_S` measured enUS 70338 (GuildSpy FOREVER-PROBE :137-149); invite / decline /
  already-guilded / not-found results **unmeasured**, possibly not CHAT_MSG_SYSTEM (UI_INFO_MESSAGE /
  UI_ERROR_MESSAGE too).
- **No StaticPopup** (shared-pool taint broke Quit, AltStable forever-api-notes :1827); **no
  Blizzard menu entry** (`Menu.ModifyMenu` taint, GlassPearls #82). `addon:` chat links reach
  `EventRegistry:RegisterCallback("SetItemRef", …)` (PG :2083); `CopyToClipboard` is forbidden →
  selected EditBox + Ctrl+C.
- Comm: **not LibAccountSync** (own accounts only, its README :3-5). GUILD addon messages in
  GuildSpy's shape (pure core with injected send/clock/timer; Wire escaping; tests with several
  cores on a fake network, GuildSpy `tests/test_guildsync.lua`), 1.2 s/send pacing as used in production.
- References (`C:\Projects\WoW\References\Addons\Guild\`): AutoGuildInvite 4.6.0, EasyGuildInvite
  0.2.5 (All Rights Reserved) and WOWForeverGuildInviter 1.1.0 (no licence): behaviour only, never
  copied.

## Design

### Roles and trust
- **Inviter**: `CanGuildInvite()` true on that client. Answers `Q`, gets prompts.
- Everyone else relays and files requests.
- **Guild-trust model (documented):** a guild member could forge any message. We authenticate the
  transport sender only (roster member, not ourselves) and rate-limit per transport sender; the
  actor a packet names is kept as stated, historical and unverified (see Attribution); every
  decision is recoverable: a refusal closes the request, a member can file a fresh one. No crypto,
  no election.

### Request identity, generations, terminal state (`Requests.lua`, pure)
- **Who** (`rid`): `g:<GUID>` when known (a whisper's arg 12), else `n:<name key>` (trimmed,
  case-folded "first surname") for a manual request. The verbatim name is always kept as the invite
  target. Two different known GUIDs are **never** merged, even with the same name (connected-realm
  collisions, PG :2514). **Name-only requests are never promoted** to a GUID in v1. Duplicates are
  prevented at the source instead: the request window refuses a name whose key matches any open
  request (and shows that one), and a whisper isn't relayed when an open request has its name key.
  Closing a GUID request also closes the open **name-only** requests with its name key (they can't
  be told apart), never another GUID's request; the closure is recorded under each closed `rid`.
- A **generation** is one open request: `{ rid, gen, name, guid?, createdAt (server time,
  immutable), origin (its creator's name, as stated), text, via, class/race/level tokens? }`,
  `gen = createdAt .. ":" .. origin key`. Two open generations of one `rid` merge into the earliest
  by `(createdAt, origin)`; one origin is kept (no relayer aliases in v1).
- **Expiry**: fixed 2 h from `createdAt`, decided locally (no `X expired` on the wire). Timestamps
  must be integers, ≤ 120 s in the future; receipt, merge, sync or claim never change them. Local
  waits (jitter, windows, pacing) use the session clock (`GetTime`), never server time.
- **Terminal record** per `rid`: `{ closedUpTo, reason = joined|declined, actor, at }` where
  `closedUpTo = max(at, createdAt of every generation it closed)`, so an accepted future-dated
  generation is covered. An `R` with `createdAt <= closedUpTo` is stale; a deliberate new request
  (`createdAt > closedUpTo`) is a new generation. Kept 2 h + 120 s from `closedUpTo` (replay never
  refreshes it). 100 is a cleanup target, not a cap: records past their age are removed first, and
  an unexpired record is never evicted (creation limits keep the count small).
- **Membership** is checked when receiving, restoring, showing and clicking a request. A GUID
  request is reconciled against **that GUID** in the ready roster; a name-only request against
  `C_GuildInfo.MemberExistsByName`. A member → closed `joined` locally. A join line (name only) or a
  remote `X joined` triggers that reconciliation; it never by itself closes another GUID's request
  of the same name (the prompt is hidden meanwhile).
- **Claims** `C rid gen attemptAt` are best-effort suppression, not a lock: expiring
  `attemptAt + 120 s`, never refreshed by replay, ignored when `gen` isn't the current open
  generation (a claim on a refused generation never suppresses a new one); synced to late inviters
  while unexpired. Two officers clicking at once may both invite: accepted, the server decides.
- **Storage** `ParsePartoutDB.guilds[guildKey] = { open = {...}, closed = {...} }`, guildKey =
  guild name + the guild's realm (GuildSpy `Compat.lua:150`). Everything (timers, queued packets,
  syncs, link records) is bound to the guild key and rechecked before sending. Cap 30 open.
- **Attribution**: the transport sender is authenticated (roster member, not us) and rate-limited;
  the actor fields (`origin` of an `R`, `actor` of a `C`/`X`) are carried unchanged when forwarded
  and shown as stated ("refusée par Carl"), never replaced by the forwarder and never presented as
  verified (guild-trust model).

### Protocol (`Wire.lua` + `Comm.lua`)
Prefix `ParsePartout`, GUILD only, `PP1` magic+version, tab-separated `%`-escaped fields, class and
race as tokens; every field bounded; text truncated on a UTF-8 boundary to fit the **encoded**
255-byte budget; a packet whose metadata alone exceeds it is never sent. Received text is
escaped (`|` → `||`) at display. Receive limits per transport sender: 40 `R` / 10 min (a full
30-record sync plus ordinary traffic fits), 80 packets / min. Creation is limited separately, at
the source: 5 manual requests / 10 min per member, one relay per requester per 10 min.
- `Q qid` who can invite? → each inviter `A qid` after a 0-1.5 s jitter, once per qid; the asker
  counts **distinct transport senders** per qid.
- `R` a generation. `C rid gen attemptAt actor`. `X rid closedUpTo reason actor at`.
  `W memberKey` (welcome sent; see After a join).
- `S sid`: an inviter, once its roster is ready (login, or `CanGuildInvite` turning true), asks for
  state; each holder waits 2-6 s, then feeds its store **one record at a time** into the pump: open
  `R`s, unexpired `C`s **and retained terminal records (`X`)**, each revalidated at send time.
  Suppression by dominance only: a holder skips a record when it has heard, since the `S`, a packet
  that makes it redundant: the same `R` generation (not merely a later one: a later `R` never
  suppresses the earlier canonical one), the same or a dominating `X` (higher `closedUpTo`), the
  same `C` (gen, attemptAt). A `C` never suppresses the `R` it targets. If no sync record arrived
  30 s after the `S`, the inviter sends one more `S` (once), whatever its roster state was.
- **Stale-`R` correction**: a holder of a terminal record that hears an `R` it covers schedules its
  `X` after a 1-5 s jitter and cancels it if an equal or dominating `X` is heard first: best-effort
  duplicate suppression (two holders can still both send; harmless). Forwarded `X`s keep their
  original `closedUpTo`, actor, at.
- **Send pump**: one packet / 1.2 s; priority `X` > `C` > `A` > `R` > `Q`/`S`; queue ≤ 20 with
  coalescing (one pending packet per (type, rid)), stale `R` dropped when its rid closes; result 3/11
  → retry after a wait, held at most 10 min (`Q`/`A` at most 10 s); 10 → stop (not in a guild);
  anything else → dropped and recorded in `/partout erreurs`.
- Local actions (create, claim, close) apply immediately; our own echo is ignored.

### Detection (`Detect.lua`, pure, FR+EN always on)
`CHAT_MSG_WHISPER` only. Skipped: secret args, sender in the guild, own characters, handled < 10 min
ago, an open request for that rid. Normalization: lower case incl. upper-case accented letters
(byte-wise Lua 5.1 tables for é É è … ç), typographic apostrophes, links/colour codes stripped,
punctuation → spaces, word boundaries. Two levels:
- **Relay automatically**: guild shorthand as a whole word (`ginv`, `g inv`, `ginvite`, `inv g`,
  `inv guild(e)`), or a self-directed request with guild context: "peux-tu m'inviter dans la
  guilde", "je peux rejoindre votre/ta guilde", "can I join your guild", "guild invite please"…
  (an explicit phrase list with conjugations: inviter/invites/invite-moi/m'inviter,
  rejoindre/rejoins/join, entrer).
- **Ask first** (a local glass toast "Transmettre la demande de Bob ? [Transmettre] [Ignorer]"):
  recruitment questions ("tu recrutes ?", "vous recrutez", "are you recruiting"), third-party ("invite
  mon ami dans la guilde"), anything else with a guild word + invite/join word.
- Never: bare `inv`/`invite` (party), negations ("je ne veux pas…"), the recipient being recruited.
  The guild's full normalized name counts as the guild word; a lone `g` never does.
Corpus tests: each example above, FR and EN, positives and negatives.

### Relay
Auto level: `R` sent at once, plus a `Q`; local chat line: "Demande de **Bob Smith** transmise."
then, when the answer window (5 s after the `Q` actually left, the local client counted if it can
invite) closes: "N membres pouvant inviter ont répondu." / "Aucun membre pouvant inviter n'a
répondu pour l'instant : la demande reste ouverte 2 h." The line has a `[Répondre à Bob]` link: a
canned whisper to the requester from that click, honest about what we know: "Ta demande a été
transmise ; un membre pouvant inviter a répondu, elle est en attente." or "Ta demande a été
transmise ; personne pouvant inviter n'a encore répondu." (chosen by the count).

### Request window ("Demander une invitation de guilde")
From the main window: a name box (Blizzard's add-member shape) + an optional note, Envoyer. Same
`R` + `Q` flow and wording; refuses a name already in the guild or already open (shows that one).

### Inviter prompt (`Prompt.lua`, own glass frame)
Queue (one shown, "1/3"), above the chat frame, no focus steal. Hidden when combat starts, held
until combat ends (Compat NoteCombat/InCombat), every request revalidated before showing again;
nothing is ever executed on `PLAYER_REGEN_ENABLED`. Shows name (class colour), level/race/class
when known, their words (escaped), "relayé par Alice" / "demandé par Alice : note", age, a claim
("Carl invite… il y a 30 s") when one is live. Buttons:
- **Inviter**: rechecks guild, `CanGuildInvite`, membership and terminal state; records the pending
  attempt; `C_GuildInfo.Invite(name)` synchronously; sends `C`. Result watcher (correlated to this
  attempt, late results accepted): `ERR_GUILD_INVITE_S` for the name → **envoyée** (not joined);
  `ADDON_ACTION_BLOCKED/FORBIDDEN` for ParsePartout naming the invite function during the attempt →
  **bloquée**; nothing in 5 s → **non confirmée**. Bloquée/non confirmée offer the copy box
  (`/ginvite Bob Smith` selected, "Ctrl+C puis colle dans la discussion"). Never retried
  automatically. Already-guilded / not-found / declined results (once measured) are said; declined
  → `X declined`.
- **Prévenir** (separate click, v1): the pre-invite whisper "Alice m'a demandé de t'inviter dans la
  guilde Parse Partout" (text in settings). Merged into Inviter only after the officer measurement
  shows whisper + invite in one click both work.
- **Plus tard** (hide 10 min, local) · **Refuser** (`X declined`, closes everywhere).
The main window shows the open requests (reopen the prompt).

### After a join (inviters)
`ERR_GUILD_JOIN_S` (pattern from the localized global, GuildSpy Patterns approach, links stripped)
→ the matching requests are reconciled under the Membership rules above (only those established as
members close), and for inviters a line "Bob Smith a rejoint la guilde :
[Bienvenue] [Notes]". Links carry an opaque **local** id (`addon:ParsePartout:j:<n>`) into a small
post-join record `{ n, name, memberKey, at }` (kept 1 h) independent of any request; the callback
rechecks guild, permission and state, never trusts link text. On the wire the member is
`memberKey` = the new member's **GUID**, resolved from the ready roster (at the join line, else
again at the click); there is no name fallback on the wire.
- `[Bienvenue]`: one configured line (setting; shown only when set), `SendChatMessage` WHISPER from
  the click, then `W memberKey` only when the GUID is resolved (otherwise the whisper goes, no `W`).
  Advisory, remembered 1 h ("déjà envoyé par Carl" on the others; near-simultaneous clicks can
  still double: accepted).
- `[Notes]`: our glass editor: public note (if `CanEditPublicNote`), officer note (read if
  `CanViewOfficerNote`, write if `C_GuildInfo.CanEditOfficerNote`), GUID from a ready roster,
  31-character limit (GameDialogDefs.lua:1938), only changed fields saved, the roster re-read before
  saving (a concurrent edit is shown, not overwritten). `C_GuildInfo.SetNote` from the click.
  Officer notes never go on the wire.

### Settings (Options + `/partout`)
Relay automatically (on) / always ask first; pre-invite whisper text; welcome line. All FR+EN.
Cut from v1: TTL choice, relay counts, whisperer quick-pick, sound, multi-line welcome, guild-info
import (later issue, after `GetInfoText` is measured).

### Simulation (the owner can't invite) — isolated from the real guild
- `Tools/PartoutProbe/` (ForeverProbe module `/fp partout`, never packaged): measurement steps that
  call the raw APIs itself, independent of the addon's internals.
- **Dev mode** (dev builds only, `PP.IsDev()`; **switched only across a `/reload`**: the flag is
  saved and read at load, so no pending send, timer or clickable record crosses modes): a test
  prefix `ParsePartoutT`, test storage `ParsePartoutDB.dev`, and this client acts as an inviter
  with **dry-run** actions (invite / whispers / SetNote logged to `/fp`, not called). Production
  validation (roster sender check) is never weakened: fake peers' packets enter through the core's
  test seam, not the network. Real delivery (whispers, links) is measured by the probe's own steps,
  never through dry-run clicks.
- Owner procedures (two accounts in the guild): the alt's whisper is **rejected** (a member: the
  negative test); a positive whisper needs a non-member (an unguilded character of the 2nd
  account, or a friend); `Q/A/R/C/X` between the two accounts in dev mode on the test prefix; a
  click-sent whisper and a link-click whisper to "First Surname"; the join line when someone joins.
- **Officer procedure (required before a release that relies on it)**: a real officer, a consenting
  non-member, the owner relaying. Invite from the real Inviter button (received?), then Prévenir +
  Inviter in one click if we want to merge them; capture the globals, events, payloads and timing
  for sent / accepted / declined / already-guilded / not-found; the `/ginvite` fallback; the request
  closing on both clients (incl. one that missed the join and restores old state); notes edited and
  read back through our editor with each permission; the welcome link; combat hold/resume; a full
  client exit for SavedVariables. Results with the build in `docs/FOREVER-PROBE.md`.

## Delivery: issue #9 "Guild invite requests" (umbrella), 4 PRs, `Part of #9` until the last

The transport (PR 2) sits on the guild-sync base of #3 (one prefix, the hello, ChatThrottleLib
behind a one-at-a-time queue, the one-answerer rule): built first or with it, never twice.
1. **Facts + probe**: `Tools/PartoutProbe` (+ deploy `-Probe`/`-ProbeOnly`, harness
   `loadForeverProbe`, CI `FOREVERPROBE_OPTIONAL`), owner and officer procedures,
   `docs/FOREVER-PROBE.md` (each fact with its build), `docs/PLAN.md` (this plan), references added.
2. **Core + transport**: `Detect.lua`, `Wire.lua`, `Requests.lua`, `Comm.lua`, `Patterns.lua`,
   guild-scoped storage; fake-network tests.
3. **Request flow**: relay, request window, prompt, invite action + watcher + copy box, combat,
   dev mode, settings.
4. **After join + release prep**: welcome, notes editor, CTA line; README/CHANGELOG (FR+EN); the
   officer procedure run before tagging.

## Files (ParsePartout)
New: `Detect.lua`, `Wire.lua`, `Requests.lua`, `Comm.lua`, `Patterns.lua`, `Invite.lua`,
`Prompt.lua`, `RequestWindow.lua`, `AfterJoin.lua` (line, welcome, notes editor), `Dev.lua`,
`Tools/PartoutProbe/{PartoutProbe.toc,PartoutProbe.lua}`, `docs/FOREVER-PROBE.md`, `docs/PLAN.md`,
tests. Changed: `Locale.lua`, `Window.lua` (requests list, request button), `Options.lua`,
`ParsePartout.lua`, `Compat.lua` (NoteCombat/InCombat from GlassMail, PlayerFullName, GuildKey from
GuildSpy), TOC, `tests/wow_stubs.lua` (GuildSpy's roster stub, SendAddonMessage with GUILD echo
and result codes, SendChatMessage / `C_GuildInfo.Invite` / `SetNote` recorders), `Tools/deploy.ps1`,
CI (`FOREVERPROBE_OPTIONAL`), CLAUDE.md (layout, trust model).

## Verification
- `pwsh tests\run.ps1`, mutation-tested: detection corpus (FR/EN, both levels, negatives); wire
  round-trip, escaping, 255-byte budget with multibyte text; fake network of 3-5 cores: relay →
  only inviters prompted; claim suppression, expiry, and a claim on a refused generation ignored by
  the next one; join closes everywhere; reordered `X`/`R`; stale `R` replay corrected (a holder
  hearing a dominating `X` before its jitter ends cancels; two concurrent corrections are harmless);
  a restored refused request corrected by sync (terminal records synced); an accepted future-dated
  generation stays closed; two GUIDs with one name never merged and a join of one never closes the
  other; a GUID closure also closes the same-name name-only request, and that one doesn't reopen
  from a restore; the request window refuses an open name; > 100 terminal records within the
  retention window all kept; `W` only with a resolved GUID; duplicate rid from two relayers; equal
  timestamps; simultaneous clicks; dropped packets incl. a lost `S` (one retry); throttle result 3;
  a 30-request sync from one holder accepted in full through a 20-slot queue; suppression never
  drops the canonical `R`; forwarded `C`/`X` keep their actor; distinct-sender `A` counting; late
  inviter with an unloaded roster; reload during a claim; guild switch; dev mode only after reload;
  secret arguments; invite watcher states; `test_methods`; every string in both languages.
- `Tools\deploy.ps1 -Probe`; the owner's procedures (`/fp steps partout …`), read back from
  SavedVariables; the officer procedure before release.
