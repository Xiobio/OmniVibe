param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex')][string]$Provider,
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [Parameter(Mandatory = $true)][string]$ApplicationPath
)
# Side-effect-only observer: never approve, deny, or add instructions to an agent.
$ErrorActionPreference = 'Stop'
try {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $receivedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $payload = [Console]::In.ReadToEnd()
    if ($payload.Length -gt 1048576) { exit 0 }
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = $ApplicationPath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    foreach ($argument in @('hook', '--task', $TaskId, '--provider', $Provider, '--root', $DataRoot, '--at', $receivedAt)) {
        if ($argument.Contains('"')) { exit 0 }
    }
    $processInfo.Arguments = 'hook --task "' + $TaskId + '" --provider "' + $Provider + '" --root "' + $DataRoot + '" --at "' + $receivedAt + '"'
    $hookProcess = New-Object Diagnostics.Process
    $hookProcess.StartInfo = $processInfo
    [void]$hookProcess.Start()
    $hookProcess.StandardInput.Write($payload)
    $hookProcess.StandardInput.Close()
    if (-not $hookProcess.WaitForExit(4000)) { $hookProcess.Kill() }
    $hookProcess.Dispose()
} catch {
    # Hook transport failure must not block the agent's normal permission flow.
    try { [IO.File]::AppendAllText((Join-Path $DataRoot 'bridge-errors.log'), ([DateTimeOffset]::Now.ToString('o') + ' ' + $_.Exception.Message + [Environment]::NewLine)) } catch { }
}
exit 0
