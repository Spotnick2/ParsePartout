-- Bootstrap: saved settings, the login build warning, /partout, the window and
-- the options page. The client is French (wow_stubs.lua), the main language.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Missing SavedVariables still load.
ParsePartoutDB = nil
local PP = loadAddon()
eq(type(ParsePartoutDB), "table", "missing saved variables become a table")
eq(PP.db, ParsePartoutDB, "the addon keeps the saved table")
check(not chatHas("n'est pas celui"), "no build warning on the checked build")
check(not chatHas("impossible d'enregistrer"), "every event registered")

-- Only what the player set is saved; the rest follows the shipped defaults.
eq(rawget(ParsePartoutDB, "language"), nil, "an untouched setting isn't saved")
eq(PP.db.language, "auto", "it reads the shipped default")
ParsePartoutDB = { language = "auto" }
PP._test.ensureDefaults()
eq(rawget(ParsePartoutDB, "language"), nil, "a saved value equal to the default is dropped")
ParsePartoutDB = { language = "de" }
PP._test.ensureDefaults()
eq(rawget(ParsePartoutDB, "language"), nil, "a language this version doesn't know is dropped")
PP.db = ParsePartoutDB

-- The options page: registered once at login, and blank-proof (hidden at
-- creation, built on its first OnShow).
eq(#WoW.categories, 1, "one options category")
check(WoW.categories[1].registered, "it is an AddOns category")
local panel = PP.Options._test.panel
check(not panel:IsShown(), "the page is hidden at creation")
panel:Show()
check(PP.Options.built, "the page builds on its first show")

-- The window: not built at load, built on first open, closed by Esc.
check(PP.Window._test.frame() == nil, "the window isn't built at load")
newChat()
SlashCmdList.PARSEPARTOUT("")
check(PP.Window.IsShown(), "/partout opens the window")
local w = PP.Window._test.frame()
eq(UISpecialFrames[#UISpecialFrames], PP.Window._test.FRAME_NAME, "Esc closes it")
eq(w:GetName(), PP.Window._test.FRAME_NAME, "  by its name")
check(w.glass ~= nil, "the window is glass")
check(w.body:GetText():find("L'addon de la guilde", 1, true), "it speaks French")
SlashCmdList.PARSEPARTOUT("")
check(not PP.Window.IsShown(), "/partout again closes it")
SlashCmdList.PARSEPARTOUT("")
eq(PP.Window._test.frame(), w, "it is built once")
PP.Window.Hide()
PP.Options._test.open:GetScript("OnClick")()
check(PP.Window.IsShown(), "the options page's button opens it")
PP.Window.Hide()
eq(#newChat(), 0, "nothing said in chat")

-- /partout: French and English command names alike.
SlashCmdList.PARSEPARTOUT("aide")
eq(#newChat(), #PP.HelpLines(), "/partout aide prints the help list")
SlashCmdList.PARSEPARTOUT("help")
eq(#newChat(), #PP.HelpLines(), "  and so does /partout help")
SlashCmdList.PARSEPARTOUT("erreurs")
local lines = newChat()
check(lines[1] and lines[1]:find("aucune erreur", 1, true), "/partout erreurs reports none")
SlashCmdList.PARSEPARTOUT("failures")
lines = newChat()
check(lines[1] and lines[1]:find("aucune erreur", 1, true), "  and so does /partout failures")
SlashCmdList.PARSEPARTOUT("version")
lines = newChat()
check(lines[1] and lines[1]:find("1.60.1.70790", 1, true), "/partout version names the checked build")
check(lines[1] and lines[1]:find("version dev,", 1, true), "a deployed copy reports dev")
SlashCmdList.PARSEPARTOUT("options")
eq(WoW.openedCategory, WoW.categories[1]:GetID(), "/partout options opens the page")

-- A failure recorded anywhere shows up in /partout erreurs.
PP.API.Fail("demo", "boom")
newChat()
SlashCmdList.PARSEPARTOUT("erreurs")
lines = newChat()
check(lines[1] and lines[1]:find("demo: boom", 1, true), "/partout erreurs lists recorded failures")
PP.failures.demo = nil

-- The build warning: at a real login on another build, in a dev build only.
-- Never on /reload.
local realBuild = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "99999", "Nov 9 2026", 16001 end
local function warned()
    for _, l in ipairs(newChat()) do if l:find("n'est pas celui", 1, true) then return true end end
    return false
end
newChat()
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(warned(), "a dev build warns at login on another build")
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(not warned(), "never on /reload")
WoW.addonVersion = "1.2.0"
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(not warned(), "a release never warns")
eq(PP.VersionText(), "1.2.0", "a release shows its version")
WoW.addonVersion = "dev"
GetBuildInfo = realBuild

done("test_boot")
