-- wow_stubs.lua: Parse Partout's WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics are WowTestKit's core (tests/kit.lua loads the commit and the
-- build tests/kit.pin names): strict globals, secrets, events checked against
-- the build, widgets that record every method called, print with the
-- stray-"|" check, timers, hooksecurefunc, fire / fireAllRegistered / tick,
-- check / eq / done. Its README is the reference. This file adds the client
-- APIs the addon touches and the widget methods the core doesn't have.

dofile("tests/kit.lua")
local Methods = WoW.Methods

--------------------------------------------------------------------------------
-- Widgets: the methods the core doesn't have
--------------------------------------------------------------------------------

-- A button's state textures: Set*Texture(file) makes one, Get*Texture reads it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    local key = "_" .. state:lower() .. "Texture"
    Methods["Set" .. state .. "Texture"] = function(b, file)
        b[key] = b[key] or WoW.newWidget("Texture", b)
        b[key]._file = file
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b[key] end
end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- Dragging: StartMoving / StopMovingOrSizing are only recorded.
function Methods.SetMovable(w, on) w._movable = on == true end
function Methods.IsMovable(w) return w._movable == true end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

SlashCmdList = {}
UISpecialFrames = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetBuildInfo() return "1.60.1", "70790", "Nov 4 2026", 16001 end
-- The client's locale: French by default, the addon's main language.
WoW.locale = "frFR"
function GetLocale() return WoW.locale end

WoW.addonVersion = "dev"
C_AddOns = {
    GetAddOnMetadata = function(name, field) if field == "Version" then return WoW.addonVersion end end,
}

WoW.categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name, id = #WoW.categories + 1 }
        function c:GetID() return self.id end
        table.insert(WoW.categories, c)
        return c
    end,
    RegisterAddOnCategory = function(c) c.registered = true end,
    OpenToCategory = function(id) WoW.openedCategory = id end,
}

--------------------------------------------------------------------------------
-- The player and the guild
--
-- WoW.guild = { name, realm, myRank (0-based), ranks = { "Maître", ... },
--   members = { { name, rank, level, class, note, onote, online, guid }, ... },
--   canInvite, isOfficer, isLeader, canEditPublic, canEditOfficer, canViewOfficer,
--   info (the guild info text) } or nil (not in a guild).
--
-- MEASURED (GuildSpy, 1.60.1.70338): GetGuildRosterInfo returns 17 values in
-- Retail's order, the GUID last, the name "First Surname" with no realm, the
-- rank index 0-based; the officer note "" for a character that can't view it.
-- GetGuildInfo's 4th return is the GUILD's realm. UnitName("player") gives the
-- surname in its second return (AltStable #56).
--------------------------------------------------------------------------------

local function resetGuild()
    WoW.playerName, WoW.playerSurname = "Aline", "Dubois"
    WoW.guild = {
        name = "Parse Partout", realm = "Doomhowl", myRank = 3,
        ranks = { "Maître de guilde", "Officier", "Vétéran", "Membre" },
        members = {
            { name = "Aline Dubois", rank = 3, level = 40, class = "MAGE", online = true, guid = "Player-1-0000A11E" },
            { name = "Carl Martin", rank = 1, level = 60, class = "WARRIOR", online = true, guid = "Player-1-0000CA41",
              note = "Tank", onote = "Officier" },
        },
        info = "Discord : discord.gg/exemple",
    }
    WoW.prefixes, WoW.addonSent, WoW.addonResult = {}, {}, nil
    WoW.sentChat, WoW.chatSendThrows = {}, nil
    WoW.invites, WoW.notesSet = {}, {}
    WoW.lockdown = false
    WoW.itemRefCallbacks = {}
end
table.insert(WoW.onReset, resetGuild)
resetGuild()

function UnitName(unit) if unit == "player" then return WoW.playerName, WoW.playerSurname end end

local function guild() return WoW.guild end
local function capability(key) return function() return guild() ~= nil and guild()[key] == true end end

function IsInGuild() return guild() ~= nil end
function GetGuildInfo(unit)
    local gd = guild()
    if unit ~= "player" or not gd then return nil end
    return gd.name, gd.ranks[gd.myRank + 1], gd.myRank, gd.realm
end
function GetNumGuildMembers()
    local gd = guild()
    if not gd then return 0, 0 end
    local online = 0
    for _, m in ipairs(gd.members) do if m.online then online = online + 1 end end
    return #gd.members, online
end
function GetGuildRosterInfo(i)
    local gd = guild()
    local m = gd and gd.members[i]
    if not m then return nil end
    local onote = gd.canViewOfficer and m.onote or ""
    return m.name, gd.ranks[m.rank + 1], m.rank, m.level, m.class, m.zone or "",
        m.note or "", onote or "", m.online and true or false, 0, m.class, -1, 0, false, false, 3, m.guid
end
function GuildControlGetNumRanks() return guild() and #guild().ranks or 0 end
CanGuildInvite = capability("canInvite")
CanEditPublicNote = capability("canEditPublic")
IsGuildLeader = capability("isLeader")
function GetGuildInfoText() return guild() and guild().info or "" end

-- C_GuildInfo.Invite and SetNote are recorded, never acted on.
C_GuildInfo = {
    GuildRoster = function() end,
    IsGuildOfficer = capability("isOfficer"),
    CanEditOfficerNote = capability("canEditOfficer"),
    CanViewOfficerNote = capability("canViewOfficer"),
    GetInfoText = function() return guild() and guild().info or "" end,
    Invite = function(name) table.insert(WoW.invites, name) end,
    SetNote = function(guid, note, isPublic)
        table.insert(WoW.notesSet, { guid = guid, note = note, isPublic = isPublic })
    end,
    MemberExistsByName = function(name)
        for _, m in ipairs(guild() and guild().members or {}) do if m.name == name then return true end end
        return false
    end,
    GuildControlGetRankFlags = function(rank) return { rank <= 2, rank <= 1 } end,
}

-- Localized system strings: enUS, as read from the client (GuildSpy's probe, 70338).
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_INVITE_S = "You have invited %s to join your guild."
ERR_GUILD_DECLINE_S = "%s declines your guild invitation."

--------------------------------------------------------------------------------
-- Chat: addon messages, chat messages, links
--
-- A GUILD addon message is recorded in WoW.addonSent and, as the server does,
-- echoed to its sender as CHAT_MSG_ADDON (measured, 70205: the sender is
-- "First Surname"). WoW.addonResult: what a send answers (0: success).
-- SendChatMessage is recorded in WoW.sentChat; WoW.chatSendThrows makes it raise.
--------------------------------------------------------------------------------

local function playerFullName() return WoW.playerName .. " " .. WoW.playerSurname end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        WoW.prefixes[prefix] = true
        return 0
    end,
    SendAddonMessage = function(prefix, message, chatType, target)
        assert(#message <= 255, "an addon message over 255 bytes")
        local result = WoW.addonResult or 0
        if result ~= 0 then return result end
        table.insert(WoW.addonSent, { prefix = prefix, message = message, chatType = chatType, target = target })
        if chatType == "GUILD" and guild() then
            local me = playerFullName()
            WoW.fire("CHAT_MSG_ADDON", prefix, message, "GUILD", me, me, 0, 0, "", 0)
        end
        return 0
    end,
    SendChatMessage = function(text, chatType, language, target)
        if WoW.chatSendThrows then error(WoW.chatSendThrows) end
        table.insert(WoW.sentChat, { text = text, chatType = chatType, target = target })
    end,
    InChatMessagingLockdown = function() return WoW.lockdown == true end,
}

-- EventRegistry: only the SetItemRef callback (a chat link's click, measured
-- route, porting guide). WoW.clickLink(link) delivers a click as the client does:
-- (owner, link, text, button, frame).
EventRegistry = {
    RegisterCallback = function(self, event, fn, owner)
        if event == "SetItemRef" then table.insert(WoW.itemRefCallbacks, { fn = fn, owner = owner }) end
    end,
}
function WoW.clickLink(link, button)
    for _, c in ipairs(WoW.itemRefCallbacks) do c.fn(c.owner, link, "[link]", button or "LeftButton", nil) end
end

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
-- ForeverProbe and the probe's saved table: the probe's tests load the host.
Kit.strict({ ParsePartout = true, ParsePartoutDB = true, LibStub = true,
    ForeverProbe = true, ForeverProbeDB = true, PartoutProbeDB = true })
