$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'src\CodeManager\CodeManager.csproj'
$outputPath = Join-Path $PSScriptRoot 'src\CodeManager\bin\Debug\net10.0-windows'
$applicationPath = Join-Path $outputPath 'CodeManager.exe'
# A running development executable is locked. Request its normal cleanup before building.
if ((Test-Path -LiteralPath $applicationPath) -and (Get-Process CodeManager -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $applicationPath -ArgumentList '--quit' -Wait -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ((Get-Process CodeManager -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if (Get-Process CodeManager -ErrorAction SilentlyContinue) { throw 'An older CodeManager is still running. Exit it from its tray menu before rebuilding.' }
}
dotnet build $projectPath -c Debug
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
Start-Process -FilePath $applicationPath -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
