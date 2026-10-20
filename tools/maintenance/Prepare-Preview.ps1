param([string]$OutputRoot = '')
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $OutputRoot) { $OutputRoot = Join-Path $workspace ('artifacts/release-candidates/' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if ((Test-Path -LiteralPath $OutputRoot) -and @(Get-ChildItem -LiteralPath $OutputRoot -Force).Count) { throw 'Use a new or empty output directory.' }
Push-Location $workspace
try {
    & (Join-Path $PSScriptRoot 'Publish-Lean.ps1') -OutputRoot $OutputRoot -Runtime win-x64
    $appRoot = Join-Path $OutputRoot 'app'
    Copy-Item -LiteralPath (Join-Path $workspace 'docs/project-kit/INSTALL.md') -Destination (Join-Path $appRoot 'INSTALL.md')
    Copy-Item -LiteralPath (Join-Path $workspace 'CHANGELOG.md') -Destination (Join-Path $appRoot 'CHANGELOG.md')
    # Inventory after adding user-facing documentation.
    & python tools/release-manifest.py --app $appRoot --output (Join-Path $OutputRoot 'release-manifest.json')
    if ($LASTEXITCODE -ne 0) { throw 'Inventory failed.' }
    $archive = Join-Path $OutputRoot 'OmniVibe-local-review-win-x64.zip'
    Compress-Archive -Path (Join-Path $appRoot '*') -DestinationPath $archive -CompressionLevel Optimal
    $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'SHA256SUMS.txt'), "$digest  $([IO.Path]::GetFileName($archive))`n")
    $commit = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
    $changes = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source status.' }
    [pscustomobject]@{
        Kind = 'local-review-only'; PublicReleaseApproved = $false
        BaseCommit = "$commit"; DirtyWorktree = ($changes.Count -gt 0)
        Runtime = 'win-x64'; FrameworkDependent = $true
        RequiredRuntime = '.NET 10 Windows Desktop Runtime x64'
        Archive = [IO.Path]::GetFileName($archive); SHA256 = $digest
        RemainingGates = @('asset redistribution review','history and screenshot privacy review','clean Windows acceptance','fixed source commit and remote CI')
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'candidate.json')
    Write-Output ("Local review candidate only: " + $archive)
} finally { Pop-Location }
