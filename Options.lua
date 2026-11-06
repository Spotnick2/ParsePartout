-- Options.lua: the page in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- a plain Frame with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value AND every text re-read on
-- every OnShow (the language can change), registered once at PLAYER_LOGIN
-- from ParsePartout.lua.
--
-- The version, the language, a button to the window; each feature adds its own
-- controls here as it lands. Choices are radio groups, not dropdowns (the
-- porting guide's measured recipe; the helpers are GlassMail's).

ParsePartout = ParsePartout or {}
local PP = ParsePartout
local API = PP.API
local L = function(...) return PP.L(...) end
local Options = {}
PP.Options = Options

local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

local panel = CreateFrame("Frame")
panel.name = "Parse Partout"
panel:Hide()

local category
local refreshers = {}

-- A label whose text is a locale key (re-read on every show) or a literal.
local function label(parent, key, font, literal)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    if literal then
        fs:SetText(key)
    else
        refreshers[#refreshers + 1] = function() fs:SetText(L(key)) end
    end
    return fs
end

-- A labelled radio button: UIRadioButtonTemplate when the client has it (its
-- own label, rb.text, takes the text), else the client's own radio art and a
-- label of ours. Returns the button and its label.
local function radioButton(parent)
    local rb, templated = API.SafeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if templated then
        rb.text:SetFontObject("GameFontHighlight")
        return rb, rb.text
    end
    rb:SetSize(16, 16)
    rb:SetNormalTexture(RADIO_ART)
    rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    rb:SetCheckedTexture(RADIO_ART)
    rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    rb:SetHighlightTexture(RADIO_ART)
    rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    rb:GetHighlightTexture():SetBlendMode("ADD")   -- as the template's (CheckButtonTemplates.xml:18)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    return rb, fs
end

-- Mutually exclusive choices, stacked under `anchor`: { {value, localeKey}, ... }.
-- Returns the last button, to anchor what follows. The whole group re-syncs
-- after a click, so a refused choice snaps back.
local function radios(parent, anchor, options, get, set)
    local group = {}
    local function sync()
        local current = get()
        for _, rb in ipairs(group) do
            rb:SetChecked(rb.value == current)
            rb.label:SetText(L(rb.key))
        end
    end
    local prev = anchor
    for _, o in ipairs(options) do
        local rb, fs = radioButton(parent)
        rb.value, rb.key, rb.label = o[1], o[2], fs
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        rb:SetScript("OnClick", function() set(o[1]); sync() end)
        group[#group + 1] = rb
        prev = rb
    end
    refreshers[#refreshers + 1] = sync
    return prev, group
end

local function build()
    local title = label(panel, "|cffe8b03aParse|r Partout", "GameFontNormalHuge", true)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    refreshers[#refreshers + 1] = function() version:SetText(L("OPTIONS_VERSION", PP.VersionText())) end

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 22)
    open:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    open:SetScript("OnClick", function() PP.Window.Show() end)
    refreshers[#refreshers + 1] = function() open:SetText(L("OPTIONS_OPEN")) end
    Options._test.open = open

    local language = label(panel, "OPTIONS_LANGUAGE", "GameFontNormal")
    language:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -16)
    local choices = {}
    for _, v in ipairs(PP.Locale.LANGUAGES) do choices[#choices + 1] = { v, "LANGUAGE_" .. v } end
    local last, group = radios(panel, language, choices, function() return PP.db.language end,
        function(v)
            PP.Settings.SetLanguage(v)
            Options.Refresh()   -- the page itself changes language
        end)
    Options._test.languageRadios = group

    local hint = label(panel, "OPTIONS_HINT", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
end

function Options.Refresh()
    if not Options.built then return end
    for _, refresh in ipairs(refreshers) do refresh() end
end

panel:SetScript("OnShow", function()
    if not Options.built then
        Options.built = true
        build()
    end
    Options.Refresh()
end)

-- Called once at PLAYER_LOGIN by ParsePartout.lua.
function Options.Register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

Options._test = { panel = panel, refreshers = refreshers }
