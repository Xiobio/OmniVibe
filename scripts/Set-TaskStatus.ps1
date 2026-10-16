param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 9)][int]$Slot,
    [Parameter(Mandatory = $true)][ValidateSet('unknown', 'running', 'waiting', 'ready', 'error')][string]$State,
    [string]$Message = ''
)
$ErrorActionPreference = 'Stop'
$dataRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodeManager'
$taskData = Get-Content -LiteralPath (Join-Path $dataRoot 'tasks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskSlot = $taskData.Slots | Where-Object { $_.Number -eq $Slot }
if ($null -eq $taskSlot.Window) { throw "Slot $Slot has no task window." }
$eventRoot = Join-Path $dataRoot 'events'
[IO.Directory]::CreateDirectory($eventRoot) | Out-Null
$eventPath = Join-Path $eventRoot ([Guid]::NewGuid().ToString('N') + '.json')
$temporaryPath = $eventPath + '.tmp'
$eventData = @{ TaskId = $taskSlot.Id; State = $State; Message = $Message; At = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
[IO.File]::WriteAllText($temporaryPath, $eventData, (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temporaryPath -Destination $eventPath
