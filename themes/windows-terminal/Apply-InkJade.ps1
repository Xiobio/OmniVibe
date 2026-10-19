param(
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'),
    [string]$RestoreFrom = '',
    [ValidateSet('Minimal', 'Ornate')][string]$Style = 'Minimal',
    [switch]$DisableEffects,
    [switch]$BackgroundOnly,
    [switch]$ChromeOnly,
    [string]$AssetRoot = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if ($BackgroundOnly -and ($Style -ne 'Ornate' -or $RestoreFrom)) { throw '-BackgroundOnly requires -Style Ornate and cannot be used with -RestoreFrom.' }
if ($ChromeOnly -and ($BackgroundOnly -or $RestoreFrom -or $DisableEffects)) { throw '-ChromeOnly cannot be combined with background, effect or restore options.' }
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
. (Join-Path $PSScriptRoot 'TerminalChrome.ps1')
if (-not $AssetRoot) { $AssetRoot = Join-Path $env:LOCALAPPDATA $(if ($Style -eq 'Ornate') { 'OmniVibe/TerminalTheme/InkJadeOrnate' } else { 'OmniVibe/TerminalTheme/InkJade' }) }
$backupRoot = Join-Path (Split-Path -Parent $AssetRoot) 'Backups'
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'Windows Terminal settings.json was not found.' }
$SettingsPath = (Resolve-Path -LiteralPath $SettingsPath).Path
$originalBytes = [IO.File]::ReadAllBytes($SettingsPath)
$original = [IO.File]::ReadAllText($SettingsPath)
$settings = [OmniVibeJsonc]::Normalize($original) | ConvertFrom-Json
if ($settings -isnot [pscustomobject]) { throw 'Terminal settings must be a JSON object.' }
$utf8 = New-Object Text.UTF8Encoding($false)
function Set-Property($Object, [string]$Name, $Value) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force }
function Write-Settings([byte[]]$Bytes) {
    $expected = [Convert]::ToBase64String($originalBytes)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($SettingsPath)) -cne $expected) { throw 'Terminal settings changed during this operation; nothing was overwritten.' }
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    $backup = Join-Path $backupRoot ('settings-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
    [IO.File]::Copy($SettingsPath, $backup, $false)
    $temporary = Join-Path (Split-Path -Parent $SettingsPath) ('.omnivibe-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($SettingsPath)) -cne $expected) { throw 'Terminal settings changed during this operation; nothing was overwritten.' }
        [IO.File]::Replace($temporary, $SettingsPath, [NullString]::Value)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    return $backup
}
if ($RestoreFrom -ne '') {
    $restorePath = (Resolve-Path -LiteralPath $RestoreFrom).Path
    $restored = [OmniVibeJsonc]::Normalize([IO.File]::ReadAllText($restorePath)) | ConvertFrom-Json
    if ($restored -isnot [pscustomobject]) { throw 'The restore file must contain a JSON object.' }
    $backup = Write-Settings ([IO.File]::ReadAllBytes($restorePath))
    [pscustomobject]@{ Restored = $true; SettingsPath = $SettingsPath; BackupPath = $backup } | ConvertTo-Json -Compress
    return
}
if ($null -ne $settings.profiles -and $settings.profiles -isnot [pscustomobject]) { throw 'profiles must be an object; legacy array profiles are not modified.' }
if ($null -ne $settings.profiles.defaults -and $settings.profiles.defaults -isnot [pscustomobject]) { throw 'profiles.defaults must be an object.' }
if ($null -ne $settings.profiles.list -and $settings.profiles.list -isnot [array]) { throw 'profiles.list must be an array.' }
foreach ($target in @($settings.profiles.defaults) + @($settings.profiles.list)) {
    if ($null -eq $target) { continue }
    if ($target -isnot [pscustomobject]) { throw 'Every profile must be an object.' }
    if ($null -ne $target.unfocusedAppearance -and $target.unfocusedAppearance -isnot [pscustomobject]) { throw 'unfocusedAppearance must be an object.' }
}

if ($ChromeOnly) {
    $themeName = if ($Style -eq 'Ornate') { 'OmniVibe Ink Jade Ornate' } else { 'OmniVibe Ink Jade' }
    $native = @($settings.themes | Where-Object { $_.name -eq $themeName }) | Select-Object -First 1
    if ($null -eq $native) { $native = [pscustomobject]@{ name=$themeName; window=[pscustomobject]@{applicationTheme='dark'}; tab=[pscustomobject]@{showCloseButton='hover'} } }
    $native = Get-OmniVibeTerminalChrome $native '#0D1612' '#D6B674' '#2A4035'
    Set-Property $settings 'themes' (@($settings.themes | Where-Object { $_.name -ne $themeName }) + @($native))
    Set-Property $settings 'theme' $themeName
    $backup = Write-Settings ($utf8.GetBytes(($settings | ConvertTo-Json -Depth 100)))
    [pscustomobject]@{ Theme=$themeName; ChromeOnly=$true; NativeChromeApplied=$true; RenderingMode='native-chrome-only'; BackupPath=$backup; SettingsPath=$SettingsPath } | ConvertTo-Json -Compress
    return
}
# Ornate animation is a background Image underneath the text, never a post-text shader.
[IO.Directory]::CreateDirectory($AssetRoot) | Out-Null
$animationFrames = 1
if ($Style -eq 'Ornate') {
    $assetName = if ($DisableEffects) { 'ink-jade-ornate-v2.png' } else { 'ink-jade-background-v5.gif' }
    $source = Join-Path $PSScriptRoot ('assets/' + $assetName)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Background asset is missing: $source" }
    Add-Type -AssemblyName System.Drawing
    $image = [Drawing.Image]::FromFile($source)
    try {
        if ($image.Width -lt 1024 -or $image.Height -lt 512) { throw 'Background asset resolution is too small.' }
        if (-not $DisableEffects) {
            $animationFrames = $image.GetFrameCount([Drawing.Imaging.FrameDimension]::Time)
            if ($animationFrames -lt 2) { throw 'Animated background has no animation frames.' }
        }
    } finally { $image.Dispose() }
    $backgroundPath = Join-Path $AssetRoot $assetName
    $alreadyInstalled = (Test-Path -LiteralPath $backgroundPath -PathType Leaf) -and ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $backgroundPath).Hash)
    if (-not $alreadyInstalled -and [IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($backgroundPath)) {
        Copy-Item -LiteralPath $source -Destination $backgroundPath -Force
    }
} else {
Add-Type -AssemblyName System.Drawing
$backgroundPath = Join-Path $AssetRoot 'ink-jade-mountains.png'
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

if (-not $BackgroundOnly) {
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
    $defaults.PSObject.Properties.Remove('experimental.pixelShaderPath')
    Set-Property $defaults 'experimental.retroTerminalEffect' $false
} else { $defaults.PSObject.Properties.Remove('experimental.pixelShaderPath') }
$theme = [pscustomobject]@{
    name = 'OmniVibe Ink Jade'
    window = [pscustomobject]@{ applicationTheme = 'dark' }
    tab = [pscustomobject]@{ background = '#2A4035'; unfocusedBackground = '#17251E'; showCloseButton = 'hover' }
    tabRow = [pscustomobject]@{ background = '#0D1612'; unfocusedBackground = '#0D1612' }
}
if ($Style -eq 'Ornate') { $theme.name = 'OmniVibe Ink Jade Ornate' }
$theme = Get-OmniVibeTerminalChrome $theme '#0D1612' '#D6B674' '#2A4035'
Set-Property $settings 'themes' (@($settings.themes | Where-Object { $_.name -ne $theme.name }) + @($theme))
Set-Property $settings 'theme' $theme.name

} else {
    if ($null -eq $settings.profiles.defaults) { throw '-BackgroundOnly requires an existing default profile.' }
    $defaults = $settings.profiles.defaults
    Set-Property $defaults 'backgroundImage' $backgroundPath
    if ($null -eq $defaults.backgroundImageOpacity) { Set-Property $defaults 'backgroundImageOpacity' 0.5 }
    if ($null -eq $defaults.backgroundImageStretchMode) { Set-Property $defaults 'backgroundImageStretchMode' 'fill' }
    $defaults.PSObject.Properties.Remove('experimental.pixelShaderPath')
    Set-Property $defaults 'experimental.retroTerminalEffect' $false
}
# Explicit old images/shaders on profiles and unfocused appearances otherwise
# override the migrated defaults. Preserve all unrelated per-profile styling.
$targets = @($settings.profiles.defaults) + @($settings.profiles.list)
foreach ($target in $targets) {
    if ($null -eq $target) { continue }
    $appearances = @($target)
    if ($null -ne $target.unfocusedAppearance) { $appearances += $target.unfocusedAppearance }
    foreach ($appearance in $appearances) {
        if ($Style -eq 'Ornate') {
            if ([string]$appearance.backgroundImage -match 'ink-jade-(ornate-v2\.png|background-v\d+\.gif)$') {
                Set-Property $appearance 'backgroundImage' $backgroundPath
            }
            if ([string]$appearance.'experimental.pixelShaderPath' -match 'ornate-frame-v2\.hlsl$') {
                $appearance.PSObject.Properties.Remove('experimental.pixelShaderPath')
                Set-Property $appearance 'experimental.retroTerminalEffect' $false
            }
        }
    }
}
$updated = $settings | ConvertTo-Json -Depth 100
$null = $updated | ConvertFrom-Json
$backup = Write-Settings ($utf8.GetBytes($updated))
[pscustomobject]@{
    Theme = $settings.theme; Style = $Style; SettingsPath = $SettingsPath; BackupPath = $backup
    BackgroundPath = $backgroundPath; BackgroundOnly = [bool]$BackgroundOnly
    RenderingMode = $(if ($Style -eq 'Ornate' -and -not $DisableEffects) { 'background-gif' } else { 'background-png' })
    EffectsEnabled = ($Style -eq 'Ornate' -and -not $DisableEffects)
    AnimationFrames = $animationFrames; ShaderEnabled = $false; ShaderCompiledBytes = 0
} | ConvertTo-Json -Compress
