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
      4. downloads the password-protected AyuGram archive into .\out and extracts AyuGram.ipa with 7-Zip.

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

# Wait until no build job is running (a build may continue over several jobs), then take the newest
# encrypted IPA artifact.
Write-Host "Waiting for the build (this takes hours; you can close this window and run the script with -NoWait later)..."
while ($true) {
    Start-Sleep -Seconds 300
    $running = gh run list --repo $Repo --workflow build.yml --limit 10 --json status --jq '[.[] | select(.status != "completed")] | length'
    if ($running -ne "0") { continue }
    $runs = gh run list --repo $Repo --workflow build.yml --status success --limit 5 --json databaseId,createdAt | ConvertFrom-Json
    $run = $runs | Where-Object { [DateTime]::Parse($_.createdAt).ToUniversalTime() -gt $started.AddMinutes(-1) } | Select-Object -First 1
    if (-not $run) {
        $last = gh run list --repo $Repo --workflow build.yml --limit 1 --json conclusion,url | ConvertFrom-Json
        Fail "The build did not succeed. Last run: $($last[0].conclusion) $($last[0].url)"
    }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    gh run download $run.databaseId --repo $Repo --name AyuGram-encrypted --dir $OutDir
    $archive = Get-ChildItem -Path $OutDir -Filter "AyuGram-*.7z" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $archive) { Fail "The encrypted IPA was not found in run $($run.databaseId)" }
    $sevenZip = @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $sevenZip) {
        Write-Host "Downloaded $($archive.FullName). Install 7-Zip (winget install 7zip.7zip) and open it with your IPA_PASSWORD." -ForegroundColor Yellow
        exit 0
    }
    & $sevenZip x $archive.FullName "-o$OutDir" -y
    if ($LASTEXITCODE -ne 0) { Fail "Could not extract the archive (wrong password?)" }
    $ipa = Join-Path $OutDir "AyuGram.ipa"
    Write-Host ("Done: {0} ({1} MB). Install it with SideStore (see ayugram/INSTALL.md)." -f $ipa, [math]::Round((Get-Item $ipa).Length / 1MB, 1)) -ForegroundColor Green
    exit 0
}
