param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex')][string]$Provider,
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [string]$ProjectDirectory = '',
    [string]$ResumeSessionId = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$AgentArguments
)
$ErrorActionPreference = 'Stop'
if ($ResumeSessionId -ne '') {
    $sessionGuid = [guid]::Empty
    if (-not [guid]::TryParse($ResumeSessionId, [ref]$sessionGuid)) { throw 'A saved session UUID is required to resume a task.' }
    $AgentArguments = @($AgentArguments | Where-Object { $null -ne $_ })
    if ($Provider -eq 'claude') { $AgentArguments = @('--resume', $ResumeSessionId) + $AgentArguments }
    else { $AgentArguments = @('resume', $ResumeSessionId) + $AgentArguments }
}
$state = Get-Content -LiteralPath (Join-Path $DataRoot 'tasks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$task = $state.Slots | Where-Object { $_.Id -eq $TaskId -and $null -ne $_.Window }
if ($null -eq $task) { throw 'This task was removed or rebound. Copy a new connection command from CodeManager.' }
if ($ProjectDirectory -ne '') { Set-Location -LiteralPath $ProjectDirectory }
$applicationPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'CodeManager.exe'
$receiver = Join-Path $PSScriptRoot 'Receive-AgentHook.ps1'
if (-not (Test-Path -LiteralPath $applicationPath)) { throw 'Build CodeManager first; run the copy of this script next to the local development executable.' }
foreach ($argument in @($receiver, $applicationPath, $DataRoot)) { if ($argument.Contains('"')) { throw 'Unsupported quote in integration path.' } }
$hookCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $receiver.Replace('\', '/') + '" -TaskId "' + $TaskId + '" -Provider "' + $Provider + '" -DataRoot "' + $DataRoot.Replace('\', '/') + '" -ApplicationPath "' + $applicationPath.Replace('\', '/') + '"'
$events = @('SessionStart', 'UserPromptSubmit', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd')
if ($Provider -eq 'claude') { $events += @('Notification', 'StopFailure', 'Elicitation', 'ElicitationResult') }
else { $events += 'Interrupt' }
$sessionRoot = Join-Path (Join-Path $DataRoot 'sessions') $TaskId
[IO.Directory]::CreateDirectory($sessionRoot) | Out-Null
if ($Provider -eq 'claude') {
    $hooks = @{}
    foreach ($eventName in $events) {
        $hooks[$eventName] = @(@{ hooks = @(@{ type = 'command'; command = $hookCommand; timeout = 5 }) })
    }
    $configPath = Join-Path $sessionRoot 'claude-settings.json'
    [IO.File]::WriteAllText($configPath, (@{ hooks = $hooks } | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    & claude --settings $configPath @AgentArguments
} else {
    $overrides = @('--no-daemon')
    $commandLiteral = ConvertTo-Json -InputObject $hookCommand -Compress
    foreach ($eventName in $events) {
        $value = 'hooks.' + $eventName + '=[{hooks=[{type="command",command=' + $commandLiteral + ',command_windows=' + $commandLiteral + ',timeout=5}]}]'
        $overrides += @('-c', $value)
    }
    Write-Host 'If Codex asks to review hooks, use /hooks to review and trust the CodeManager observers.'
    # Bypass Windows PowerShell 5's lossy native argument binder for TOML values.
    # Support the native executable and the standard npm Node launcher.
    $entry = (Get-Command codex -ErrorAction Stop).Source
    $nativeArguments = @()
    if ([IO.Path]::GetExtension($entry) -ne '.exe') {
        $launcher = Join-Path (Split-Path -Parent $entry) 'node_modules/@openai/codex/bin/codex.js'
        if (-not (Test-Path -LiteralPath $launcher)) { throw 'Cannot locate the Codex native executable or npm launcher.' }
        $entry = (Get-Command node.exe -ErrorAction Stop).Source
        $nativeArguments += $launcher
    }
    $nativeArguments += $overrides
    $nativeArguments += $AgentArguments
    $quotedArguments = foreach ($argument in $nativeArguments) {
        $escaped = [regex]::Replace($argument, '(\\*)"', { param($match) ('\' * ($match.Groups[1].Length * 2 + 1)) + '"' })
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
        '"' + $escaped + '"'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $entry; $start.Arguments = $quotedArguments -join ' '
    $start.UseShellExecute = $false; $start.WorkingDirectory = (Get-Location).Path
    $agent = [Diagnostics.Process]::Start($start)
    $agent.WaitForExit(); $agentExitCode = $agent.ExitCode; $agent.Dispose()
    if ($agentExitCode -ne 0) { throw ('codex exited with code ' + $agentExitCode) }
    return
}
if ($LASTEXITCODE -ne 0) { throw ($Provider + ' exited with code ' + $LASTEXITCODE) }
