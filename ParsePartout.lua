-- ParsePartout.lua: bootstrap, saved settings, the settings helpers and the
-- /partout command. Loads last: every module is defined by now.

local ADDON = ...
ParsePartout = ParsePartout or {}
local PP = ParsePartout
local API = PP.API
local L = PP.L
local say = API.Print

-- Account-wide (ParsePartoutDB): settings, the same on every character.
local DEFAULTS = {
    language = "auto",   -- "auto" (the client's: frFR -> French, else English), "fr" or "en"
}
PP.DEFAULTS = DEFAULTS

-- Only what the player SET is saved: everything else falls through to
-- DEFAULTS, so a changed default reaches everyone. Saved keys equal to the
-- default are dropped. Nothing may REQUIRE a value to have survived
-- (GlassChat's rule).
local function ensureDefaults()
    if type(ParsePartoutDB) ~= "table" then ParsePartoutDB = {} end
    local db = ParsePartoutDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    if db.language ~= nil and not PP.Locale.IsValid(db.language) then db.language = nil end
    setmetatable(db, { __index = DEFAULTS })
    return db
end

-- Every setting goes through here: /partout and the options page.
local Settings = {}
PP.Settings = Settings

-- False for a value that isn't a language choice; the setting is left as it was.
function Settings.SetLanguage(choice)
    if not PP.Locale.IsValid(choice) then return false end
    PP.db.language = choice
    PP.Window.Refresh()
    PP.Options.Refresh()
    return true
end

-- A dev build, by its version: "dev" from the deploy script, or the
-- packager's token left unreplaced (matched as a pattern, never written whole:
-- the packager would replace it here too). Unreadable is NOT dev.
function PP.IsDev()
    local v = API.AddOnVersion(ADDON or "ParsePartout")
    return v ~= nil and (v == "dev" or v:find("@project%-version@") ~= nil)
end

function PP.VersionText()
    local v = API.AddOnVersion(ADDON or "ParsePartout")
    if v == nil or v == "" or PP.IsDev() then return "dev" end
    return v
end

local function failures()
    local any = false
    for key, err in pairs(PP.failures) do
        any = true
        say(key .. ": " .. err)
    end
    for _, line in ipairs(PP.eventFailures) do
        any = true
        say("event " .. line)
    end
    if not any then say(L("NO_FAILURES")) end
end

-- The command list: /partout aide (or help) prints it.
local function helpLines()
    return {
        L("HELP_TOGGLE"),
        L("HELP_LANGUAGE", L("LANGUAGE_" .. PP.db.language)),
        L("HELP_OPTIONS"),
        L("HELP_FAILURES"),
        L("HELP_VERSION"),
    }
end
PP.HelpLines = helpLines

-- Every command has its French and its English name, whatever the language.
local COMMANDS = {
    aide = "help", help = "help",
    langue = "language", language = "language",
    options = "options",
    erreurs = "failures", failures = "failures",
    version = "version",
}

local function slash(msg)
    local word, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local cmd = COMMANDS[word]
    if word == "" then
        PP.Window.Toggle()
    elseif cmd == "language" then
        if not Settings.SetLanguage(arg) then return say(L("LANGUAGE_USAGE")) end
        say(L("LANGUAGE_SET", L("LANGUAGE_" .. arg)))
    elseif cmd == "options" then
        if not PP.Options.Open() then say(L("OPTIONS_PATH")) end
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say(L("VERSION_LINE", PP.VersionText(), API.ClientBuild(), PP.MEASURED_ON_BUILD))
    else
        for _, line in ipairs(helpLines()) do say(line) end
    end
end

SLASH_PARSEPARTOUT1 = "/partout"
SLASH_PARSEPARTOUT2 = "/parsepartout"
SlashCmdList.PARSEPARTOUT = slash

local function start(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail(key, err) end
end

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then PP.db = ensureDefaults() end
    elseif event == "PLAYER_LOGIN" then
        -- SavedVariables are read here at the latest (porting guide: not at file scope).
        if not PP.db then PP.db = ensureDefaults() end
        start("options", PP.Options.Register)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin. The build warning asks the developer to
        -- check again; a player can't act on it, and /reload never repeats it.
        if arg1 and PP.IsDev() and API.ClientBuild() ~= PP.MEASURED_ON_BUILD then
            say(L("BUILD_WARNING", API.ClientBuild(), PP.MEASURED_ON_BUILD))
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })

PP._test = PP._test or {}
PP._test.ensureDefaults = ensureDefaults
