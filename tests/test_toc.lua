-- The manifest, the pinned build and the embedded material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Interface 16001, the version token, every listed .lua file exists and every
-- line is listed once (the library's XML line too).
Kit.checkToc(TOC)
local toc = io.open(TOC):read("*a")
check(toc:find("## SavedVariables: ParsePartoutDB", 1, true), "saved variables declared")
-- The publishers read this from the packaged TOC: CurseForge's webhook
-- (RELEASING.md section 1). A wrong ID uploads to another project.
check(toc:find("\n## X%-Curse%-Project%-ID: 1787925\r?\n"), "the CurseForge project ID")
-- The icon is our own texture, and it ships (deploy and the CI allowlist take Media\*.tga).
check(toc:find("\n## IconTexture: Interface\\AddOns\\ParsePartout\\Media\\Logo%s*\n"), "the logo is the TOC icon")
check(io.open("Media/Logo.tga", "rb") ~= nil, "Media/Logo.tga exists")
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
eq(tocFiles()[#tocFiles()], "ParsePartout.lua", "the bootstrap loads last")

-- Two places that must agree, never derived from each other (porting guide section 0).
loadAddon()
eq(ParsePartout.MEASURED_ON_BUILD, "1.60.1.70790", "MEASURED_ON_BUILD")

-- Every texture the material names ships with the library.
local root = libGlassRoot()
for size, S in pairs(ParsePartout.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        if S[key] then
            local f = root .. "/Media/" .. S[key] .. ".tga"
            check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
        end
    end
end
-- The Pearl material (LibGlass r11), and MEDIA points into the embedded copy,
-- where the packager puts it.
eq(ParsePartout.Glass.preset, "pearl", "the Pearl material")
eq(ParsePartout.Glass.MEDIA, "Interface\\AddOns\\ParsePartout\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
for _, k in ipairs({ "Apply", "Font", "Inset", "ContentLevel" }) do
    check(ParsePartout.Glass[k] ~= nil, "the instance has Glass." .. k)
end

done("test_toc")
