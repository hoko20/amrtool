# SandboxExplorer - one-shot GitHub build helper for Windows.
#
#   $env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxxxxxxxxxx"
#   .\Scripts\push_to_github.ps1 -Repo SandboxExplorer -Public
#
# The token needs the classic "repo" AND "workflow" scopes (or fine-grained
# Contents: read/write + Workflows: read/write + Actions: read/write +
# Administration: read/write for repo creation).
#
# Alternative without creating a PAT by hand:
#   winget install --id GitHub.cli
#   gh auth login --scopes "repo,workflow"
#   .\Scripts\push_to_github.ps1 -Repo SandboxExplorer -Public
# github_build.py then reads `gh auth token` automatically.

param(
    [string]$Repo = "SandboxExplorer",
    [switch]$Public,
    [switch]$NoWait,
    [int]$TimeoutMinutes = 45,
    [string]$BundleId = "dev.local.SandboxExplorer",
    [string]$AppGroup = "group.dev.local.SandboxExplorer",
    [string]$DisplayName = "沙盒管家",
    [ValidateSet("adhoc", "unsigned", "signed")]
    [string]$SignMode = "adhoc"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not $env:GITHUB_TOKEN) {
        Write-Host "No GITHUB_TOKEN set - trying the GitHub CLI login token instead ..." -ForegroundColor Yellow
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $gh) {
            Write-Host "ERROR: no credentials. Choose one:" -ForegroundColor Red
            Write-Host "  A) Create a classic PAT at https://github.com/settings/tokens/new" -ForegroundColor Red
            Write-Host "     with BOTH 'repo' and 'workflow' scopes, then:" -ForegroundColor Red
            Write-Host '     $env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxxxxxxxxxx"' -ForegroundColor Red
            Write-Host "  B) winget install --id GitHub.cli ; gh auth login --scopes `"repo,workflow`"" -ForegroundColor Red
            exit 2
        }
        $ghToken = & gh auth token 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $ghToken) {
            Write-Host "ERROR: gh is installed but not logged in." -ForegroundColor Red
            Write-Host '       Run: gh auth login --scopes "repo,workflow"' -ForegroundColor Red
            Write-Host '       Then: gh auth refresh -h github.com -s workflow  (if workflow scope is missing)' -ForegroundColor Red
            exit 2
        }
        $env:GITHUB_TOKEN = $ghToken.Trim()
        Write-Host "Using the GitHub CLI login token." -ForegroundColor Green
    }
    $pyArgs = @(
        (Join-Path $PSScriptRoot "github_build.py"),
        "--repo", $Repo,
        "--timeout", $TimeoutMinutes,
        "--bundle-id", $BundleId,
        "--app-group", $AppGroup,
        "--display-name", $DisplayName,
        "--sign-mode", $SignMode
    )
    if ($Public) { $pyArgs += "--public" }
    if ($NoWait) { $pyArgs += "--no-wait" }
    python @pyArgs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
