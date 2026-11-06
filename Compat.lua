-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- ParsePartout.API. Nothing is injected into _G.
--
-- A subset of GlassMail's Compat.lua (itself from GlassChat's, same measured
-- rules); lift more from there when needed rather than rewriting.

ParsePartout = ParsePartout or {}
local PP = ParsePartout
local API = {}
PP.API = API

-- The build this addon was last checked on in game. Bump only after checking
-- again; tests/test_toc.lua pins the same literal. Nothing measured yet: the
-- scaffold targets the newest API dump's build.
PP.MEASURED_ON_BUILD = "1.60.1.70790"

function API.Print(msg)
    print("|cffe8b03aParse Partout|r " .. msg)
end

-- True for a secret value. Such a value may be handed back to the client
-- (SetText) but never compared, concatenated, tostring'd, pattern-matched or
-- truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
PP.eventFailures = {}

local function report(name, why)
    table.insert(PP.eventFailures, name .. ": " .. why)
    -- Locale.lua loads after this file; registrations happen once it has.
    local text = PP.L and PP.L("COULD_NOT_REGISTER") or "could not register"
    API.Print("|cffff6060" .. text .. "|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

-- The one place failures are recorded (first error per key), read by
-- /partout failures and the tests.
PP.failures = PP.failures or {}
function API.Fail(key, err)
    if PP.failures[key] == nil then PP.failures[key] = tostring(err) end
end

-- A frame from a template, and whether the template really applied: a missing
-- template doesn't throw, it returns a bare frame, so `proof` names a field
-- the template makes (GlassUnitFrames' API.SafeFrame, via GlassMail).
function API.SafeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

-- An addon's TOC Version, or nil (absent API, error, secret, not a string).
function API.AddOnVersion(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end
