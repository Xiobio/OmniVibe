param(
    [string]$OutputRoot = '',
    [ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64'
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $OutputRoot) { $OutputRoot = Join-Path $workspace ('artifacts/publish/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if ((Test-Path -LiteralPath $OutputRoot) -and @(Get-ChildItem -LiteralPath $OutputRoot -Force).Count) { throw 'Use a new or empty output directory so obsolete files cannot leak into the package.' }
$appRoot = Join-Path $OutputRoot 'app'
Push-Location $workspace
try {
    & dotnet publish src/CodeManager/CodeManager.csproj -c Release -r $Runtime --no-self-contained -p:RuntimeAssetsOnly=true -p:DebugType=None -p:DebugSymbols=false -o $appRoot
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
    & python tools/release-manifest.py --app $appRoot --output (Join-Path $OutputRoot 'release-manifest.json')
    if ($LASTEXITCODE -ne 0) { throw 'Resource inventory failed.' }
    Write-Output ("Published framework-dependent Windows application: " + $appRoot)
} finally { Pop-Location }
