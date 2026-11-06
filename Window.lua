-- Window.lua: the guild's main window, a glass panel opened with /partout.
-- Empty for now: each feature adds its own section here as it lands.
--
-- Built on first open, never at load. Movable by its title, closed with Esc
-- (UISpecialFrames, which needs a named frame) or its close button.

ParsePartout = ParsePartout or {}
local PP = ParsePartout
local Window = {}
PP.Window = Window

local WIDTH, HEIGHT = 360, 180
local FRAME_NAME = "ParsePartoutWindow"
local LOGO = "Interface\\AddOns\\ParsePartout\\Media\\Logo"

local frame

local function build()
    local Glass = PP.Glass
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    table.insert(UISpecialFrames, FRAME_NAME)

    f.glass = Glass.Apply(f, "large")
    local inset = Glass.Inset("large")
    local level = Glass.ContentLevel(f)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", inset + 8, -(inset + 6))
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(inset + 8), inset + 6)
    content:SetFrameLevel(level)
    f.content = content

    -- The guild's emblem (Media\Logo.tga, from docs/images/logo.png).
    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(28, 28)
    logo:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    logo:SetTexture(LOGO)
    f.logo = logo

    local title = Glass.Font(content, 16, "LEFT")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("|cffe8b03aParse|r Partout")
    f.title = title

    local body = Glass.Font(content, 12, "LEFT")
    body:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    f.body = body
    -- Every text re-read on every show: the language can change meanwhile.
    f:SetScript("OnShow", Window.Refresh)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetFrameLevel(level + 1)
    f.close = close

    return f
end

-- The texts in the current language; the language setting calls it too.
function Window.Refresh()
    if not frame then return end
    frame.body:SetText(PP.L("WINDOW_BODY"))
end

function Window.Get()
    if not frame then frame = build() end
    return frame
end

function Window.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Window.Show() Window.Get():Show() end

function Window.Hide()
    if frame then frame:Hide() end
end

function Window.Toggle()
    if Window.IsShown() then Window.Hide() else Window.Show() end
end

Window._test = { FRAME_NAME = FRAME_NAME, frame = function() return frame end }
