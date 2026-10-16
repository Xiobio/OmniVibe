param(
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'),
    [string]$RestoreFrom = '',
    [ValidateSet('Minimal', 'Ornate')][string]$Style = 'Minimal',
    [switch]$DisableEffects
)
$ErrorActionPreference = 'Stop'
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
$assetRoot = Join-Path $env:LOCALAPPDATA $(if ($Style -eq 'Ornate') { 'OmniVibe/TerminalTheme/InkJadeOrnate' } else { 'OmniVibe/TerminalTheme/InkJade' })
$backupRoot = Join-Path $env:LOCALAPPDATA 'OmniVibe/TerminalTheme/Backups'
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'Windows Terminal settings.json was not found.' }
$original = [IO.File]::ReadAllText($SettingsPath)
$settings = [OmniVibeJsonc]::Normalize($original) | ConvertFrom-Json
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$backup = Join-Path $backupRoot ('settings-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
[IO.File]::Copy($SettingsPath, $backup, $false)
$utf8 = New-Object Text.UTF8Encoding($false)
if ($RestoreFrom -ne '') {
    $restored = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RestoreFrom).Path)
    $null = [OmniVibeJsonc]::Normalize($restored) | ConvertFrom-Json
    if ([IO.File]::ReadAllText($SettingsPath) -cne $original) { throw 'Terminal settings changed during this operation; no settings were overwritten.' }
    [IO.File]::WriteAllText($SettingsPath, $restored, $utf8)
    [pscustomobject]@{ Restored = $true; SettingsPath = $SettingsPath; BackupPath = $backup } | ConvertTo-Json -Compress
    return
}

# Procedural artwork follows OmniVibe's existing ink scenery; no external images.
[IO.Directory]::CreateDirectory($assetRoot) | Out-Null
if ($Style -eq 'Ornate') {
    $backgroundPath = Join-Path $assetRoot 'ink-jade-ornate-v2.png'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets/ink-jade-ornate-v2.png') -Destination $backgroundPath -Force
    $shaderPath = Join-Path $assetRoot 'ornate-frame-v2.hlsl'
    $shaderSource = Join-Path $PSScriptRoot 'ornate-frame-v2.hlsl'
    if (-not $DisableEffects) {
        if (-not ('OmniVibeShaderCompiler' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ShaderCompiler.cs') }
        $compiledShaderBytes = [OmniVibeShaderCompiler]::Validate([IO.File]::ReadAllText($shaderSource))
        Copy-Item -LiteralPath $shaderSource -Destination $shaderPath -Force
    }
} else {
Add-Type -AssemblyName System.Drawing
$backgroundPath = Join-Path $assetRoot 'ink-jade-mountains.png'
$bitmap = New-Object Drawing.Bitmap(2560, 1600)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
try {
    $bounds = New-Object Drawing.Rectangle(0, 0, 2560, 1600)
    $gradient = New-Object Drawing.Drawing2D.LinearGradientBrush($bounds, [Drawing.ColorTranslator]::FromHtml('#101B17'), [Drawing.ColorTranslator]::FromHtml('#20362B'), 24.0)
    $graphics.FillRectangle($gradient, $bounds); $gradient.Dispose()
    $random = New-Object Random(217)
    $grain = New-Object Drawing.Pen([Drawing.Color]::FromArgb(7, 221, 209, 178), 1)
    for ($i = 0; $i -lt 6500; $i++) { $x = $random.Next(2560); $y = $random.Next(1600); $graphics.DrawLine($grain, $x, $y, $x + 1, $y + 2) }
    $grain.Dispose()
    for ($layer = 0; $layer -lt 4; $layer++) {
        $points = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
        $points.Add((New-Object Drawing.PointF(650, 1600)))
        for ($i = 0; $i -le 20; $i++) {
            $x = 650 + $i * 100
            $height = 200 + 290 * [Math]::Exp(-[Math]::Pow(($i - 14) / 4.0, 2)) + $random.Next(135)
            $y = 1600 - $height + $layer * 105
            $points.Add((New-Object Drawing.PointF($x, $y)))
        }
        $points.Add((New-Object Drawing.PointF(2650, 1600)))
        $shade = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(130, 10 + $layer * 2, 26 + $layer * 2, 19 + $layer * 2))
        $graphics.FillPolygon($shade, $points.ToArray()); $shade.Dispose()
    }
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(23, 182, 164, 111), 1.5)
    foreach ($radius in @(145, 151, 182)) { $graphics.DrawEllipse($pen, [single](2210 - $radius), [single](650 - $radius), [single]($radius * 2), [single]($radius * 2)) }
    for ($i = 0; $i -lt 8; $i++) {
        $state = $graphics.Save(); $graphics.TranslateTransform(2210, 650); $graphics.RotateTransform($i * 45)
        for ($j = 0; $j -lt 3; $j++) {
            $y = -162 - $j * 5
            if (($i -band (1 -shl $j)) -eq 0) { $graphics.DrawLine($pen, -16, $y, 16, $y) }
            else { $graphics.DrawLine($pen, -16, $y, -4, $y); $graphics.DrawLine($pen, 4, $y, 16, $y) }
        }
        $graphics.Restore($state)
    }
    $pen.Dispose()
    $bitmap.Save($backgroundPath, [Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $bitmap.Dispose() }
}

function Set-Property($Object, [string]$Name, $Value) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force }
$scheme = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'OmniVibe-InkJade.json') | ConvertFrom-Json
Set-Property $settings 'schemes' (@($settings.schemes | Where-Object { $_.name -ne $scheme.name }) + @($scheme))
if ($null -eq $settings.profiles) { Set-Property $settings 'profiles' ([pscustomobject]@{}) }
if ($null -eq $settings.profiles.defaults) { Set-Property $settings.profiles 'defaults' ([pscustomobject]@{}) }
$defaults = $settings.profiles.defaults
if ($null -eq $defaults.font) { Set-Property $defaults 'font' ([pscustomobject]@{}) }
Set-Property $defaults.font 'face' 'Cascadia Mono'
Set-Property $defaults.font 'size' 13
Set-Property $defaults 'colorScheme' $scheme.name
Set-Property $defaults 'padding' '16, 12, 16, 12'
Set-Property $defaults 'antialiasingMode' 'grayscale'
Set-Property $defaults 'cursorShape' 'bar'
Set-Property $defaults 'opacity' 96
Set-Property $defaults 'useAcrylic' $true
Set-Property $defaults 'backgroundImage' $backgroundPath
Set-Property $defaults 'backgroundImageOpacity' 0.4
Set-Property $defaults 'backgroundImageStretchMode' 'uniformToFill'
Set-Property $defaults 'backgroundImageAlignment' 'center'
if ($Style -eq 'Ornate') {
    Set-Property $defaults 'padding' '36, 30, 36, 30'
    Set-Property $defaults 'backgroundImageOpacity' 0.5
    Set-Property $defaults 'backgroundImageStretchMode' 'fill'
    Set-Property $defaults 'opacity' 98
    if (-not $DisableEffects) { Set-Property $defaults 'experimental.pixelShaderPath' $shaderPath }
    else { $defaults.PSObject.Properties.Remove('experimental.pixelShaderPath') }
} else { $defaults.PSObject.Properties.Remove('experimental.pixelShaderPath') }
$theme = [pscustomobject]@{
    name = 'OmniVibe Ink Jade'
    window = [pscustomobject]@{ applicationTheme = 'dark' }
    tab = [pscustomobject]@{ background = '#2A4035'; unfocusedBackground = '#17251E'; showCloseButton = 'hover' }
    tabRow = [pscustomobject]@{ background = '#0D1612'; unfocusedBackground = '#0D1612' }
}
if ($Style -eq 'Ornate') { $theme.name = 'OmniVibe Ink Jade Ornate' }
Set-Property $settings 'themes' (@($settings.themes | Where-Object { $_.name -ne $theme.name }) + @($theme))
Set-Property $settings 'theme' $theme.name
$updated = $settings | ConvertTo-Json -Depth 100
$null = $updated | ConvertFrom-Json
if ([IO.File]::ReadAllText($SettingsPath) -cne $original) { throw 'Terminal settings changed during this operation; no settings were overwritten.' }
[IO.File]::WriteAllText($SettingsPath, $updated, $utf8)
[pscustomobject]@{ Theme = $theme.name; Style = $Style; SettingsPath = $SettingsPath; BackupPath = $backup; BackgroundPath = $backgroundPath; EffectsEnabled = ($Style -eq 'Ornate' -and -not $DisableEffects); ShaderCompiledBytes = $compiledShaderBytes } | ConvertTo-Json -Compress
