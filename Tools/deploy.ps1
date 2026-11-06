<#
    deploy.ps1 - Copy Parse Partout into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    The glass material is the embedded LibGlass-1.0. The packager fetches it
    into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev copy this script
    hands that job to the LibGlass checkout's own deploy.ps1, which checks the
    checkout, copies only the shipped files and prints its commit. The checkout
    is $env:LIBGLASS, else ..\LibGlass. (GlassMail's deploy, without a probe.)

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_forever_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

. (Join-Path $PSScriptRoot "LibGlassPin.ps1")
$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }

$dest = Join-Path $AddOnsPath "ParsePartout"
if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
    Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
    exit 1
}
Write-LibGlassPinStatus $RepoRoot $LibGlass "this deploy tests a library the release won't ship"
# The library first: its deploy checks the checkout and may refuse, and a
# refusal must leave the deployed addon as it was.
& pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon ParsePartout -AddOnsPath $AddOnsPath
if ($LASTEXITCODE -ne 0) { Write-Error "LibGlass deploy refused; ParsePartout was not touched"; exit 1 }

Write-Host "Deploying ParsePartout -> $dest" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dest | Out-Null
# The TOC is the list of what ships (subfolders included).
$lua = @(Get-Content -LiteralPath (Join-Path $RepoRoot "ParsePartout.toc") | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" })
# Our own textures ship too (Media\*.tga).
$media = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -Filter *.tga -File -ErrorAction SilentlyContinue |
    ForEach-Object { "Media\" + $_.Name })
$files = @("ParsePartout.toc", "LICENSE") + $lua + $media
foreach ($f in $files) {
    $src = Join-Path $RepoRoot $f
    $to = Join-Path $dest $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    if ($f -like "*.toc") {
        (Get-Content -LiteralPath $src -Raw) -replace '## Version: @project-version@', '## Version: dev' |
            Set-Content -LiteralPath $to -NoNewline
    } else {
        Copy-Item -LiteralPath $src -Destination $to -Force
    }
    Write-Host "  $f"
}
# A file removed from the repo must not linger where the client finds it.
$keep = $files | ForEach-Object { $_.Replace("/", "\") }
Get-ChildItem -LiteralPath $dest -File -Recurse | Where-Object { $_.FullName -notlike (Join-Path $dest "Libs\*") } |
    ForEach-Object {
        $rel = $_.FullName.Substring($dest.Length + 1)
        if ($keep -notcontains $rel) {
            Write-Host "  removing stale $rel" -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }

Write-Host ""
Write-Host "/reload is enough, a brand-new addon folder included; restart the client only for new textures." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /partout   (/partout aide for the commands)" -ForegroundColor Green
