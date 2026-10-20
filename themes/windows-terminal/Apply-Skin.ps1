param(
    [ValidateSet('ink-jade','midnight','cinnabar','hextech','tactical','protocol','adventure','arsenal','relic','starlight','formation','astral','wonderland')]
    [string]$Skin = '',
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'),
    [string]$RestoreFrom = '',
    [switch]$DisableEffects,
    [switch]$EnableAnimation,
    [switch]$DisableArtwork,
    [switch]$AllProfiles,
    [switch]$ChromeOnly,
    [switch]$RegisterAllChrome,
    [string]$AssetRoot = (Join-Path $env:LOCALAPPDATA 'OmniVibe/TerminalTheme')
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if (-not $Skin -and -not $RestoreFrom -and -not $RegisterAllChrome) { throw 'Select -Skin <slug>, -RegisterAllChrome, or -RestoreFrom <backup.json>.' }
if ($Skin -and $RestoreFrom) { throw '-Skin and -RestoreFrom cannot be combined.' }
if ($EnableAnimation -and ($DisableEffects -or $RestoreFrom)) { throw '-EnableAnimation cannot be combined with -DisableEffects or -RestoreFrom.' }
if ($RegisterAllChrome -and ($Skin -or $RestoreFrom -or $ChromeOnly -or $DisableEffects -or $EnableAnimation -or $DisableArtwork -or $AllProfiles)) { throw '-RegisterAllChrome only registers native presets and preserves the selected theme; do not combine it with other appearance options.' }
if ($ChromeOnly -and ($RestoreFrom -or $DisableEffects -or $EnableAnimation -or $DisableArtwork -or $AllProfiles)) { throw '-ChromeOnly changes native theme colors only; do not combine it with restore or profile options.' }
if ($Skin -in @('ink-jade','midnight','cinnabar') -and -not $ChromeOnly) { throw 'Classic themes support native chrome via -ChromeOnly; illustrated game backgrounds are separate presets.' }
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'Windows Terminal settings.json was not found.' }
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
. (Join-Path $PSScriptRoot 'TerminalChrome.ps1')
function Read-Settings([string]$Text) {
    $value = [OmniVibeJsonc]::Normalize($Text) | ConvertFrom-Json
    if ($null -eq $value -or $value -is [array] -or $value -isnot [pscustomobject]) { throw 'Terminal settings must be a JSON object.' }
    return $value
}
function Set-Property($Object, [string]$Name, $Value) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force }
$settingsFullPath = (Resolve-Path -LiteralPath $SettingsPath).Path
$original = [IO.File]::ReadAllText($settingsFullPath)
$settings = Read-Settings $original
$utf8 = New-Object Text.UTF8Encoding($false)
$animated = [bool]$EnableAnimation
if ($RestoreFrom) {
    $restorePath = (Resolve-Path -LiteralPath $RestoreFrom).Path
    $restoreBytes = [IO.File]::ReadAllBytes($restorePath)
    $updated = [IO.File]::ReadAllText($restorePath)
    $null = Read-Settings $updated
} else {
    if ($null -ne $settings.themes -and $settings.themes -isnot [array]) { throw 'themes must be a JSON array.' }
    $presets = @(Get-OmniVibeTerminalChromePresets)
    if ($presets.Count -ne 13 -or @($presets.slug | Select-Object -Unique).Count -ne 13) { throw 'Expected 13 unique native chrome presets.' }
    $selected = @($presets | Where-Object { $RegisterAllChrome -or $_.slug -eq $Skin })
    if (-not $RegisterAllChrome -and $selected.Count -ne 1) { throw "Native chrome preset is missing or duplicated: $Skin" }
    foreach ($preset in $selected) {
        $themeSource = @($settings.themes | Where-Object { $_.name -eq $preset.theme.name }) | Select-Object -First 1
        if ((-not $ChromeOnly -and -not $RegisterAllChrome) -or $null -eq $themeSource) { $themeSource = $preset.theme }
        $nativeTheme = Get-OmniVibeTerminalChrome $themeSource $preset.background $preset.accent $preset.surface
        Set-Property $settings 'themes' (@($settings.themes | Where-Object { $_.name -ne $preset.theme.name }) + @($nativeTheme))
    }
    if (-not $RegisterAllChrome) { Set-Property $settings 'theme' $selected[0].theme.name }
    $shaderBytes = 0; $animationFrames = 0; $safePadding = $null; $backgroundEnabled = $false
    if (-not $ChromeOnly -and -not $RegisterAllChrome) {
    $manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'skins.json')) | ConvertFrom-Json
    $entry = @($manifest.skins | Where-Object { $_.slug -eq $Skin })
    if ($entry.Count -ne 1) { throw "Skin manifest entry is missing or duplicated: $Skin" }
    $entry = $entry[0]
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $illustration = Join-Path $repoRoot $entry.artwork
    if (-not $DisableArtwork -and -not (Test-Path -LiteralPath $illustration -PathType Leaf)) { throw "Skin illustration is missing: $illustration" }
    $shaderBytes = 0
    $refinedRoot = Join-Path $PSScriptRoot 'assets/refined-v1'
    $suffix = if ($DisableArtwork) { 'frame-only-v1' } else { 'c-v1' }
    # Animation repeatedly decodes and repaints every open Terminal background.
    # Keep the complete illustrated frame by default, with motion explicitly opt-in.
    $extension = if ($animated) { '.gif' } else { '.png' }
    $sourceBackground = Join-Path $refinedRoot ($Skin + '-' + $suffix + $extension)
    $backgroundEnabled = -not ($DisableArtwork -and $DisableEffects)
    if ($backgroundEnabled -and -not (Test-Path -LiteralPath $sourceBackground -PathType Leaf)) { throw "Refined C-layout background is missing: $sourceBackground" }
    $animationFrames = 0
    if ($backgroundEnabled) {
        Add-Type -AssemblyName System.Drawing
        $image = [Drawing.Image]::FromFile($sourceBackground)
        try {
            if ($image.Width -ne 1280 -or $image.Height -ne 754) { throw 'Unexpected refined background dimensions.' }
            $animationFrames = if ($animated) { $image.GetFrameCount([Drawing.Imaging.FrameDimension]::Time) } else { 1 }
            if ($animated -and $animationFrames -ne 96) { throw 'Refined background animation is incomplete.' }
        } finally { $image.Dispose() }
    }
    if (-not ('OmniVibeFrameLayout' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'FrameLayout.cs') }
    $layout = [OmniVibeFrameLayout]::MaximumLogicalScreen()
    $safePadding = [OmniVibeFrameLayout]::Padding($layout[0],$layout[1])
    $skinAssets = Join-Path $AssetRoot $Skin
    [IO.Directory]::CreateDirectory($skinAssets) | Out-Null
    $backgroundPath = ''
    if ($backgroundEnabled) {
        # A content-addressed URI refreshes already-open Terminal tabs even when
        # a resource is revised; it also avoids overwriting a locked live GIF.
        $hash = (Get-FileHash -LiteralPath $sourceBackground -Algorithm SHA256).Hash.Substring(0,12).ToLowerInvariant()
        $backgroundPath = Join-Path $skinAssets ($Skin + '-' + $suffix + '-' + $hash + $extension)
        if (-not (Test-Path -LiteralPath $backgroundPath -PathType Leaf)) { Copy-Item -LiteralPath $sourceBackground -Destination $backgroundPath }
    }
    Set-Property $settings 'schemes' (@($settings.schemes | Where-Object { $_.name -ne $entry.scheme.name }) + @($entry.scheme))
    if ($null -eq $settings.profiles) { Set-Property $settings 'profiles' ([pscustomobject]@{}) }
    if ($settings.profiles -isnot [pscustomobject]) { throw 'profiles must be a JSON object; legacy array-format profiles are not modified.' }
    if ($null -eq $settings.profiles.defaults) { Set-Property $settings.profiles 'defaults' ([pscustomobject]@{}) }
    if ($settings.profiles.defaults -isnot [pscustomobject]) { throw 'profiles.defaults must be a JSON object.' }
    if ($null -ne $settings.profiles.list -and $settings.profiles.list -isnot [array]) { throw 'profiles.list must be a JSON array.' }
    if (@($settings.profiles.list | Where-Object { $null -ne $_ -and $_ -isnot [pscustomobject] }).Count -gt 0) { throw 'Every profiles.list entry must be a JSON object.' }
    $targets = @($settings.profiles.defaults)
    if ($AllProfiles) { $targets += @($settings.profiles.list | Where-Object { $null -ne $_ }) }
    $appearanceTargets = @($targets)
    foreach ($target in $targets) {
        if ($null -ne $target.unfocusedAppearance) {
            if ($target.unfocusedAppearance -isnot [pscustomobject]) { throw 'unfocusedAppearance must be a JSON object.' }
            $appearanceTargets += $target.unfocusedAppearance
        }
    }
    foreach ($target in $appearanceTargets) {
        # Only appearance fields are changed. Commands, cwd, GUIDs, keybindings,
        # defaultProfile, environment and every unrelated setting survive.
        Set-Property $target 'colorScheme' $entry.scheme.name
        # Explicit per-profile colors override colorScheme in Terminal. Remove
        # them only on profiles selected above so light/dark switching is safe.
        foreach ($field in @('foreground','background','cursorColor','selectionBackground')) { $target.PSObject.Properties.Remove($field) }
        Set-Property $target 'padding' $safePadding
        Set-Property $target 'antialiasingMode' 'grayscale'
        Set-Property $target 'opacity' 100
        Set-Property $target 'useAcrylic' $false
        if (-not $backgroundEnabled) {
            # Empty path + zero opacity prevents inherited images without
            # inventing a non-existent "none" file or relying on null fallback.
            Set-Property $target 'backgroundImage' ''
            Set-Property $target 'backgroundImageOpacity' 0.0
        } else {
            Set-Property $target 'backgroundImage' $backgroundPath
            # The artwork veil, tone mapping and C frame are precomposited.
            Set-Property $target 'backgroundImageOpacity' 1.0
            Set-Property $target 'backgroundImageStretchMode' 'fill'
            Set-Property $target 'backgroundImageAlignment' 'center'
        }
        Set-Property $target 'experimental.retroTerminalEffect' $false
        $target.PSObject.Properties.Remove('experimental.pixelShaderPath')
    }
    }
    $updated = $settings | ConvertTo-Json -Depth 100
    $null = Read-Settings $updated
}
# Validate every dependency before creating a backup or touching settings. A
# byte-for-byte backup preserves original comments and formatting for restore.
$backupRoot = Join-Path $AssetRoot 'Backups'
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$backup = Join-Path $backupRoot ('settings-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
if ([IO.File]::ReadAllText($settingsFullPath) -cne $original) { throw 'Terminal settings changed during this operation; nothing was overwritten.' }
[IO.File]::Copy($settingsFullPath, $backup, $false)
$temporary = Join-Path ([IO.Path]::GetDirectoryName($settingsFullPath)) ('.omnivibe-settings-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    if ($RestoreFrom) { [IO.File]::WriteAllBytes($temporary, $restoreBytes) }
    else { [IO.File]::WriteAllText($temporary, $updated, $utf8) }
    if ([IO.File]::ReadAllText($settingsFullPath) -cne $original) { throw 'Terminal settings changed during this operation; nothing was overwritten.' }
    [IO.File]::Replace($temporary, $settingsFullPath, [NullString]::Value)
} finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
[pscustomobject]@{
    Skin = $Skin; Restored = [bool]$RestoreFrom; SettingsPath = $settingsFullPath
    BackupPath = $backup; EffectsEnabled = $(if ($ChromeOnly -or $RegisterAllChrome) {$null} else {-not $RestoreFrom -and $animated})
    ArtworkEnabled = $(if ($ChromeOnly -or $RegisterAllChrome) {$null} else {-not $RestoreFrom -and -not $DisableArtwork})
    ShaderCompiledBytes = $shaderBytes; AllProfiles = [bool]$AllProfiles
    RenderingMode = $(if ($RestoreFrom) {'restored'} elseif ($RegisterAllChrome) {'native-chrome-register-all'} elseif ($ChromeOnly) {'native-chrome-only'} elseif (-not $backgroundEnabled) {'plain'} elseif ($animated) {'background-gif'} else {'background-png'})
    NativeChromeApplied = (-not $RestoreFrom); ChromeOnly = [bool]$ChromeOnly
    RegisteredThemeCount = $(if ($RegisterAllChrome) {$selected.Count} else {0})
    FrameLayout = $(if ($ChromeOnly -or $RegisterAllChrome) {'unchanged'} else {'C'}); AnimationFrames = $animationFrames; Padding = $safePadding
} | ConvertTo-Json -Compress
