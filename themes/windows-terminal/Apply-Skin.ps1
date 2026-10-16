param(
    [ValidateSet('hextech','tactical','protocol','adventure','arsenal','relic','starlight','formation','astral','wonderland')]
    [string]$Skin = '',
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'),
    [string]$RestoreFrom = '',
    [switch]$DisableEffects,
    [switch]$DisableArtwork,
    [switch]$AllProfiles,
    [string]$AssetRoot = (Join-Path $env:LOCALAPPDATA 'OmniVibe/TerminalTheme')
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if (-not $Skin -and -not $RestoreFrom) { throw 'Select a skin explicitly with -Skin <slug>, or supply -RestoreFrom <backup.json>.' }
if ($Skin -and $RestoreFrom) { throw '-Skin and -RestoreFrom cannot be combined.' }
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'Windows Terminal settings.json was not found.' }
if (-not ('OmniVibeJsonc' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Jsonc.cs') }
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
if ($RestoreFrom) {
    $restorePath = (Resolve-Path -LiteralPath $RestoreFrom).Path
    $restoreBytes = [IO.File]::ReadAllBytes($restorePath)
    $updated = [IO.File]::ReadAllText($restorePath)
    $null = Read-Settings $updated
} else {
    $manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'skins.json')) | ConvertFrom-Json
    $entry = @($manifest.skins | Where-Object { $_.slug -eq $Skin })
    if ($entry.Count -ne 1) { throw "Skin manifest entry is missing or duplicated: $Skin" }
    $entry = $entry[0]
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $illustration = Join-Path $repoRoot $entry.artwork
    if (-not $DisableArtwork -and -not (Test-Path -LiteralPath $illustration -PathType Leaf)) { throw "Skin illustration is missing: $illustration" }
    $shaderSource = Join-Path $PSScriptRoot $entry.shader
    $shaderBytes = 0
    if (-not $DisableEffects) {
        if (-not ('OmniVibeShaderCompiler' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ShaderCompiler.cs') }
        $shaderBytes = [OmniVibeShaderCompiler]::Validate([IO.File]::ReadAllText($shaderSource))
    }
    $skinAssets = Join-Path $AssetRoot $Skin
    [IO.Directory]::CreateDirectory($skinAssets) | Out-Null
    $backgroundPath = Join-Path $skinAssets 'illustration.png'
    $shaderPath = Join-Path $skinAssets 'frame.hlsl'
    if (-not $DisableArtwork) { Copy-Item -LiteralPath $illustration -Destination $backgroundPath -Force }
    if (-not $DisableEffects) { Copy-Item -LiteralPath $shaderSource -Destination $shaderPath -Force }
    Set-Property $settings 'schemes' (@($settings.schemes | Where-Object { $_.name -ne $entry.scheme.name }) + @($entry.scheme))
    Set-Property $settings 'themes' (@($settings.themes | Where-Object { $_.name -ne $entry.theme.name }) + @($entry.theme))
    Set-Property $settings 'theme' $entry.theme.name
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
        Set-Property $target 'padding' '36, 32, 36, 32'
        Set-Property $target 'antialiasingMode' 'grayscale'
        Set-Property $target 'opacity' 100
        Set-Property $target 'useAcrylic' $false
        if ($DisableArtwork) {
            # Empty path + zero opacity prevents inherited images without
            # inventing a non-existent "none" file or relying on null fallback.
            Set-Property $target 'backgroundImage' ''
            Set-Property $target 'backgroundImageOpacity' 0.0
        } else {
            Set-Property $target 'backgroundImage' $backgroundPath
            Set-Property $target 'backgroundImageOpacity' $entry.imageOpacity
            Set-Property $target 'backgroundImageStretchMode' 'uniformToFill'
            Set-Property $target 'backgroundImageAlignment' 'center'
        }
        Set-Property $target 'experimental.retroTerminalEffect' $false
        if ($DisableEffects) { $target.PSObject.Properties.Remove('experimental.pixelShaderPath') }
        else { Set-Property $target 'experimental.pixelShaderPath' $shaderPath }
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
    BackupPath = $backup; EffectsEnabled = (-not $RestoreFrom -and -not $DisableEffects)
    ArtworkEnabled = (-not $RestoreFrom -and -not $DisableArtwork)
    ShaderCompiledBytes = $shaderBytes; AllProfiles = [bool]$AllProfiles
} | ConvertTo-Json -Compress
