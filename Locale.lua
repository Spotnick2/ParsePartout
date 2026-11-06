-- Locale.lua: every player-facing string, French first, with its English.
--
-- French is the addon's main language: a new string is written in French
-- first, then in English. PP.L(key, ...) returns the current language's text,
-- formatted with string.format when arguments are given.
--
-- The language is the player's choice (ParsePartoutDB.language): "auto"
-- follows the client (frFR -> French, any other locale -> English), "fr" and
-- "en" force one. A key missing from the current language falls back to the
-- French text, then to the key itself, so a gap shows rather than breaks.

ParsePartout = ParsePartout or {}
local PP = ParsePartout
local Locale = {}
PP.Locale = Locale

Locale.LANGUAGES = { "auto", "fr", "en" }

local STRINGS = {
    fr = {
        WINDOW_BODY = "L'addon de la guilde. Rien ici pour l'instant : les premières fonctions arrivent.",
        OPTIONS_VERSION = "Version %s pour World of Warcraft: Forever, par Spotnick",
        OPTIONS_OPEN = "Ouvrir la fenêtre",
        OPTIONS_LANGUAGE = "Langue",
        OPTIONS_HINT = "Tapez /partout aide pour toutes les commandes.",
        LANGUAGE_auto = "Celle du jeu",
        LANGUAGE_fr = "Français",
        LANGUAGE_en = "English",
        HELP_TOGGLE = "/partout - ouvrir ou fermer la fenêtre",
        HELP_LANGUAGE = "/partout langue auto/fr/en - la langue de l'addon (%s)",
        HELP_OPTIONS = "/partout options - ouvrir la page d'options",
        HELP_FAILURES = "/partout erreurs - ce qui n'a pas pu se construire ou s'enregistrer",
        HELP_VERSION = "/partout version - la version du client et celle sur laquelle l'addon a été vérifié",
        LANGUAGE_SET = "langue : %s",
        LANGUAGE_USAGE = "/partout langue auto/fr/en",
        OPTIONS_PATH = "Échap > Options > AddOns > Parse Partout",
        NO_FAILURES = "aucune erreur enregistrée",
        VERSION_LINE = "version %s, client %s, vérifié sur %s",
        BUILD_WARNING = "le client %s n'est pas celui sur lequel l'addon a été vérifié (%s). "
            .. "Certaines choses peuvent mal fonctionner d'ici la prochaine vérification.",
        COULD_NOT_REGISTER = "impossible d'enregistrer",
    },
    en = {
        WINDOW_BODY = "The guild's addon. Nothing here yet: the first features are on their way.",
        OPTIONS_VERSION = "Version %s for World of Warcraft: Forever, by Spotnick",
        OPTIONS_OPEN = "Open the window",
        OPTIONS_LANGUAGE = "Language",
        OPTIONS_HINT = "Type /partout help for every command.",
        LANGUAGE_auto = "The game's",
        LANGUAGE_fr = "Français",
        LANGUAGE_en = "English",
        HELP_TOGGLE = "/partout - open or close the window",
        HELP_LANGUAGE = "/partout language auto/fr/en - the addon's language (%s)",
        HELP_OPTIONS = "/partout options - open the options page",
        HELP_FAILURES = "/partout failures - what failed to build or register",
        HELP_VERSION = "/partout version - client build vs the one it was checked on",
        LANGUAGE_SET = "language: %s",
        LANGUAGE_USAGE = "/partout language auto/fr/en",
        OPTIONS_PATH = "Esc > Options > AddOns > Parse Partout",
        NO_FAILURES = "no failures recorded",
        VERSION_LINE = "version %s, client %s, checked on %s",
        BUILD_WARNING = "client build %s differs from the one this addon was checked on (%s). "
            .. "Things may misbehave until it is checked again.",
        COULD_NOT_REGISTER = "could not register",
    },
}
Locale.STRINGS = STRINGS

function Locale.IsValid(choice)
    for _, v in ipairs(Locale.LANGUAGES) do if v == choice then return true end end
    return false
end

-- The client's locale, read once per call (GetLocale can't change mid-session,
-- but the tests switch it). Only frFR maps to French.
local function clientLanguage()
    local ok, loc = pcall(GetLocale)
    if ok and loc == "frFR" then return "fr" end
    return "en"
end

-- The language in use: "fr" or "en". Before the saved settings are read, the
-- client's.
function Locale.Current()
    local choice = PP.db and PP.db.language or "auto"
    if choice == "fr" or choice == "en" then return choice end
    return clientLanguage()
end

function PP.L(key, ...)
    local text = STRINGS[Locale.Current()][key] or STRINGS.fr[key] or key
    if select("#", ...) > 0 then return text:format(...) end
    return text
end
