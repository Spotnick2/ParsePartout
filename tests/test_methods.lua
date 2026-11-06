-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- exercises the addon, then Kit.checkMethods checks each recorded
-- "Type:Method" pair against the pinned build's widget methods. It fails,
-- never skips, when the data is missing or nothing was recorded.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Exercise everything so every method is recorded.
local PP = loadAddon()
WoW.fireAllRegistered()
WoW.tick()
PP.Options._test.panel:Show()
for _, cmd in ipairs({ "", "", "help", "failures", "version", "options" }) do
    SlashCmdList.PARSEPARTOUT(cmd)
end

local recorded = Kit.checkMethods()
-- What loading plus the exercise records today, rounded down: the exercise
-- can't quietly shrink.
check(recorded >= 55, "the exercise reached the window (" .. recorded .. " recorded)")
done("test_methods")
