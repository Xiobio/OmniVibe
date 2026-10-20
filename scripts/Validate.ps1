param(
    [string]$OutputRoot = '',
    [switch]$FullDesktop
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputRoot) { $OutputRoot = Join-Path $projectRoot ('artifacts/validation/' + [guid]::NewGuid().ToString('N')) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$appRoot = Join-Path $OutputRoot 'app'
Push-Location $projectRoot
try {
    & dotnet build src/CodeManager/CodeManager.csproj -c Release -o $appRoot
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
    $suites = @(
        @{ Name = 'reliability'; Language = 'zh-CN' },
        @{ Name = 'localization'; Language = 'en' },
        @{ Name = 'task-status'; Language = 'zh-CN' }
    )
    if ($FullDesktop) { $suites += @{ Name = 'skin'; Language = 'zh-CN' }; $suites += @{ Name = 'self'; Language = 'zh-CN' } }
    $results = @()
    foreach ($suite in $suites) {
        $resultPath = Join-Path $OutputRoot ($suite.Name + '-results.json')
        $process = Start-Process -FilePath (Join-Path $appRoot 'CodeManager.exe') -ArgumentList @(('--' + $suite.Name + '-test'), ('"' + $resultPath + '"'), ('--language=' + $suite.Language)) -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(180000)) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
            throw ("Test timed out: " + $suite.Name)
        }
        $process.Refresh()
        if ($process.ExitCode -ne 0) { throw "Validation failed; inspect $resultPath" }
        $suiteResults = @(([IO.File]::ReadAllText($resultPath) | ConvertFrom-Json) | ForEach-Object { $_ })
        if ($suiteResults.Count -eq 0 -or @($suiteResults | Where-Object { -not $_.Passed }).Count -gt 0) { throw "Empty or failed test report: $resultPath" }
        $results += $suiteResults
    }
    $results | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'results.json')
    & python scripts/monitoring/test_schedule_review.py
    if ($LASTEXITCODE -ne 0) { throw 'Monitoring unit tests failed.' }
    & python tools/release-manifest.py --app $appRoot --output (Join-Path $OutputRoot 'release-manifest.json')
    if ($LASTEXITCODE -ne 0) { throw 'Release resource inventory failed.' }
    Write-Output ("Validated {0} product checks. Evidence: {1}" -f @($results).Count, $OutputRoot)
} finally { Pop-Location }
