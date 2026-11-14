# Publishes one app release to the catalog in one step: swaps the package in packages\, updates
# apps\<app>.json (version, url, sha256, size, notes, date), signs dist\index.json, commits,
# pushes, and waits until GitHub Pages serves it.
#
#   .\tools\publish.ps1 -App retrofox -Package <path to .appx/.xap> -Version 0.3.14.0 -Notes "What changed, in plain words."
#
# Apps: app-loader (Unesbrews, .xap), retrobird (.appx), retrofox (.appx), file-explorer (.xap).
# The signing key stays outside the repo (default C:\rfx\keys\wp-homebrew.pem).
param(
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Package,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Notes,
    [string]$Key = "C:\rfx\keys\wp-homebrew.pem",
    [string]$CatalogTool = "C:\rfx\wp-loader\app-loader\catalog\tools\catalog.py",
    [switch]$NoPush
)
# "Continue": git writes harmless warnings (line endings) to stderr, which "Stop" would turn into
# errors in Windows PowerShell 5; failures are caught with $LASTEXITCODE checks instead
$ErrorActionPreference = "Continue"
function RunGit { & git.exe @args 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch "LF will be replaced|CRLF will be replaced" }; if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)" } }
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo

$appFile = "apps\$App.json"
if (-not (Test-Path $appFile)) { throw "No $appFile (known: $((Get-ChildItem apps\*.json).BaseName -join ', '))" }
if (-not (Test-Path $Package)) { throw "No package at $Package" }
foreach ($need in @($Key, $CatalogTool)) { if (-not (Test-Path $need)) { throw "Missing $need" } }

RunGit pull -q --ff-only
$raw = Get-Content $appFile -Raw
$r = ($raw | ConvertFrom-Json).releases[0]
if ($r.version -eq $Version) { throw "$App $Version is already the catalog's release" }

# Same naming as before: the old file name with the old version replaced by the new one
$oldName = Split-Path $r.url -Leaf
$newName = $oldName.Replace($r.version, $Version)
if ($newName -eq $oldName) { throw "Can't derive the new file name from $oldName" }
$sha = (Get-FileHash $Package -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $Package).Length
$newUrl = $r.url.Replace($oldName, $newName)
$today = Get-Date -Format "yyyy-MM-dd"

$raw = $raw.Replace('"version": "' + $r.version + '"', '"version": "' + $Version + '"').
            Replace($r.url, $newUrl).
            Replace($r.sha256, $sha).
            Replace('"size": ' + $r.size + ',', '"size": ' + $size + ',').
            Replace('"added": "' + $r.added + '"', '"added": "' + $today + '"')
if ($r.notes) { $raw = $raw.Replace('"notes": ' + ($r.notes | ConvertTo-Json), '"notes": ' + ($Notes | ConvertTo-Json)) }
Set-Content $appFile $raw -NoNewline

# Check the result before anything is signed
$n = (Get-Content $appFile -Raw | ConvertFrom-Json).releases[0]
if ($n.version -ne $Version -or $n.sha256 -ne $sha -or $n.size -ne $size -or $n.url -ne $newUrl -or $n.notes -ne $Notes) {
    RunGit checkout -- $appFile
    throw "Updating $appFile didn't come out right; left unchanged"
}

if (Test-Path "packages\$oldName") { git mv "packages\$oldName" "packages\$newName" }
Copy-Item $Package "packages\$newName" -Force
python -I $CatalogTool build --key $Key --app-dir apps --out dist
if ($LASTEXITCODE -ne 0) { throw "Signing the index failed" }
RunGit add apps dist packages

$msg = Join-Path $env:TEMP "wp-homebrew-msg.txt"
"$App $Version`n`n$Notes`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" | Set-Content $msg
RunGit commit -q -F $msg
if ($NoPush) { Write-Host "Committed, not pushed (-NoPush)."; return }
RunGit push -q
if ($LASTEXITCODE -ne 0) { throw "Push failed" }

# Live once GitHub Pages serves the new index
$deadline = (Get-Date).AddMinutes(5)
do {
    Start-Sleep 10
    $index = try { (Invoke-WebRequest "https://younes-mirzaie.github.io/wp-homebrew/dist/index.json?t=$([DateTime]::Now.Ticks)" -UseBasicParsing -TimeoutSec 20).Content } catch { "" }
} until ($index.Contains($Version) -or (Get-Date) -gt $deadline)
if ($index.Contains($Version)) { Write-Host "Live: $App $Version" -ForegroundColor Green }
else { Write-Host "Pushed; GitHub Pages hasn't served $Version yet (check in a few minutes)." -ForegroundColor Yellow }
