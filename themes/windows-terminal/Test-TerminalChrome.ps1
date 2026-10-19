param([string]$OutputRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot '../../artifacts/terminal-chrome-tests' }
$testRoot = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$settingsPath = Join-Path $testRoot 'settings.json'
$assets = Join-Path $testRoot 'assets'
$utf8 = New-Object Text.UTF8Encoding($true)
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Read-Settings { return [OmniVibeJsonc]::Normalize([IO.File]::ReadAllText($settingsPath)) | ConvertFrom-Json }
function NonTheme($Value) {
    $clone = $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $clone.PSObject.Properties.Remove('themes'); $clone.PSObject.Properties.Remove('theme')
    return ($clone | ConvertTo-Json -Depth 100 -Compress)
}
function Apply([string]$Script,[string[]]$Extra) {
    $out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) -SettingsPath $settingsPath -AssetRoot $assets @Extra
    Assert ($LASTEXITCODE -eq 0) ('Apply failed: ' + ($out -join ' '))
    return ($out -join '' | ConvertFrom-Json)
}
. (Join-Path $PSScriptRoot 'TerminalChrome.ps1')
$presets = @(Get-OmniVibeTerminalChromePresets)
Assert ($presets.Count -eq 13) 'Expected all 13 UI themes.'
# Catch palette drift between the script presets and the actual native UI.
$catalogSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../src/CodeManager/SkinCatalog.cs'))
foreach ($preset in $presets) {
    $pattern = 'new SkinDefinition\(Skin\.\w+, "' + [regex]::Escape($preset.slug) + '",[^\r\n]+?"(#[0-9A-F]{6})", "(#[0-9A-F]{6})", "#[0-9A-F]{6}", "#[0-9A-F]{6}", "#[0-9A-F]{6}", "(#[0-9A-F]{6})"'
    $palette = [regex]::Match($catalogSource,$pattern)
    Assert ($palette.Success -and $palette.Groups[1].Value -ceq $preset.background -and $palette.Groups[2].Value -ceq $preset.surface -and $palette.Groups[3].Value -ceq $preset.accent) ('Native UI palette mismatch: ' + $preset.slug)
}
$cases = @($presets | ForEach-Object { @{ slug=$_.slug; theme=$_.theme; script='Apply-Skin.ps1'; args=@('-Skin',$_.slug,'-ChromeOnly'); background=$_.background } })
foreach ($style in @('Minimal','Ornate')) {
    $name = 'OmniVibe Ink Jade' + $(if ($style -eq 'Ornate') {' Ornate'} else {''})
    $cases += @{slug=('ink-jade-' + $style); theme=[pscustomobject]@{name=$name; window=[pscustomobject]@{applicationTheme='dark'}}; script='Apply-InkJade.ps1'; args=@('-Style',$style,'-ChromeOnly'); background='#0D1612'}
}
$reports = foreach ($case in $cases) {
    $fixture = @'
{
  // Native chrome must not change content, behavior or custom profile settings.
  "theme":"dark", "showTabsInTitlebar":false, "alwaysShowTabs":false,
  "launchMode":"maximized", "tabWidthMode":"titleLength",
  "actions":[{"command":"paste","keys":"ctrl+alt+v"}],
  "defaultProfile":"fixture", "startupActions":"new-tab --title preserved",
  "profiles":{"defaults":{"font":{"face":"Custom Mono","size":17},"padding":"41, 37, 43, 39","opacity":97,"useAcrylic":true,"backgroundImage":"D:\\existing.gif","experimental.pixelShaderPath":"D:\\custom.hlsl"},
    "list":[{"guid":"fixture","name":"Existing","commandline":"pwsh -NoExit","startingDirectory":"D:\\project","tabColor":"#ABCDEF","environment":{"EXAMPLE":"keep"}}]},
  "schemes":[{"name":"Existing","background":"#17202A"}], "themes":[{"name":"User Theme","window":{"applicationTheme":"system"}}]
}
'@
    $fixture = [OmniVibeJsonc]::Normalize($fixture) | ConvertFrom-Json
    $existing = [pscustomobject]@{name=$case.theme.name; window=[pscustomobject]@{applicationTheme=$case.theme.window.applicationTheme; useMica=$true}; tab=[pscustomobject]@{showCloseButton='always'; iconStyle='monochrome'}}
    $fixture.themes += $existing
    [IO.File]::WriteAllText($settingsPath,($fixture | ConvertTo-Json -Depth 100),$utf8)
    $beforeBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath))
    $before = NonTheme $fixture
    $result = Apply $case.script $case.args
    $after = Read-Settings
    Assert ((NonTheme $after) -ceq $before) ('Non-theme settings changed: ' + $case.slug)
    $theme = @($after.themes | Where-Object name -eq $case.theme.name)
    Assert ($theme.Count -eq 1) 'Native theme missing or duplicated.'
    $theme = $theme[0]
    Assert ($theme.tab.background -ceq $case.background) 'Selected tab did not join the pane base color.'
    Assert ($theme.tab.unfocusedBackground -ceq $theme.tabRow.background) 'Inactive tabs do not join the row.'
    Assert ($theme.tabRow.unfocusedBackground -cne $theme.tabRow.background) 'Window focus palette missing.'
    Assert ($theme.window.frame -match '^#[0-9A-F]{6}$' -and $theme.window.unfocusedFrame -cne $theme.window.frame) 'Native frame palette missing.'
    Assert (-not $theme.window.'experimental.rainbowFrame') 'A border animation loop was enabled.'
    Assert ($theme.tab.showCloseButton -ceq 'always' -and $theme.tab.iconStyle -ceq 'monochrome' -and $theme.window.useMica) 'Existing native behavior was changed.'
    Assert (@($after.themes | Where-Object name -eq 'User Theme').Count -eq 1) 'Unrelated user theme removed.'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($result.BackupPath)) -ceq $beforeBytes) 'Backup was not byte-exact.'
    $null = Apply $case.script $case.args
    Assert (@((Read-Settings).themes | Where-Object name -eq $case.theme.name).Count -eq 1) 'Repeated apply duplicated theme.'
    $null = Apply $case.script @('-RestoreFrom',$result.BackupPath)
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath)) -ceq $beforeBytes) 'Restore was not byte-exact.'
    [pscustomobject]@{Skin=$case.slug; ChromeOnly=$true; ProfilesAndBehaviorPreserved=$true; NativeControlsPreserved=$true; BackupRestoreByteExact=$true}
}
$bulkReports = foreach ($selection in @('named','automatic','absent')) {
    $fixture = [pscustomobject]@{themes=@([pscustomobject]@{name='User Theme'; window=[pscustomobject]@{applicationTheme='system'}}); profiles=[pscustomobject]@{defaults=[pscustomobject]@{backgroundImage='D:\existing.gif'; padding='40'; font=[pscustomobject]@{size=17}}}; actions=@()}
    if ($selection -eq 'named') { $fixture | Add-Member NoteProperty theme $presets[0].theme.name }
    elseif ($selection -eq 'automatic') { $fixture | Add-Member NoteProperty theme ([pscustomobject]@{light='User Theme';dark=$presets[1].theme.name}) }
    [IO.File]::WriteAllText($settingsPath,($fixture | ConvertTo-Json -Depth 100),$utf8)
    $beforeBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath))
    $before = NonTheme $fixture
    $selectionBefore = $fixture.theme | ConvertTo-Json -Compress
    $result = Apply 'Apply-Skin.ps1' @('-RegisterAllChrome')
    $after = Read-Settings
    Assert ($result.RegisteredThemeCount -eq 13 -and $after.themes.Count -eq 14) 'Bulk registration missed themes or removed a user theme.'
    Assert ((NonTheme $after) -ceq $before) 'Bulk registration changed profile content or behavior.'
    Assert (($after.theme | ConvertTo-Json -Compress) -ceq $selectionBefore) 'Bulk registration changed theme selection.'
    Assert (($selection -ne 'absent') -or $null -eq $after.PSObject.Properties['theme']) 'Bulk registration introduced a theme selection.'
    foreach ($preset in $presets) {
        $theme = @($after.themes | Where-Object name -eq $preset.theme.name)
        Assert ($theme.Count -eq 1 -and $theme[0].tab.background -ceq $preset.background -and $theme[0].window.frame -match '^#[0-9A-F]{6}$') ('Bulk chrome incomplete: ' + $preset.slug)
    }
    $null = Apply 'Apply-Skin.ps1' @('-RegisterAllChrome')
    Assert ((Read-Settings).themes.Count -eq 14) 'Bulk registration duplicated themes.'
    $null = Apply 'Apply-Skin.ps1' @('-RestoreFrom',$result.BackupPath)
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath)) -ceq $beforeBytes) 'Bulk restore was not byte-exact.'
    [pscustomobject]@{Selection=$selection; RegisteredThemeCount=13; SelectionAndProfilesPreserved=$true; BackupRestoreByteExact=$true}
}
$report = [pscustomobject]@{Passed=$true; ThemeCount=$presets.Count; Cases=$reports; BulkCases=$bulkReports; OutputRoot=$testRoot}
[IO.File]::WriteAllText((Join-Path ([IO.Path]::GetFullPath($OutputRoot)) 'report.json'),($report | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
$report | ConvertTo-Json -Depth 20
