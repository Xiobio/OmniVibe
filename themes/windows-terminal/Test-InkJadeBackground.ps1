param([string]$OutputRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot '../../artifacts/terminal-background/config-test' }
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$applier = Join-Path $PSScriptRoot 'Apply-InkJade.ps1'
$settingsPath = Join-Path $OutputRoot 'settings.json'
$assets = Join-Path $OutputRoot 'assets/InkJadeOrnate'
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Apply([string[]]$Extra = @()) {
    $result = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $applier -SettingsPath $settingsPath -AssetRoot $assets @Extra
    Assert ($LASTEXITCODE -eq 0) ('Applier failed: ' + ($result -join '\n'))
    return ($result -join '\n' | ConvertFrom-Json)
}
$original = @'
{
  // Preserve comments and the UTF-8 BOM on restore.
  "defaultProfile": "{11111111-1111-1111-1111-111111111111}",
  "theme": "OmniVibe Ink Jade Ornate",
  "actions": [{"command":"paste","keys":"ctrl+v"}],
  "schemes": [{"name":"OmniVibe Ink Jade","foreground":"#E5D8B9"}],
  "themes": [{"name":"OmniVibe Ink Jade Ornate"}],
  "profiles": {
    "defaults": {
      "colorScheme":"OmniVibe Ink Jade", "padding":"41, 35, 43, 37",
      "font":{"face":"Consolas","size":17}, "opacity":97, "useAcrylic":true,
      "cursorShape":"bar", "historySize":9000,
      "backgroundImage":"C:\\old\\InkJadeOrnate\\ink-jade-ornate-v2.png",
      "backgroundImageOpacity":0.47, "backgroundImageStretchMode":"fill",
      "experimental.pixelShaderPath":"C:\\old\\ornate-frame-v2.hlsl",
      "unfocusedAppearance":{"experimental.pixelShaderPath":"C:\\old\\ornate-frame-v2.hlsl"}
    },
    "list":[
      {"guid":"{11111111-1111-1111-1111-111111111111}","name":"tracked fixture",
       "commandline":"pwsh.exe -NoLogo", "startingDirectory":"D:\\fixture", "environment":{"KEEP":"unchanged"},
       "backgroundImage":"C:\\old\\ink-jade-ornate-v2.png",
       "experimental.pixelShaderPath":"C:\\old\\ornate-frame-v2.hlsl",
       "unfocusedAppearance":{"backgroundImage":"C:\\old\\ink-jade-ornate-v2.png","opacity":91}},
      {"guid":"{22222222-2222-2222-2222-222222222222}","name":"independent styling",
       "commandline":"cmd.exe", "backgroundImage":"C:\\other\\wallpaper.png",
       "experimental.pixelShaderPath":"C:\\other\\unrelated.hlsl", "font":{"size":22}}
    ],
  },
}
'@
$encoding = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($settingsPath, $original, $encoding)
$originalBytes = [IO.File]::ReadAllBytes($settingsPath)
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
$before = [OmniVibeJsonc]::Normalize($original) | ConvertFrom-Json
$defaultStatic = Apply @('-Style','Ornate','-BackgroundOnly')
Assert ($defaultStatic.RenderingMode -eq 'background-png' -and $defaultStatic.AnimationFrames -eq 1 -and -not $defaultStatic.EffectsEnabled) 'Default Ornate application must keep the original static illustration.'
Assert ($defaultStatic.BackgroundPath -match '\.png$') 'Default Ornate application enabled a GIF.'
$null = Apply @('-RestoreFrom',$defaultStatic.BackupPath)
$result = Apply @('-Style','Ornate','-BackgroundOnly','-EnableAnimation')
$after = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
Assert ($result.RenderingMode -eq 'background-gif' -and $result.AnimationFrames -eq 200 -and -not $result.ShaderEnabled) 'Expected a 200-frame background GIF with no post-text shader.'
Assert ($after.profiles.defaults.backgroundImage -match 'ink-jade-background-v5\.gif$') 'Default background was not migrated.'
Assert ($null -eq $after.profiles.defaults.'experimental.pixelShaderPath') 'Default post-text shader survived.'
Assert ($null -eq $after.profiles.defaults.unfocusedAppearance.'experimental.pixelShaderPath') 'Unfocused post-text shader survived.'
Assert ($after.profiles.list[0].backgroundImage -eq $result.BackgroundPath) 'Explicit old profile image survived.'
Assert ($after.profiles.list[0].unfocusedAppearance.backgroundImage -eq $result.BackgroundPath) 'Explicit unfocused old image survived.'
Assert ($null -eq $after.profiles.list[0].'experimental.pixelShaderPath') 'Explicit profile shader survived.'
foreach ($name in @('padding','font','colorScheme','opacity','useAcrylic','cursorShape','historySize','backgroundImageOpacity','backgroundImageStretchMode')) {
    Assert (($before.profiles.defaults.$name | ConvertTo-Json -Compress -Depth 20) -ceq ($after.profiles.defaults.$name | ConvertTo-Json -Compress -Depth 20)) ('Background-only changed ' + $name)
}
foreach ($name in @('commandline','startingDirectory','environment','guid','name')) {
    Assert (($before.profiles.list[0].$name | ConvertTo-Json -Compress -Depth 20) -ceq ($after.profiles.list[0].$name | ConvertTo-Json -Compress -Depth 20)) ('Changed task profile ' + $name)
}
foreach ($name in @('defaultProfile','actions','schemes','themes','theme')) {
    Assert (($before.$name | ConvertTo-Json -Compress -Depth 20) -ceq ($after.$name | ConvertTo-Json -Compress -Depth 20)) ('Changed unrelated global setting ' + $name)
}
Assert (($before.profiles.list[1] | ConvertTo-Json -Compress -Depth 20) -ceq ($after.profiles.list[1] | ConvertTo-Json -Compress -Depth 20)) 'Unrelated profile styling changed.'
$firstBackup = $result.BackupPath
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($firstBackup)) -ceq [Convert]::ToBase64String($originalBytes)) 'Backup was not byte-exact.'
$null = Apply @('-Style','Ornate','-BackgroundOnly','-EnableAnimation')
$still = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
Assert ($still.profiles.defaults.backgroundImage -eq $result.BackgroundPath) 'Repeated application changed the installed asset.'
$static = Apply @('-Style','Ornate','-BackgroundOnly','-DisableEffects')
Assert (-not $static.EffectsEnabled -and $static.RenderingMode -eq 'background-png') 'Disabled animation did not use the original PNG.'
$null = Apply @('-RestoreFrom',$firstBackup)
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath)) -ceq [Convert]::ToBase64String($originalBytes)) 'Restore did not preserve original bytes, comments and BOM.'
$full = Apply @('-Style','Ornate','-EnableAnimation')
$fullSettings = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
Assert ($null -eq $fullSettings.profiles.defaults.'experimental.pixelShaderPath' -and $fullSettings.profiles.defaults.backgroundImage -match '\.gif$') 'Normal Ornate apply still used the old shader.'

# Native Windows GIF decoder, in addition to the generator's every-pixel checks.
Add-Type -AssemblyName System.Drawing
$gif = [Drawing.Image]::FromFile($full.BackgroundPath)
try {
    $count = $gif.GetFrameCount([Drawing.Imaging.FrameDimension]::Time)
    Assert ($count -eq 200) 'Windows could not decode all 200 GIF frames.'
    $center = $gif.GetPixel([int]($gif.Width / 2),[int]($gif.Height / 2)).ToArgb()
    $edgeSamples = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($i = 0; $i -lt $count; $i++) {
        $null = $gif.SelectActiveFrame([Drawing.Imaging.FrameDimension]::Time, $i)
        Assert ($gif.GetPixel([int]($gif.Width / 2),[int]($gif.Height / 2)).ToArgb() -eq $center) 'Native GIF decoder changed the centre.'
        $null = $edgeSamples.Add($gif.GetPixel([int]($gif.Width * 0.4),[int]($gif.Height * 0.012)).ToArgb())
    }
    Assert ($edgeSamples.Count -gt 1) 'Native decoder did not observe the moving rim light.'
} finally { $gif.Dispose() }
$snapshot = [IO.File]::ReadAllBytes($settingsPath)
$ErrorActionPreference = 'Continue'
try { $bad = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $applier -SettingsPath $settingsPath -AssetRoot $assets -Style Minimal -BackgroundOnly 2>&1; $badExit = $LASTEXITCODE }
finally { $ErrorActionPreference = 'Stop' }
Assert ($badExit -ne 0) 'Invalid BackgroundOnly mode was accepted.'
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath)) -ceq [Convert]::ToBase64String($snapshot)) 'Rejected mode changed settings.'
$report = [ordered]@{
    passed=$true; isolatedSettingsOnly=$true; backgroundGif=$true; framesDecodedByWindows=$count
    nativeCenterStatic=$true; nativeEdgeAnimation=$true; defaultShaderRemoved=$true
    explicitAndUnfocusedOverridesMigrated=$true; profileCommandsAndSettingsPreserved=$true
    unrelatedProfilePreserved=$true; fontPaddingAndAppearancePreserved=$true
    repeatApplyPassed=$true; staticByDefault=$true; explicitAnimationVerified=$true; staticPngFallbackPassed=$true; originalPngPreserved=$true
    backupRestoreByteExactIncludingBom=$true; invalidModeRejectedWithoutSettingsChange=$true
}
$json = $report | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $OutputRoot 'report.json'),$json,(New-Object Text.UTF8Encoding($false)))
$json
