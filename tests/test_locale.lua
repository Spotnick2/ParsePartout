-- The language: French first, English supported. "auto" follows the client
-- (frFR -> French, anything else -> English); "fr" / "en" force one, from
-- /partout langue or the options page, and every open text follows at once.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local PP = loadAddon()
local S = PP.Locale.STRINGS

-- Every key exists in both languages, as a non-empty string, with the same
-- format specifiers in the same order.
local function specs(s)
    local out = {}
    for spec in s:gmatch("%%[%-%d%.]*%a") do out[#out + 1] = spec end
    return table.concat(out, " ")
end
for _, pair in ipairs({ { "fr", "en" }, { "en", "fr" } }) do
    local a, b = pair[1], pair[2]
    for key, text in pairs(S[a]) do
        check(type(S[b][key]) == "string" and S[b][key] ~= "", key .. " exists in " .. b)
        if S[b][key] then eq(specs(S[b][key]), specs(text), key .. ": the same format specifiers") end
    end
end
-- No stray "|" in any string: the client reads it as an escape.
for lang, t in pairs(S) do
    for key, text in pairs(t) do
        check(not text:find("|", 1, true), lang .. "." .. key .. " has no stray |")
    end
end

-- auto: the client's locale.
eq(PP.db.language, "auto", "auto by default")
WoW.locale = "frFR"
eq(PP.Locale.Current(), "fr", "a French client gets French")
WoW.locale = "enUS"
eq(PP.Locale.Current(), "en", "an English client gets English")
WoW.locale = "deDE"
eq(PP.Locale.Current(), "en", "any other client gets English")
WoW.locale = "frFR"

-- A missing key falls back to French, then to the key.
S.en.ONLY_FR, S.fr.ONLY_FR = nil, "seulement en français"
SlashCmdList.PARSEPARTOUT("language en")
eq(PP.L("ONLY_FR"), "seulement en français", "a key missing in English falls back to French")
eq(PP.L("NO_SUCH_KEY"), "NO_SUCH_KEY", "an unknown key shows itself")
S.fr.ONLY_FR = nil

-- /partout langue: forces a language, open texts follow, the choice is saved.
newChat()
SlashCmdList.PARSEPARTOUT("")
local w = PP.Window._test.frame()
check(w.body:GetText():find("The guild's addon", 1, true), "forced English on a French client")
eq(rawget(ParsePartoutDB, "language"), "en", "the choice is saved")
SlashCmdList.PARSEPARTOUT("langue fr")
check(w.body:GetText():find("L'addon de la guilde", 1, true), "the open window turns French at once")
local lines = newChat()
check(lines[#lines]:find("langue : Français", 1, true), "/partout langue fr says so, in French")
SlashCmdList.PARSEPARTOUT("langue klingon")
lines = newChat()
check(lines[1]:find("/partout langue auto/fr/en", 1, true), "a bad choice shows the usage")
eq(PP.db.language, "fr", "  and changes nothing")
SlashCmdList.PARSEPARTOUT("langue auto")
eq(rawget(ParsePartoutDB, "language"), "auto", "auto set by hand is kept this session")

-- The options page's radios: the page itself changes language.
PP.Options._test.panel:Show()
local radios = PP.Options._test.languageRadios
eq(#radios, 3, "three language choices")
for _, rb in ipairs(radios) do
    if rb.value == "en" then rb:GetScript("OnClick")(rb) end
end
eq(PP.db.language, "en", "the English radio sets English")
for _, rb in ipairs(radios) do
    eq(rb:GetChecked(), rb.value == "en", "  only it is checked (" .. rb.value .. ")")
end
eq(PP.Options._test.open:GetText(), "Open the window", "the page turned English")
check(w.body:GetText():find("The guild's addon", 1, true), "  and so did the window")

done("test_locale")
