[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path.TrimEnd('\')
$artifactRoot = Join-Path $workspace 'artifacts'
$toolRoot = Join-Path $workspace 'tools'
$reportRoot = Join-Path $artifactRoot 'maintenance'
$keep = @('artifacts/reliability/ci/app', 'artifacts/empty-dock/app', 'artifacts/signature-completion/app', 'artifacts/skin-monitor', 'artifacts/publish') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $workspace $_)).TrimEnd('\') }
function Active-Executables {
    @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath } | ForEach-Object { [IO.Path]::GetFullPath($_.ExecutablePath) })
}
function Check-Target([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    if (-not ($resolved.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $resolved.StartsWith($toolRoot + '\', [StringComparison]::OrdinalIgnoreCase))) { throw "Outside permitted cleanup roots: $resolved" }
    foreach ($protected in $keep) {
        if ($resolved -eq $protected -or $resolved.StartsWith($protected + '\', [StringComparison]::OrdinalIgnoreCase) -or $protected.StartsWith($resolved + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'protected verification or monitoring directory' }
    }
    $cursor = $resolved
    while ($cursor -ne $workspace) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return 'reparse point in target path' }
        $cursor = Split-Path -Parent $cursor
    }
    if (@(Get-ChildItem -LiteralPath $resolved -Recurse -Force -Attributes ReparsePoint).Count) { return 'target contains a reparse point' }
    foreach ($executable in (Active-Executables)) {
        if ($executable.StartsWith($resolved + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'contains a running executable' }
    }
    $relative = $resolved.Substring($workspace.Length + 1).Replace('\', '/')
    $tracked = @(& git -C $workspace ls-files -- $relative)
    if ($LASTEXITCODE -ne 0 -or $tracked.Count) { return 'contains versioned files or git check failed' }
    return ''
}
$candidates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $artifactRoot) {
    foreach ($config in Get-ChildItem -LiteralPath $artifactRoot -Filter 'CodeManager.runtimeconfig.json' -File -Recurse) {
        $folder = $config.Directory.FullName
        if (-not (Test-Path -LiteralPath (Join-Path $folder 'CodeManager.exe'))) { continue }
        # Only a pure build output qualifies. Reports, staged source and task data stay.
        $unexpected = @(Get-ChildItem -LiteralPath $folder -Force | Where-Object {
            if ($_.PSIsContainer) { $_.Name -notin @('scripts','skins','themes','runtimes') }
            else { $_.Name -notin @('CodeManager.exe','CodeManager.dll','CodeManager.pdb','CodeManager.deps.json','CodeManager.runtimeconfig.json') }
        })
        if ($unexpected.Count -eq 0) { $null = $candidates.Add($folder) }
    }
}
foreach ($project in Get-ChildItem -LiteralPath $toolRoot -Directory) {
    if (@(Get-ChildItem -LiteralPath $project.FullName -Filter '*.csproj' -File).Count -eq 0) { continue }
    foreach ($name in @('bin','obj')) {
        $folder = Join-Path $project.FullName $name
        if (Test-Path -LiteralPath $folder -PathType Container) { $null = $candidates.Add($folder) }
    }
}
$records = @()
foreach ($target in ($candidates | Sort-Object Length -Descending)) {
    $reason = Check-Target $target
    $files = @(Get-ChildItem -LiteralPath $target -File -Recurse -Force)
    $bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
    $status = if ($reason) { 'protected' } else { 'candidate' }
    if ($Apply -and -not $reason -and $PSCmdlet.ShouldProcess($target, 'Delete regenerable build output')) {
        # Recheck absolute containment and running processes immediately before mutation.
        $reason = Check-Target $target
        if ($reason) { $status = 'protected' }
        else { Remove-Item -LiteralPath $target -Recurse -Force; $status = 'removed' }
    }
    $records += [pscustomobject]@{ path = $target.Substring($workspace.Length + 1).Replace('\','/'); bytes = $bytes; files = $files.Count; status = $status; reason = $reason }
}
[IO.Directory]::CreateDirectory($reportRoot) | Out-Null
$mode = if ($Apply) { 'applied' } else { 'preview' }
$report = [pscustomobject]@{
    mode = $mode; at = [DateTimeOffset]::UtcNow.ToString('O')
    removedBytes = [long](($records | Where-Object status -eq 'removed' | Measure-Object bytes -Sum).Sum)
    candidateBytes = [long](($records | Where-Object status -eq 'candidate' | Measure-Object bytes -Sum).Sum)
    records = $records
}
$reportPath = Join-Path $reportRoot ('cleanup-' + $mode + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ mode = $mode; removedBytes = $report.removedBytes; candidateBytes = $report.candidateBytes; removedDirectories = @($records | Where-Object status -eq 'removed').Count; protectedDirectories = @($records | Where-Object status -eq 'protected').Count; report = $reportPath } | ConvertTo-Json
