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

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ ParsePartout = true, ParsePartoutDB = true, LibStub = true })
