<#
.SYNOPSIS
  Prepare the GitHub Actions secrets for sign_mode=signed (build an installable
  IPA directly on GitHub, with App Group entitlements written into the signature).

.DESCRIPTION
  Reads a local .p12 + .mobileprovision, validates that the provisioning profile
  really enables the App Group, base64-encodes both files and either sets the
  repository secrets through `gh` or prints them for manual pasting.

.EXAMPLE
  .\Scripts\setup_signing_secrets.ps1 `
      -P12Path "C:\certs\ios_dev.p12" -P12Password "..." `
      -ProvisionPath "C:\certs\SandboxExplorer.mobileprovision" `
      -TeamId "ABCDE12345" -Repo "hoko20/SandboxExplorer" -SetSecrets

.NOTES
  Without -SetSecrets nothing is uploaded; the script only prints a summary and
  writes the base64 strings to Scripts/.secrets/ (gitignored) for manual paste.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $P12Path,
    [Parameter(Mandatory = $true)][string] $P12Password,
    [Parameter(Mandatory = $true)][string] $ProvisionPath,
    [Parameter(Mandatory = $true)][string] $TeamId,
    [string] $Repo = "hoko20/SandboxExplorer",
    [string] $AppGroup = "group.dev.local.SandboxExplorer",
    [string] $BundleId = "dev.local.SandboxExplorer",
    [switch] $SetSecrets
)

$ErrorActionPreference = "Stop"

foreach ($f in @($P12Path, $ProvisionPath)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "File not found: $f" }
}

$p12Bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $P12Path))
$provBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ProvisionPath))
$p12B64 = [Convert]::ToBase64String($p12Bytes)
$provB64 = [Convert]::ToBase64String($provBytes)

# The plist inside a .mobileprovision CMS blob is stored as plain XML, so the
# capability keys are visible as literal strings. This is a pre-flight check,
# not a signature verification.
$provText = [Text.Encoding]::GetEncoding("iso-8859-1").GetString($provBytes)
$hasCapability = $provText.Contains("com.apple.security.application-groups")
$hasGroup = $provText.Contains($AppGroup)
$hasBundle = $provText.Contains($BundleId)
$appIdMatch = [regex]::Match($provText, "<key>application-identifier</key>\s*<string>([A-Z0-9]+)\.")
$profileTeam = if ($appIdMatch.Success) { $appIdMatch.Groups[1].Value } else { "" }

Write-Host "=== Provisioning profile pre-flight ===" -ForegroundColor Cyan
Write-Host ("  file bytes          : {0}" -f $provBytes.Length)
Write-Host ("  App Groups capability: {0}" -f $(if ($hasCapability) { "present" } else { "MISSING" }))
Write-Host ("  exact group id       : {0}" -f $(if ($hasGroup) { "present" } else { "MISSING" }))
Write-Host ("  bundle id string     : {0}" -f $(if ($hasBundle) { "present" } else { "MISSING" }))
Write-Host ("  profile team id      : {0}" -f $(if ($profileTeam) { $profileTeam } else { "(not detected)" }))
Write-Host ("  -TeamId supplied     : {0}" -f $TeamId)

if ($profileTeam -and $profileTeam -ne $TeamId) {
    throw "TeamId '$TeamId' does not match the profile's team '$profileTeam'. Use -TeamId $profileTeam."
}
if (-not $hasGroup -or -not $hasCapability) {
    throw @"
The provisioning profile does NOT authorise '$AppGroup'.
Fix it at https://developer.apple.com/account/resources/identifiers :
  1. open the App ID matching '$BundleId'
  2. enable the 'App Groups' capability and add exactly '$AppGroup'
  3. regenerate/download the Development or Ad Hoc provisioning profile
Then re-run this script. A profile without the group produces an IPA whose
entitlements are stripped, and container access will return -1.
"@
}

$randomBytes = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($randomBytes)
$keychainPassword = [Convert]::ToBase64String($randomBytes)

$secrets = [ordered]@{
    "IOS_P12_BASE64"                = $p12B64
    "IOS_P12_PASSWORD"              = $P12Password
    "IOS_PROVISION_PROFILE_BASE64"  = $provB64
    "IOS_TEAM_ID"                   = $TeamId
    "KEYCHAIN_PASSWORD"             = $keychainPassword
}

$outDir = Join-Path $PSScriptRoot ".secrets"
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
foreach ($name in $secrets.Keys) {
    $path = Join-Path $outDir "$name.txt"
    [IO.File]::WriteAllText($path, $secrets[$name], (New-Object Text.UTF8Encoding($false)))
}

Write-Host ""
Write-Host "=== Secret payloads (never printed in full) ===" -ForegroundColor Cyan
foreach ($name in $secrets.Keys) {
    Write-Host ("  {0,-32} {1,8} chars  ->  Scripts\.secrets\{0}.txt" -f $name, $secrets[$name].Length)
}

if ($SetSecrets) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { throw "gh CLI not found. Install it (winget install --id GitHub.cli) or omit -SetSecrets and paste manually." }
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "gh is not logged in. Run: gh auth login --scopes `"repo,workflow`"" }

    Write-Host ""
    Write-Host "=== Setting repository secrets on $Repo ===" -ForegroundColor Cyan
    foreach ($name in $secrets.Keys) {
        # stdin avoids putting large base64 blobs / passwords on the command line
        $secrets[$name] | & gh secret set $name --repo $Repo
        if ($LASTEXITCODE -ne 0) { throw "Failed to set secret $name" }
        Write-Host "  set $name"
    }
    Write-Host ""
    Write-Host "Done. Now run:" -ForegroundColor Green
    Write-Host "  Actions -> Build SandboxExplorer IPA -> Run workflow -> sign_mode = signed"
} else {
    Write-Host ""
    Write-Host "Manual path: open" -ForegroundColor Yellow
    Write-Host "  https://github.com/$Repo/settings/secrets/actions"
    Write-Host "and paste the contents of each Scripts\.secrets\<NAME>.txt into the matching secret."
    Write-Host "Or re-run this script with -SetSecrets (requires gh auth login)."
}
