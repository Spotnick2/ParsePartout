-- PartoutProbe smoke test: it loads as a ForeverProbe module, registers only
-- real events, and its commands and actions run against the stub guild. What
-- it measures needs the live client; this only keeps it from breaking there.
-- Its lines go to the console and PartoutProbeDB.log, never to chat (the one
-- exception: the link it prints on purpose). Runs locally only (ForeverProbe is
-- private; CI skips it).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon()
local FP = loadForeverProbe()
local P = loadPartoutProbe()
newChat()

eq(type(PartoutProbeDB), "table", "the probe's saved table exists")
eq(PartoutProbeDB.loads, 1, "it counts sessions")
check(P.Probe.log == PartoutProbeDB.log, "its ForeverProbe log is PartoutProbeDB.log, bound at ADDON_LOADED")
check(WoW.prefixes[P.PREFIX], "the test prefix is registered")
eq(P.PREFIX, "ParsePartoutT", "  and it is the test prefix, never the addon's")

local seen = 0
local function newLog()
    local lines = {}
    for i = seen + 1, #PartoutProbeDB.log do lines[#lines + 1] = PartoutProbeDB.log[i] end
    seen = #PartoutProbeDB.log
    return table.concat(lines, "\n")
end
newLog()

-- state: the guild, permissions, rank flags, the own roster row.
SlashCmdList.FOREVERPROBE("partout state")
local log = newLog()
check(log:find("CanGuildInvite = false", 1, true), "state reads CanGuildInvite")
check(log:find('GetGuildInfo(player) = "Parse Partout"', 1, true), "state reads the guild")
check(log:find("rank 4 flags:", 1, true), "state reads each rank's flags")
check(log:find("own roster row: rankIndex 3", 1, true), "state finds the player's own roster row")

-- globals: the guild strings, read whole from _G.
SlashCmdList.FOREVERPROBE("partout globals")
log = newLog()
check(log:find('ERR_GUILD_JOIN_S = "%s has joined the guild."', 1, true), "globals lists the join string")
check(log:find("4 guild-related globals", 1, true), "  and counts them")

-- Patterns: names with a surname, positional specifiers.
check(("Bob Smith has joined the guild."):find(P.toPattern(ERR_GUILD_JOIN_S)), "the join pattern takes a two-word name")
check(not ("Bob Smith has joined the raid."):find(P.toPattern(ERR_GUILD_JOIN_S)), "  and nothing else")
check(("Bob a rejoint Les Gens."):find(P.toPattern("%1$s a rejoint %2$s.")), "a positional %1$s matches")
eq(P.whichGlobal("|cffffff00Bob Smith has joined the guild.|r"), "ERR_GUILD_JOIN_S", "a coloured line is recognized")
eq(P.whichGlobal("You are now AFK."), nil, "a line that isn't a guild string isn't")

-- info: the guild info text, by shape only.
SlashCmdList.FOREVERPROBE("partout info")
log = newLog()
check(log:find("GetInfoText: str", 1, true), "info logs the text's shape")
check(not log:find("discord", 1, true), "  never the text itself")

-- Addon messages on the test prefix: ping, our own echo ignored, pongs counted.
WoW.addonSent = {}
SlashCmdList.FOREVERPROBE("partout ping")
eq(#WoW.addonSent, 1, "ping sends once (our own GUILD echo is not answered)")
eq(WoW.addonSent[1].message, "PING 1", "  PING 1")
eq(WoW.addonSent[1].chatType, "GUILD", "  on GUILD")
eq(WoW.addonSent[1].prefix, "ParsePartoutT", "  on the test prefix")
WoW.fire("CHAT_MSG_ADDON", "ParsePartoutT", "PING 7", "GUILD", "Carl Martin", "Carl Martin", 0, 0, "", 0)
eq(WoW.addonSent[2] and WoW.addonSent[2].message, "PONG 7", "another client's ping is answered")
WoW.fire("CHAT_MSG_ADDON", "ParsePartoutT", "PONG 1", "GUILD", "Carl Martin", "Carl Martin", 0, 0, "", 0)
eq(#P.state.pongs, 1, "a pong to our ping is counted")
WoW.fire("CHAT_MSG_ADDON", "ParsePartout", "PING 8", "GUILD", "Carl Martin", "Carl Martin", 0, 0, "", 0)
eq(#WoW.addonSent, 2, "the addon's own prefix is left alone")
WoW.fire("CHAT_MSG_ADDON", "ParsePartoutT", "PING 9", "WHISPER", "Carl Martin", "Aline Dubois", 0, 0, "", 0)
eq(WoW.addonSent[3] and WoW.addonSent[3].chatType, "WHISPER", "a whispered ping is answered by whisper")
eq(WoW.addonSent[3] and WoW.addonSent[3].target, "Carl Martin", "  to its sender")

-- A whisper: logged by shape, the sender kept in memory for the whisper back.
newLog()
WoW.fire("CHAT_MSG_WHISPER", "salut, tu peux m'inviter ?", "Zed Outsider", "", "", "Zed Outsider", "", 0, 0, "",
    0, 1, "Player-1-0000ABCD", 0, false, false, false)
log = newLog()
check(log:find("WHISPER text str", 1, true), "a whisper is logged by shape")
check(not log:find("Zed", 1, true) and not log:find("inviter", 1, true), "  never its sender or its words")
eq(P.state.whisperer, "Zed Outsider", "the sender is kept in memory")

-- The link's click whispers back (SetItemRef callback).
WoW.clickLink("addon:partoutprobe:whisper")
eq(WoW.sentChat[1] and WoW.sentChat[1].target, "Zed Outsider", "the link's click whispers the last whisperer")
eq(WoW.sentChat[1] and WoW.sentChat[1].chatType, "WHISPER", "  as a whisper")
check(P.state.linkResult and P.state.linkResult.ok, "  and records it")
WoW.clickLink("addon:other:thing")
eq(#WoW.sentChat, 1, "another addon's link does nothing")

-- The invite: recorded, then what comes back collected and named.
P.invite("Zed Outsider", "plain")
eq(WoW.invites[1], "Zed Outsider", "invite calls C_GuildInfo.Invite with the name verbatim")
WoW.fire("CHAT_MSG_SYSTEM", "You have invited Zed Outsider to join your guild.")
WoW.fire("UI_ERROR_MESSAGE", 1, "Something else")
local a = P.state.attempt
eq(#a.lines, 2, "what comes back during the attempt is collected")
check(a.lines[1]:find("[ERR_GUILD_INVITE_S]", 1, true), "  and the invite string is named")
local finished = P.collected()
check(not finished(), "the collection waits")
WoW.advance(11)
check(finished(), "  and ends after its window")

-- Notes, by GUID, from roster rows.
P.writeNote("Carl Martin", true, "PartoutProbe")
eq(WoW.notesSet[1] and WoW.notesSet[1].guid, "Player-1-0000CA41", "SetNote takes the member's GUID")
eq(WoW.notesSet[1] and WoW.notesSet[1].isPublic, true, "  public note")
check(not P.writeNote("Nobody Here", true, "x"), "a name not in the roster writes nothing")

-- The procedures are defined.
SlashCmdList.FOREVERPROBE("steps")
local listed = { owner = false, officer = false }
for _, l in ipairs(FP.lines) do
    for name in pairs(listed) do
        if l.text:find("partout " .. name, 1, true) then listed[name] = true end
    end
end
check(listed.owner, "the owner procedure is listed")
check(listed.officer, "the officer procedure is listed")

-- Nothing in chat but the deliberate stimulus (none was printed here).
eq(#newChat(), 0, "nothing in chat")

done("test_probe")
