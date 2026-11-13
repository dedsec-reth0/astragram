<#
.SYNOPSIS
    Builds AyuGram.ipa (the official Telegram app with AyuGram features) on GitHub Actions and downloads it.

.DESCRIPTION
    Windows cannot compile iOS apps, so the build runs on a GitHub-hosted macOS runner with Xcode
    (.github/workflows/build.yml). A full build takes several hours; when one job runs out of time the
    workflow saves its cache and starts the next job itself. This script:
      1. checks the GitHub CLI and your login,
      2. optionally stores your Telegram API ID / API hash as repository secrets,
      3. starts the workflow and waits until an IPA is published,
      4. downloads AyuGram.ipa into .\out and checks it.

.EXAMPLE
    .\ayugram\scripts\build.ps1 -SetSecrets
    .\ayugram\scripts\build.ps1
    .\ayugram\scripts\build.ps1 -NoWait
#>
param(
    [string]$Repo = "",
    [string]$Ref = "master",
    [switch]$SetSecrets,
    [switch]$NoWait,
    [string]$OutDir = (Join-Path (Get-Location) "out")
)

$ErrorActionPreference = "Stop"

function Fail($message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "GitHub CLI is not installed. Install it with: winget install --id GitHub.cli"
}
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Not logged in to GitHub. Run: gh auth login" }

if ($Repo -eq "") {
    $origin = git remote get-url origin 2>$null
    if ($origin -match "github\.com[:/](.+?)(\.git)?$") { $Repo = $Matches[1] } else { Fail "Cannot detect the repository; pass -Repo owner/name" }
}
Write-Host "Repository: $Repo  ref: $Ref"

if ($SetSecrets) {
    Write-Host "Get your api_id and api_hash at https://my.telegram.org -> API development tools."
    $apiId = Read-Host "Telegram API ID (digits)"
    if ($apiId -notmatch '^\d+$') { Fail "API ID must be digits" }
    $apiHashSecure = Read-Host "Telegram API hash (32 hex characters)" -AsSecureString
    $apiHash = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiHashSecure))
    if ($apiHash -notmatch '^[0-9a-fA-F]{32}$') { Fail "API hash must be 32 hex characters" }
    $apiId | gh secret set TELEGRAM_API_ID --repo $Repo
    $apiHash | gh secret set TELEGRAM_API_HASH --repo $Repo
    Remove-Variable apiHash
    Write-Host "Secrets saved in $Repo." -ForegroundColor Green
}

$started = (Get-Date).ToUniversalTime()
gh workflow run build.yml --repo $Repo --ref $Ref -f configuration=release_arm64
if ($LASTEXITCODE -ne 0) { Fail "Could not start the workflow" }
Write-Host "Build started: https://github.com/$Repo/actions"
if ($NoWait) { exit 0 }

# Wait for a release newer than the start (the build may continue over several jobs).
Write-Host "Waiting for the IPA (this takes hours; you can close this window and run the script with -NoWait later)..."
while ($true) {
    Start-Sleep -Seconds 300
    $release = gh release list --repo $Repo --limit 1 --json tagName,createdAt | ConvertFrom-Json
    if ($release -and [DateTime]::Parse($release[0].createdAt).ToUniversalTime() -gt $started) {
        New-Item -ItemType Directory -Force $OutDir | Out-Null
        gh release download $release[0].tagName --repo $Repo --pattern "AyuGram.ipa" --dir $OutDir --clobber
        $ipa = Join-Path $OutDir "AyuGram.ipa"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ipa)
        $ok = $zip.Entries | Where-Object { $_.FullName -match '^Payload/[^/]+\.app/Info\.plist$' }
        $zip.Dispose()
        if (-not $ok) { Fail "$ipa is not a valid IPA" }
        Write-Host ("Done: {0} ({1} MB). Install it with SideStore (see ayugram/INSTALL.md)." -f $ipa, [math]::Round((Get-Item $ipa).Length / 1MB, 1)) -ForegroundColor Green
        exit 0
    }
    $running = gh run list --repo $Repo --workflow build.yml --limit 5 --json status --jq '[.[] | select(.status != "completed")] | length'
    if ($running -eq "0") {
        $last = gh run list --repo $Repo --workflow build.yml --limit 1 --json conclusion,url | ConvertFrom-Json
        Fail "No build is running and no new release was published. Last run: $($last[0].conclusion) $($last[0].url)"
    }
}
