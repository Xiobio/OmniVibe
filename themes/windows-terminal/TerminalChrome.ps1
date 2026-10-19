# Native Terminal theme colors only: no overlay, window subclass or animation loop.
function Get-OmniVibeChromeColor([string]$From, [string]$To, [double]$Amount) {
    if ($From -notmatch '^#[0-9a-fA-F]{6}$' -or $To -notmatch '^#[0-9a-fA-F]{6}$') { throw 'Chrome palette requires RGB hex colors.' }
    $channels = foreach ($offset in @(1,3,5)) {
        $a = [Convert]::ToInt32($From.Substring($offset,2),16)
        $b = [Convert]::ToInt32($To.Substring($offset,2),16)
        [int][Math]::Round($a + ($b - $a) * $Amount)
    }
    return ('#{0:X2}{1:X2}{2:X2}' -f $channels[0],$channels[1],$channels[2])
}
function Set-OmniVibeChromeProperty($Target, [string]$Name, $Value) {
    $Target | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}
function Get-OmniVibeTerminalChrome($Theme, [string]$Background, [string]$Accent, [string]$Surface) {
    # Clone so the source palette and unrelated settings remain untouched.
    $result = $Theme | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    foreach ($part in @('window','tab','tabRow')) {
        if ($null -eq $result.$part) { Set-OmniVibeChromeProperty $result $part ([pscustomobject]@{}) }
        if ($result.$part -isnot [pscustomobject]) { throw "Invalid native theme section: $part" }
    }
    $row = Get-OmniVibeChromeColor (Get-OmniVibeChromeColor $Background $Surface .55) $Accent .035
    $quietRow = Get-OmniVibeChromeColor $Background $row .55
    # The selected native tab shares the pane's base color; inactive tabs recede
    # into the row. Do not set tabColor on profiles, which would override this.
    Set-OmniVibeChromeProperty $result.tab 'background' $Background
    Set-OmniVibeChromeProperty $result.tab 'unfocusedBackground' $row
    Set-OmniVibeChromeProperty $result.tabRow 'background' $row
    Set-OmniVibeChromeProperty $result.tabRow 'unfocusedBackground' $quietRow
    Set-OmniVibeChromeProperty $result.window 'frame' (Get-OmniVibeChromeColor $Background $Accent .55)
    Set-OmniVibeChromeProperty $result.window 'unfocusedFrame' (Get-OmniVibeChromeColor $Background $Accent .20)
    # Optional native border colors depend on Terminal/Windows support; the
    # supported tab/row palette is sufficient on hosts that ignore these keys.
    Set-OmniVibeChromeProperty $result.window 'experimental.rainbowFrame' $false
    return $result
}

function Get-OmniVibeTerminalChromePresets {
    $manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'skins.json')) | ConvertFrom-Json
    $classic = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'classic-palettes.json')) | ConvertFrom-Json
    foreach ($entry in $manifest.skins) {
        $palette = $entry.chromePalette
        if ($null -eq $palette) { throw "Native chrome palette missing: $($entry.slug)" }
        [pscustomobject]@{slug=$entry.slug; theme=$entry.theme; background=$palette.background; accent=$palette.accent; surface=$palette.surface}
    }
    foreach ($entry in $classic) {
        $theme = [pscustomobject]@{
            name=('OmniVibe / ' + $entry.name)
            window=[pscustomobject]@{applicationTheme='dark'}
            tab=[pscustomobject]@{showCloseButton='hover'}
        }
        [pscustomobject]@{slug=$entry.slug; theme=$theme; background=$entry.background; accent=$entry.accent; surface=$entry.surface}
    }
}
