param([string]$OutputRoot = '', [switch]$RequireArtwork, [string]$Skin = '')
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'artifacts/terminal-skin-tests' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$testRoot = Join-Path $OutputRoot ([guid]::NewGuid().ToString('N'))
$testScripts = Join-Path $testRoot 'repo/themes/windows-terminal'
[IO.Directory]::CreateDirectory($testScripts) | Out-Null
foreach ($name in @('Apply-Skin.ps1','TerminalChrome.ps1','classic-palettes.json','Jsonc.cs','ShaderCompiler.cs','FrameLayout.cs','skins.json')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $testScripts }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'shaders') -Destination $testScripts -Recurse
[IO.Directory]::CreateDirectory((Join-Path $testScripts 'assets')) | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets/refined-v1') -Destination (Join-Path $testScripts 'assets') -Recurse
$manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'skins.json')) | ConvertFrom-Json
$testedEntries = @($manifest.skins | Where-Object { -not $Skin -or $_.slug -eq $Skin })
if ($testedEntries.Count -eq 0) { throw "Unknown test skin: $Skin" }
$fixtureImages = @()
foreach ($entry in $manifest.skins) {
    $source = Join-Path $repoRoot $entry.artwork
    if (-not (Test-Path -LiteralPath $source)) {
        if ($RequireArtwork) { throw "Missing artwork: $source" }
        $source = Join-Path $PSScriptRoot 'assets/ink-jade-ornate-v2.png'
        $fixtureImages += $entry.slug
    }
    $target = Join-Path $testRoot ('repo/' + $entry.artwork)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
$settingsPath = Join-Path $testRoot 'settings.json'
$assets = Join-Path $testRoot 'installed-assets'
$utf8 = New-Object Text.UTF8Encoding($false)
$fixture = @'
{
  // User comments must be accepted and preserved verbatim in the backup.
  "defaultProfile": "{00000000-0000-0000-0000-000000000001}",
  "actions": [{"command":"paste", "keys":"ctrl+alt+v",}],
  "startupActions": "new-tab --title \"https://example.org//retain/*yes*/\"",
  "profiles": {
    "defaults": {"font":{"face":"My Custom Mono", "size":15}, "cursorShape":"underscore", "foreground":"#FFFFFF", "background":"#000000", "unfocusedAppearance":{"foreground":"#AAAAAA","background":"#111111"},},
    "list": [{"guid":"{00000000-0000-0000-0000-000000000001}","name":"Keep me","commandline":"cmd.exe /k echo \"a//b/*c*/\"", "startingDirectory":"D:\\my project", "environment":{"KEY":"/* keep */"}, "colorScheme":"Campbell", "foreground":"#FFFFFF", "background":"#000000"},],
  }, /* block comment */
  "experimental.rendering.software": true,
}
'@
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Read-Json([string]$Text) { return [OmniVibeJsonc]::Normalize($Text) | ConvertFrom-Json }
function Invoke-Apply([string[]]$Arguments) {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'Apply-Skin.ps1') -SettingsPath $settingsPath -AssetRoot $assets @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    return ($output -join "`n") | ConvertFrom-Json
}
function Invoke-Rejected([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'Apply-Skin.ps1') -SettingsPath $settingsPath -AssetRoot $assets @Arguments 2>&1
    return $LASTEXITCODE
}
$originalObject = Read-Json $fixture
$reports = @()
foreach ($entry in $testedEntries) {
    [IO.File]::WriteAllText($settingsPath,$fixture,$utf8)
    $result = Invoke-Apply @('-Skin',$entry.slug)
    $actual = Read-Json ([IO.File]::ReadAllText($settingsPath))
    Assert ($actual.defaultProfile -ceq $originalObject.defaultProfile) 'defaultProfile changed.'
    Assert (($actual.actions | ConvertTo-Json -Compress -Depth 10) -ceq ($originalObject.actions | ConvertTo-Json -Compress -Depth 10)) 'Shortcuts changed.'
    Assert ($actual.startupActions -ceq $originalObject.startupActions) 'startupActions changed.'
    Assert (($actual.profiles.list | ConvertTo-Json -Compress -Depth 10) -ceq ($originalObject.profiles.list | ConvertTo-Json -Compress -Depth 10)) 'Profile commands/cwd/environment changed.'
    Assert ($actual.profiles.defaults.font.face -ceq 'My Custom Mono') 'User font changed.'
    Assert ($actual.profiles.defaults.cursorShape -ceq 'underscore') 'User cursor preference changed.'
    Assert ($null -eq $actual.profiles.defaults.foreground -and $null -eq $actual.profiles.defaults.background) 'Old explicit colors override the selected theme.'
    Assert ($actual.profiles.defaults.unfocusedAppearance.colorScheme -ceq $entry.scheme.name) 'Unfocused theme was not switched.'
    Assert ([IO.File]::ReadAllText($result.BackupPath) -ceq $fixture) 'Backup was not byte-for-byte.'
    Assert (Test-Path -LiteralPath $actual.profiles.defaults.backgroundImage) 'Installed illustration is missing.'
    Assert ($actual.profiles.defaults.backgroundImage.StartsWith($assets,[StringComparison]::OrdinalIgnoreCase)) 'Illustration references repository or cache.'
    Assert ($null -eq $actual.profiles.defaults.'experimental.pixelShaderPath') 'A post-text shader was enabled.'
    Assert ($result.RenderingMode -ceq 'background-gif' -and $result.AnimationFrames -eq 96) 'C background animation was not applied.'
    Assert ($actual.profiles.defaults.backgroundImageOpacity -eq 1 -and $actual.profiles.defaults.backgroundImageStretchMode -ceq 'fill') 'Precomposited C layout was not preserved.'
    $null = Invoke-Apply @('-Skin',$entry.slug,'-DisableEffects')
    $static = Read-Json ([IO.File]::ReadAllText($settingsPath))
    Assert ($static.profiles.defaults.backgroundImage -match '\.png$') 'Animation-off did not select the static C asset.'
    $null = Invoke-Apply @('-Skin',$entry.slug,'-DisableArtwork')
    $frameOnly = Read-Json ([IO.File]::ReadAllText($settingsPath))
    Assert ($frameOnly.profiles.defaults.backgroundImage -match 'frame-only.*\.gif$') 'Artwork-off removed the independently enabled border animation.'
    $null = Invoke-Apply @('-Skin',$entry.slug,'-DisableEffects','-DisableArtwork','-AllProfiles')
    $disabled = Read-Json ([IO.File]::ReadAllText($settingsPath))
    Assert ($null -eq $disabled.profiles.defaults.'experimental.pixelShaderPath') 'Effects were not disabled.'
    Assert ($null -eq $disabled.profiles.list[0].'experimental.pixelShaderPath') 'Profile effects were not disabled.'
    Assert ($disabled.profiles.defaults.backgroundImage -ceq '' -and $disabled.profiles.defaults.backgroundImageOpacity -eq 0) 'Artwork was not disabled.'
    Assert ($disabled.profiles.list[0].backgroundImage -ceq '' -and $disabled.profiles.list[0].backgroundImageOpacity -eq 0) 'Profile artwork was not disabled.'
    Assert ($disabled.profiles.list[0].colorScheme -ceq $entry.scheme.name) 'AllProfiles did not apply appearance.'
    Assert ($null -eq $disabled.profiles.list[0].foreground -and $null -eq $disabled.profiles.list[0].background) 'AllProfiles did not remove incompatible color overrides.'
    Assert ($disabled.profiles.list[0].commandline -ceq $originalObject.profiles.list[0].commandline) 'AllProfiles changed commandline.'
    Assert (@($disabled.schemes | Where-Object { $_.name -eq $entry.scheme.name }).Count -eq 1) 'Duplicate scheme created.'
    $null = Invoke-Apply @('-RestoreFrom',$result.BackupPath)
    Assert ([IO.File]::ReadAllText($settingsPath) -ceq $fixture) 'Restore did not preserve original JSONC.'
    $reports += @{slug=$entry.slug; applied=$true; jsoncAccepted=$true; commandsAndShortcutsPreserved=$true; originalFontPreserved=$true; allProfilesVerified=$true; effectsDisableVerified=$true; artworkOffAnimationPreserved=$true; backgroundGifFrames=$result.AnimationFrames; frameLayout='C'; postTextShaderEnabled=$false; backupRestoreByteExact=$true; testIllustrationFixture=($fixtureImages -contains $entry.slug)}
}
$negativeCases = 0
foreach ($bad in @('{"profiles": /* unterminated','{"profiles": [}', '[1,2,3]', '{"profiles": [],}', '{"profiles":{"defaults":[]}}', '{"x":[1,,]}', '{"x":[,]}')) {
    [IO.File]::WriteAllText($settingsPath,$bad,$utf8)
    $rejected = Invoke-Rejected @('-Skin','hextech')
    Assert ($rejected -ne 0) 'Malformed settings unexpectedly accepted.'
    Assert ([IO.File]::ReadAllText($settingsPath) -ceq $bad) 'Malformed settings were overwritten.'
    $negativeCases++
}
[IO.File]::WriteAllText($settingsPath,$fixture,$utf8)
$rejected = Invoke-Rejected @()
Assert ($rejected -ne 0) 'Missing explicit skin unexpectedly accepted.'
Assert ([IO.File]::ReadAllText($settingsPath) -ceq $fixture) 'Missing skin modified settings.'
# Restore is truly byte-for-byte even for UTF-8 files with BOM.
[IO.File]::WriteAllText($settingsPath,$fixture,(New-Object Text.UTF8Encoding($true)))
$bomBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath))
$bomApply = Invoke-Apply @('-Skin','hextech','-DisableEffects')
$null = Invoke-Apply @('-RestoreFrom',$bomApply.BackupPath)
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath)) -ceq $bomBytes) 'BOM restore was not byte-exact.'
$result = [ordered]@{ skins=$reports; negativeCasesPassed=($negativeCases+1); utf8BomRestoreByteExact=$true; isolatedSettingsOnly=$true; artworkFixtureCount=$fixtureImages.Count; outputRoot=$testRoot }
[IO.File]::WriteAllText((Join-Path $OutputRoot 'report.json'),($result | ConvertTo-Json -Depth 20),$utf8)
$result | ConvertTo-Json -Depth 20
