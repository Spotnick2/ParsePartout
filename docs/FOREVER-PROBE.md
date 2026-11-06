# What the live client does: Parse Partout's measurements

Measured on the live client, with the build. The plan (`docs/PLAN.md`) rests on some of these as
assumptions until they are measured here; a result here wins over the plan, and the plan is
updated in the same PR.

The probe is `Tools/PartoutProbe`, a ForeverProbe module (`..\ForeverProbe\docs\GUIDE.md`).
Deploy it with `pwsh Tools\deploy.ps1 -Probe`, then `/reload` in game:
- `/fp partout` lists its commands: `state`, `globals`, `info`, `target <First Surname>`,
  `ping [First Surname]`, `clear`.
- `/fp steps partout owner` and `/fp steps partout officer` start the procedures below.
- Results: `WTF\Account\<account>\SavedVariables\PartoutProbe.lua` (its log) and
  `ForeverProbe.lua` (`steps.records["PartoutProbe/<name>"]`), read after a `/reload`.

Addon messages in the probe use the test prefix `ParsePartoutT`, never the addon's own. A
whisper is logged by shape only (type and length), never its words or its sender.

## Still open

| Question | Why it matters | Measured by |
|---|---|---|
| Does `C_GuildInfo.Invite` work from an addon button's click? | The Inviter button, or only the copy-`/ginvite` fallback. One reference says no (70790, beta), another addon in production says yes. | officer procedure |
| Whisper + invite in one click: both delivered? | Whether "Prévenir" can be merged into "Inviter". | officer procedure |
| What comes back after an invite: sent, declined, joined, already in a guild, nobody by that name; which event (CHAT_MSG_SYSTEM, UI_INFO_MESSAGE, UI_ERROR_MESSAGE) and which global | The invite result watcher (sent / blocked / unconfirmed). | officer procedure |
| `C_GuildInfo.SetNote` from a click (`HasRestrictions`): public and officer note | The [Notes] editor. | officer procedure |
| `C_GuildInfo.GetInfoText` / `GetGuildInfoText` from a click (`HasRestrictions`) | The "take the guild info" welcome text (cut from v1 until measured). | owner procedure (any member) |
| Can a member who can't invite read the rank flags (`C_GuildInfo.GuildControlGetRankFlags`)? | Only informative: each client decides with its own `CanGuildInvite()`. | owner procedure, `state` |
| GUILD addon messages between two of the owner's clients, and an addon whisper to "First Surname" | The relay and sync transport (#3's base). | owner procedure |
| A whisper sent from a click, from a timer (no click) and from a chat link's click, to "First Surname" | The [Bienvenue] link, the [Répondre] link; whether anything can be sent without a click. | owner procedure |
| A whisper's payload outside an instance: text, sender, GUID (arg 12), secret or not | Detection and the requester's GUID. | owner procedure (shape only) |
| The join line in this client's language | Closing requests on a join. Measured enUS on 70338 (GuildSpy); French not yet. | `globals`, and passively: the probe logs every guild system line it recognizes |

## The procedures

**owner** (the owner: two accounts, both with a character in the guild, no invite rights).
Guild state and strings; the guild info text from a click; a GUILD ping on the test prefix and the
other client's pong; a whisper from the other account (the event's shape); a whisper back from a
click, from a timer, and from a chat link's click (yes/no: received?); an addon whisper to
"First Surname" and its pong. Deploy `-Probe` on both accounts' clients.

**officer** (an officer with invite rights, and a non-member who agrees to be invited: a real
recruit, or someone removed afterwards). `/fp partout target <First Surname>` first. The invite
from the Invite button (received? then declined: what came back); whisper + invite in one click
(both received? then accepted: the join line); an invite to someone already in the guild, and to a
name nobody has (what came back); the notes read, written from a click, read back and restored;
the guild info text. ForeverProbe is a private developer tool: give the officer the
`ForeverProbe` and `PartoutProbe` folders, or run it on an officer's account yourself.

## Measured

Nothing yet.
