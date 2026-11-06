-- PartoutProbe: what Parse Partout's guild invite requests (#9) need to know
-- about the live client, measured rather than assumed. A ForeverProbe module:
-- /fp partout for the commands, /fp steps partout <name> for the procedures.
--
-- Two procedures (docs/FOREVER-PROBE.md says what each measures and why):
--   owner    the owner, two accounts in the guild, no invite rights: guild
--            state and strings, the guild info text, addon messages between
--            two clients, a whisper sent from a click, from a timer and from
--            a chat link's click.
--   officer  an officer with invite rights and a consenting non-member: the
--            invite from a click, what comes back (sent, declined, joined,
--            already in a guild, nobody by that name), whisper + invite in one
--            click, the notes written from a click.
--
-- Rules (ForeverProbe's guide): lines go to /fp and PartoutProbeDB.log, never
-- to chat; the only chat lines are deliberate stimuli (the link to click).
-- Nothing another player wrote is logged: a whisper is logged by shape only,
-- and the name it came from stays in memory for the whisper back. Addon
-- messages use a test prefix of their own, never the addon's.

local ADDON, NS = ...
local MAX_LOG = 3000
local PREFIX = "ParsePartoutT"          -- the test prefix (Parse Partout's dev mode uses it too)
local COLLECT = 10                       -- seconds of results collected after an attempt
local NOBODY = "Zzqx Qzzv"               -- a name nobody has, for the "not found" result

local Probe = ForeverProbe:Module("PartoutProbe", { api = 1, cmd = "partout" })
local function say(msg) Probe:Say(msg) end
local show = Probe.Show

-- In-memory state for the procedures; never saved (names of other players).
local state = {
    target = nil,        -- the officer procedure's non-member, /fp partout target <name>
    whisperer = nil,     -- who last whispered us (owner procedure), for the whisper back
    pongs = {},          -- { { from, channel, n } } answers to our pings
    pingN = 0,
    attempt = nil,       -- { what, name, t, lines } the action being watched
    linkResult = nil,    -- the chat link's click: { ok, err }
    timerResult = nil,   -- the timer whisper: { ok, err }
}

-- A dotted global path read with rawget, so a strict stub never trips.
local function get(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = rawget(v, part)
    end
    return v
end

local function secret(v)
    local is = get("issecretvalue")
    return is ~= nil and is(v) == true
end

local function plainString(v)
    return type(v) == "string" and not secret(v)
end

-- A chat test stimulus: a line this probe writes to chat ON PURPOSE (the
-- link the owner clicks). Diagnostics never come here.
local function stimulus(msg) print("|cffe8b03aPartoutProbe|r " .. msg) end

--------------------------------------------------------------------------------
-- Guild strings: the localized globals, turned into patterns
--------------------------------------------------------------------------------

-- The globals a guild invite can answer with. ERR_GUILD_* is read whole
-- from _G (whatever this build has); these are the others worth having.
local EXTRA_GLOBALS = { "ERR_ALREADY_IN_GUILD_S", "ERR_ALREADY_INVITED_TO_GUILD_S", "ERR_INVITE_PLAYER_S",
    "ERR_BAD_PLAYER_NAME_S", "ERR_CHAT_PLAYER_NOT_FOUND_S", "ERR_PLAYER_NOT_FOUND_S" }

local function guildGlobals()
    local names = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^ERR_GUILD_") and plainString(v) then names[#names + 1] = k end
    end
    for _, k in ipairs(EXTRA_GLOBALS) do
        if plainString(rawget(_G, k)) then names[#names + 1] = k end
    end
    table.sort(names)
    return names
end

-- A format string as an anchored pattern: magic characters escaped, each
-- %s / %d / %n$s a capture (GuildSpy's Patterns.lua approach, names with spaces).
local function toPattern(fmt)
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")   -- "%1$s" is now "%1%$s"
    p = p:gsub("%%%d%%%$[sd]", "(.+)"):gsub("%%[sd]", "(.+)")
    return "^" .. p .. "$"
end

local patterns   -- { { name, pattern } }, built on first use
local function guildPatterns()
    if patterns then return patterns end
    patterns = {}
    for _, name in ipairs(guildGlobals()) do
        local ok, p = pcall(toPattern, rawget(_G, name))
        if ok then patterns[#patterns + 1] = { name, p } end
    end
    return patterns
end

-- The global a line matches, or nil.
local function whichGlobal(text)
    if not plainString(text) then return nil end
    local line = Probe.Plain(text)
    for _, e in ipairs(guildPatterns()) do
        if line:find(e[2]) then return e[1] end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Reading the guild state
--------------------------------------------------------------------------------

local function one(label, path, ...)
    local fn = get(path)
    local r = Probe.Pack(Probe:Try(label or path, fn, ...))
    if r[1] then
        local out = {}
        for i = 2, r.n do out[#out + 1] = show(r[i]) end
        say(label .. " = " .. (#out > 0 and table.concat(out, ", ") or "(nothing)"))
    end
    return r[1] == true, r[2]
end

-- The roster row of a name ("First Surname"), as plain values, or nil.
local function rosterRow(name)
    if not plainString(name) then return nil end
    local okN, n = Probe:Try("GetNumGuildMembers", get("GetNumGuildMembers"))
    if not okN or type(n) ~= "number" or secret(n) then return nil end
    for i = 1, n do
        local r = Probe.Pack(Probe:Try("GetGuildRosterInfo", get("GetGuildRosterInfo"), i))
        if r[1] and plainString(r[2]) and r[2] == name then
            return { index = i, name = r[2], rankIndex = r[4], publicNote = r[8], officerNote = r[9], guid = r[18] }
        end
    end
    return nil
end

local function playerName()
    local ok, a, b = Probe:Try("UnitName", get("UnitName"), "player")
    if not ok or not plainString(a) then return nil end
    if a:find(" ") or not plainString(b) or b == "" then return a end
    return a .. " " .. b
end

local function readState()
    say("client " .. table.concat({ GetBuildInfo() }, " ", 1, 2) .. ", locale " .. show(GetLocale and GetLocale()))
    local _, inGuild = one("IsInGuild", "IsInGuild")
    one("GetGuildInfo(player)", "GetGuildInfo", "player")
    local _, canInvite = one("CanGuildInvite", "CanGuildInvite")
    one("C_GuildInfo.IsGuildOfficer", "C_GuildInfo.IsGuildOfficer")
    one("IsGuildLeader", "IsGuildLeader")
    one("CanEditPublicNote", "CanEditPublicNote")
    one("C_GuildInfo.CanEditOfficerNote", "C_GuildInfo.CanEditOfficerNote")
    one("C_GuildInfo.CanViewOfficerNote", "C_GuildInfo.CanViewOfficerNote")
    one("C_ChatInfo.InChatMessagingLockdown", "C_ChatInfo.InChatMessagingLockdown")
    one("GetNumGuildMembers", "GetNumGuildMembers")
    -- Rank permissions: can a member who can't invite read who can? (Answers
    -- whether rank flags could ever replace each client's own CanGuildInvite.)
    local okR, ranks = one("GuildControlGetNumRanks", "GuildControlGetNumRanks")
    if okR and type(ranks) == "number" and not secret(ranks) then
        for r = 1, math.min(ranks, 10) do
            local ok, flags = Probe:Try("GuildControlGetRankFlags(" .. r .. ")", get("C_GuildInfo.GuildControlGetRankFlags"), r)
            if ok then say("rank " .. r .. " flags: " .. Probe.Describe(flags)) end
        end
    end
    local me = rosterRow(playerName())
    if me then
        say("own roster row: rankIndex " .. show(me.rankIndex) .. ", guid " .. Probe.Shape(me.guid)
            .. ", public note " .. Probe.Shape(me.publicNote) .. ", officer note " .. Probe.Shape(me.officerNote))
    else
        say("own roster row: not found (roster not loaded yet?)")
    end
    return inGuild, canInvite
end

local function readGlobals()
    local names = guildGlobals()
    for _, k in ipairs(names) do say(k .. " = " .. show(rawget(_G, k))) end
    say(#names .. " guild-related globals")
    return #names
end

-- C_GuildInfo.GetInfoText has HasRestrictions: read it from the click that
-- calls this, and log only its shape (the guild's text is the guild's).
local function readInfoText()
    local ok, text = Probe:Try("C_GuildInfo.GetInfoText", get("C_GuildInfo.GetInfoText"))
    say("GetInfoText: " .. (ok and Probe.Shape(text) or "failed"))
    local okG, textG = Probe:Try("GetGuildInfoText", get("GetGuildInfoText"))
    say("GetGuildInfoText: " .. (okG and Probe.Shape(textG) or "failed"))
    return ok and Probe.Shape(text), okG and Probe.Shape(textG)
end

--------------------------------------------------------------------------------
-- Addon messages on the test prefix: ping / pong between two clients
--------------------------------------------------------------------------------

local function sendAddon(text, channel, target)
    local ok, res = Probe:Try("SendAddonMessage " .. channel, get("C_ChatInfo.SendAddonMessage"), PREFIX, text, channel, target)
    say("SendAddonMessage " .. channel .. (target and (" to " .. show(target)) or "") .. " -> " .. show(ok and res))
    return ok, res
end

local function ping(target)
    state.pingN = state.pingN + 1
    state.pongs = {}
    return sendAddon("PING " .. state.pingN, target and "WHISPER" or "GUILD", target)
end

local function onAddon(prefix, text, channel, sender)
    if prefix ~= PREFIX or not plainString(text) or not plainString(sender) then return end
    say("ADDON " .. show(channel) .. " from " .. show(sender) .. ": " .. show(text))
    local n = text:match("^PING (%d+)$")
    if n then
        if sender == playerName() then return end   -- our own GUILD echo
        if channel == "WHISPER" then sendAddon("PONG " .. n, "WHISPER", sender) else sendAddon("PONG " .. n, "GUILD") end
        return
    end
    n = text:match("^PONG (%d+)$")
    if n and sender ~= playerName() then
        table.insert(state.pongs, { from = sender, channel = channel, n = tonumber(n) })
    end
end

--------------------------------------------------------------------------------
-- Restricted actions: whispers and invites, from the calling click
--------------------------------------------------------------------------------

local function sendChat()
    return get("C_ChatInfo.SendChatMessage") or get("SendChatMessage")
end

local function whisper(name, text, how)
    if not plainString(name) then say("whisper " .. how .. ": no target"); return false end
    local ok, err = Probe:Try("SendChatMessage WHISPER (" .. how .. ")", sendChat(), text, "WHISPER", nil, name)
    say("whisper " .. how .. " to " .. show(name) .. " -> " .. (ok and "no error" or show(err)))
    return ok
end

-- Watch what comes back for COLLECT seconds: system lines, UI info/error
-- messages (the host logs ADDON_ACTION_BLOCKED/FORBIDDEN itself).
local function startAttempt(what, name)
    state.attempt = { what = what, name = name, t = GetTime(), lines = {} }
    say("ATTEMPT " .. what .. " " .. show(name))
end

local function note(kind, text)
    local a = state.attempt
    local g = whichGlobal(text)
    local line = kind .. (g and (" [" .. g .. "]") or "") .. ": " .. (plainString(text) and show(Probe.Plain(text)) or show(text))
    if a and GetTime() - a.t <= COLLECT * 3 then
        a.lines[#a.lines + 1] = string.format("+%.1fs %s", GetTime() - a.t, line)
        say("RESULT " .. a.what .. " " .. a.lines[#a.lines])
    elseif g then
        say("GUILD LINE " .. line)   -- passive: guild lines seen outside an attempt
    end
end

local function invite(name, what)
    if not plainString(name) then say("invite " .. what .. ": no target"); return false end
    startAttempt(what, name)
    local ok, err = Probe:Try("C_GuildInfo.Invite", get("C_GuildInfo.Invite"), name)
    say("C_GuildInfo.Invite(" .. show(name) .. ") -> " .. (ok and "no error" or show(err)))
    return ok
end

-- A wait-step function: done once COLLECT seconds have passed since the
-- attempt (or `stop(lines)` says so), its result the lines collected.
local function collected(stop)
    return function()
        local a = state.attempt
        if not a then return false, "no attempt yet: press Run on the step before" end
        local lines = table.concat(a.lines, " | ")
        if (stop and stop(a)) or GetTime() - a.t >= COLLECT then return true, #a.lines .. " lines", lines end
        return false, string.format("collecting %.0f s", COLLECT - (GetTime() - a.t))
    end
end

local function sawGlobal(name)
    return function(a)
        for _, l in ipairs(a.lines) do if l:find("[" .. name .. "]", 1, true) then return true end end
        return false
    end
end

-- Notes, by GUID, from the calling click (C_GuildInfo.SetNote has HasRestrictions).
local saved = {}   -- the target's notes before the test, to put back
local function readNotes(name)
    local row = rosterRow(name)
    if not row then say("notes: " .. show(name) .. " not in the roster"); return false end
    say("notes of " .. show(name) .. ": public " .. show(row.publicNote) .. ", officer " .. show(row.officerNote)
        .. ", guid " .. Probe.Shape(row.guid))
    return true, row
end

local function writeNote(name, isPublic, text)
    local ok, row = readNotes(name)
    if not ok then return false end
    if saved.name ~= name then saved = { name = name, public = row.publicNote, officer = row.officerNote } end
    local okSet, err = Probe:Try("C_GuildInfo.SetNote", get("C_GuildInfo.SetNote"), row.guid, text, isPublic)
    say("SetNote(" .. (isPublic and "public" or "officer") .. ") -> " .. (okSet and "no error" or show(err)))
    return okSet
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        Probe:Ready()
        if type(PartoutProbeDB) ~= "table" then PartoutProbeDB = {} end
        if type(PartoutProbeDB.log) ~= "table" then PartoutProbeDB.log = {} end
        Probe:UseLog(PartoutProbeDB.log, MAX_LOG)
        PartoutProbeDB.loads = (PartoutProbeDB.loads or 0) + 1
        local reg = get("C_ChatInfo.RegisterAddonMessagePrefix")
        local ok, res = Probe:Try("RegisterAddonMessagePrefix", reg, PREFIX)
        say("loaded (" .. PartoutProbeDB.loads .. " loads), prefix " .. PREFIX .. " -> " .. show(ok and res)
            .. ". /fp partout for the commands, /fp steps for the procedures")
    elseif event == "CHAT_MSG_ADDON" then
        onAddon(...)
    elseif event == "CHAT_MSG_WHISPER" then
        local text, sender = ...
        local guid = select(12, ...)
        say("WHISPER text " .. Probe.Shape(text) .. ", sender " .. Probe.Shape(sender) .. ", guid " .. Probe.Shape(guid))
        if plainString(sender) then state.whisperer = sender end
    elseif event == "CHAT_MSG_SYSTEM" then
        note("SYSTEM", (...))
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        local kind, text = ...
        note(event .. "(" .. show(kind) .. ")", text)
    end
end)
Probe:RegisterEvents(events, { "ADDON_LOADED", "CHAT_MSG_ADDON", "CHAT_MSG_WHISPER", "CHAT_MSG_SYSTEM",
    "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" })

-- The chat link's click (measured route: EventRegistry's SetItemRef callback).
local registry = get("EventRegistry")
if registry and registry.RegisterCallback then
    Probe:Try("EventRegistry SetItemRef", registry.RegisterCallback, registry, "SetItemRef", function(_, link)
        if type(link) ~= "string" or secret(link) or link ~= "addon:partoutprobe:whisper" then return end
        local ok = whisper(state.whisperer, "PartoutProbe : chuchotement depuis un lien", "link click")
        state.linkResult = { ok = ok }
    end, Probe)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

Probe:Command("state", function() readState() end, "guild state, permissions, rank flags, own roster row")
Probe:Command("globals", function() readGlobals() end, "the guild strings of this client's language")
Probe:Command("info", function() readInfoText() end, "the guild info text's shape (C_GuildInfo.GetInfoText)")
Probe:Command("target", function(args)
    local name = (args or ""):match("^%s*(.-)%s*$")
    state.target = name ~= "" and name or nil
    say("target = " .. show(state.target))
end, "<First Surname>: the non-member for the officer procedure")
Probe:Command("ping", function(args)
    local name = (args or ""):match("^%s*(.-)%s*$")
    ping(name ~= "" and name or nil)
end, "[First Surname]: a ping on the test prefix, GUILD (or WHISPER to a name)")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

--------------------------------------------------------------------------------
-- Procedures
--------------------------------------------------------------------------------

local function pongs(channel)
    return function()
        for _, p in ipairs(state.pongs) do
            if p.channel == channel and p.n == state.pingN then return true, "pong from " .. p.from .. " on " .. channel end
        end
        return false, "waiting for a pong on " .. channel
    end
end

Probe:Steps("owner", {
    title = "Owner: guild state, addon messages, whispers from clicks",
    rev = 1,
    { text = "Log in a character of Parse Partout on this account. Press Read.", button = "Read",
      run = readState, check = function() local f = get("IsInGuild"); return f ~= nil and f() == true, "in a guild" end },
    { text = "The guild strings of this client's language.", auto = true, run = readGlobals },
    { text = "Read the guild info text, from this click (logs its shape only).", button = "Read",
      run = readInfoText },
    { text = "On your other account: log in a guild member, deploy with -Probe there too and /reload. Then press Run here: a ping to the guild on the test prefix.",
      button = "Ping guild", run = function() return ping(nil) end },
    { text = "Waiting for the other client's pong (GUILD).", wait = pongs("GUILD"), timeout = 60 },
    { text = "From the other account, whisper this character anything (\"test\").",
      event = "CHAT_MSG_WHISPER", shapeOnly = true },
    { text = "Press Run: whispers back to that character, from this click.", button = "Whisper back",
      run = function() return whisper(state.whisperer, "PartoutProbe : chuchotement depuis un clic", "click") end },
    { text = "Did the other character get \"chuchotement depuis un clic\"?", ask = true },
    { text = "Press Run: a whisper sent 1 s later from a timer, not from the click. Watch /fp for a blocked-action line.",
      button = "Timer whisper", run = function()
          state.timerResult = nil
          C_Timer.After(1, function()
              state.timerResult = { ok = whisper(state.whisperer, "PartoutProbe : chuchotement depuis un minuteur", "timer") }
          end)
          return "scheduled"
      end },
    { text = "Did the other character get \"chuchotement depuis un minuteur\"?", ask = true },
    { text = "Press Run: a link is printed in chat. Then click [Chuchoter] in the chat line.", button = "Print link",
      run = function()
          state.linkResult = nil
          stimulus("cliquez : |cffe8b03a|Haddon:partoutprobe:whisper|h[Chuchoter]|h|r (test du probe)")
          return "printed"
      end },
    { text = "Waiting for the link's click.", wait = function()
          if state.linkResult then return true, "clicked, whisper " .. (state.linkResult.ok and "sent" or "failed") end
          return false, "click [Chuchoter] in chat"
      end, timeout = 120 },
    { text = "Did the other character get \"chuchotement depuis un lien\"?", ask = true },
    { text = "Press Run: an addon whisper to that character (\"First Surname\").", button = "Ping whisper",
      run = function() return ping(state.whisperer) end },
    { text = "Waiting for the other client's pong (WHISPER).", wait = pongs("WHISPER"), timeout = 60 },
    { text = "Type /reload to save the results.", reload = true },
})

Probe:Steps("officer", {
    title = "Officer: guild invite from a click, results, notes",
    rev = 1,
    { text = "You need an officer who can invite, and a non-member online who agrees to be invited (a real recruit, or someone you remove after). Type /fp partout target First Surname with their exact name, then Next.",
      check = function() return state.target ~= nil, show(state.target) end },
    { text = "Your guild state.", auto = true, run = readState,
      check = function() local f = get("CanGuildInvite"); return f ~= nil and f() == true, "CanGuildInvite" end },
    { text = "The guild strings of this client's language.", auto = true, run = readGlobals },
    { text = "Press Invite: C_GuildInfo.Invite(target) from this click. Ask them to DECLINE.", button = "Invite",
      run = function() return invite(state.target, "plain") end },
    { text = "Collecting what comes back.", wait = collected(), timeout = 60 },
    { text = "Did they get the guild invite window?", ask = true },
    { text = "Collecting their decline (press Done once they declined).",
      wait = function()
          local a = state.attempt
          if not a then return false, "no attempt" end
          for _, l in ipairs(a.lines) do if l:find("DECLINE") then return true, l end end
          return false, #a.lines .. " lines so far"
      end, timeout = 90 },
    { text = "Press Run: a whisper and the invite, in this one click. Ask them to ACCEPT this time.",
      button = "Whisper + Invite", run = function()
          local w = whisper(state.target, "PartoutProbe : un membre m'a demandé de t'inviter dans la guilde", "click, before invite")
          local i = invite(state.target, "whisper+invite")
          return w, i
      end },
    { text = "Did they get both the whisper and the invite?", ask = true },
    { text = "Waiting for them to join.", wait = collected(sawGlobal("ERR_GUILD_JOIN_S")), timeout = 120 },
    { text = "Press Run: invite them again, now that they are in the guild.", button = "Invite again",
      run = function() return invite(state.target, "already in guild") end },
    { text = "Collecting.", wait = collected(), timeout = 60 },
    { text = "Press Run: invite a name nobody has.", button = "Invite nobody",
      run = function() return invite(NOBODY, "nobody") end },
    { text = "Collecting.", wait = collected(), timeout = 60 },
    { text = "Press Run: read their notes.", button = "Read notes", run = function() return readNotes(state.target) end },
    { text = "Press Run: write \"PartoutProbe\" in their public note, from this click.", button = "Write public",
      run = function() return writeNote(state.target, true, "PartoutProbe") end },
    { text = "Press Run: write \"PartoutProbe\" in their officer note, from this click.", button = "Write officer",
      run = function() return writeNote(state.target, false, "PartoutProbe") end },
    { text = "Wait a few seconds, then press Run: read the notes back.", button = "Read back",
      run = function() return readNotes(state.target) end,
      check = function()
          local row = rosterRow(state.target)
          return row ~= nil and row.publicNote == "PartoutProbe", row and show(row.publicNote)
      end },
    { text = "Press Run: put their notes back as they were.", button = "Restore", run = function()
          if saved.name ~= state.target then return false, "nothing saved" end
          local a = writeNote(state.target, true, saved.public or "")
          local b = writeNote(state.target, false, saved.officer or "")
          return a, b
      end },
    { text = "Read the guild info text, from this click (its shape only).", button = "Read", run = readInfoText },
    { text = "Type /reload to save the results.", reload = true },
})

NS._test = { Probe = Probe, state = state, toPattern = toPattern, whichGlobal = whichGlobal, PREFIX = PREFIX,
    invite = invite, whisper = whisper, readNotes = readNotes, writeNote = writeNote, readInfoText = readInfoText,
    collected = collected, ping = ping }
