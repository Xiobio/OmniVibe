param([switch]$Validate, [switch]$RequireArtwork, [string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$catalog = [IO.File]::ReadAllText((Join-Path $repoRoot 'skins/catalog.json')) | ConvertFrom-Json
$utf8 = New-Object Text.UTF8Encoding($false)
. (Join-Path $PSScriptRoot 'TerminalChrome.ps1')
function RGB([string]$Hex) {
    return ,@([Convert]::ToInt32($Hex.Substring(1,2),16),[Convert]::ToInt32($Hex.Substring(3,2),16),[Convert]::ToInt32($Hex.Substring(5,2),16))
}
function Hex($Values) { return '#{0:X2}{1:X2}{2:X2}' -f [int][Math]::Round($Values[0]),[int][Math]::Round($Values[1]),[int][Math]::Round($Values[2]) }
function Blend([string]$First,[string]$Second,[double]$Amount) {
    $a = RGB $First; $b = RGB $Second
    return Hex @((0..2 | ForEach-Object { $a[$_] * (1-$Amount) + $b[$_] * $Amount }))
}
function Luminance([string]$Color) {
    $v = @(RGB $Color | ForEach-Object { $_ })
    $linear = foreach ($channel in $v) { $s = $channel / 255.0; if ($s -le 0.04045) { $s / 12.92 } else { [Math]::Pow(($s+0.055)/1.055,2.4) } }
    return 0.2126*$linear[0]+0.7152*$linear[1]+0.0722*$linear[2]
}
function Contrast([string]$Foreground,[string]$Background) {
    $a = Luminance $Foreground; $b = Luminance $Background
    return ([Math]::Max($a,$b)+0.05)/([Math]::Min($a,$b)+0.05)
}
function WorstContrast([string]$Foreground,[string]$Background,[double]$Opacity) {
    return [Math]::Min((Contrast $Foreground (Blend $Background '#000000' $Opacity)),(Contrast $Foreground (Blend $Background '#FFFFFF' $Opacity)))
}
function Readable([string]$Color,[string]$Background,[double]$Opacity) {
    $destination = if ((Luminance $Background) -gt 0.5) { '#000000' } else { '#FFFFFF' }
    for ($i=0; $i -le 100; $i++) {
        $candidate = Blend $Color $destination ($i / 100.0)
        if ((WorstContrast $candidate $Background $Opacity) -ge 4.55) { return $candidate }
    }
    throw "Cannot calibrate ANSI color $Color against $Background"
}
function HlslColor([string]$Color) {
    $channels = (RGB $Color) | ForEach-Object { ($_/255.0).ToString('0.000000',[Globalization.CultureInfo]::InvariantCulture) }
    return 'float3(' + ($channels -join ',') + ')'
}
if ($Validate -and -not ('OmniVibeShaderCompiler' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ShaderCompiler.cs') }
if ($Validate) { Add-Type -AssemblyName System.Drawing }
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'shaders/frame-template.hlsl'))
$entries = @(); $results = @()
foreach ($skin in $catalog) {
    $opacity = 0.12
    $light = (Luminance $skin.background) -gt 0.5
    $seeds = [ordered]@{
        black = $skin.muted; red = $skin.error; green = $skin.running; yellow = $skin.waiting
        blue = $(if ($light) {'#235C96'} else {'#81B6EF'})
        purple = $(if ($light) {'#7B3982'} else {'#D1ACEB'}); cyan = $skin.secondary; white = $skin.text
        brightBlack = (Blend $skin.muted $skin.text 0.3); brightRed = (Blend $skin.error $skin.text 0.2)
        brightGreen = (Blend $skin.running $skin.text 0.2); brightYellow = (Blend $skin.waiting $skin.text 0.2)
        brightBlue = $(if ($light) {'#174E8A'} else {'#ADD1FF'})
        brightPurple = $(if ($light) {'#6B2C75'} else {'#E6C8FF'})
        brightCyan = (Blend $skin.secondary $skin.text 0.2); brightWhite = $skin.text
    }
    $scheme = [ordered]@{
        name = 'OmniVibe / ' + $skin.name; background = $skin.background
        foreground = (Readable $skin.text $skin.background $opacity)
        cursorColor = (Readable $skin.accent $skin.background $opacity)
        selectionBackground = (Blend $skin.background $skin.accent 0.24)
    }
    foreach ($key in $seeds.Keys) { $scheme[$key] = Readable $seeds[$key] $skin.background $opacity }
    $theme = [ordered]@{
        name = $scheme.name
        window = @{ applicationTheme = $(if ($light) {'light'} else {'dark'}) }
        tab = @{ background = $skin.surface; unfocusedBackground = $skin.background; showCloseButton = 'hover' }
        tabRow = @{ background = $skin.background; unfocusedBackground = $skin.background }
    }
    $theme = Get-OmniVibeTerminalChrome ([pscustomobject]$theme) $skin.background $skin.accent $skin.surface
    $design = [IO.File]::ReadAllText((Join-Path $PSScriptRoot ('shaders/designs/' + $skin.slug + '.hlsl')))
    $shader = $template.Replace('__SLUG__',$skin.slug).Replace('__DESIGN__',$design).Replace('__ACCENT__',(HlslColor $skin.accent)).Replace('__SECONDARY__',(HlslColor $skin.secondary))
    $relativeShader = 'shaders/' + $skin.slug + '.hlsl'
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot $relativeShader),$shader,$utf8)
    $bytes = 0
    if ($Validate) { $bytes = [OmniVibeShaderCompiler]::Validate($shader) }
    $artworkExists = Test-Path -LiteralPath (Join-Path $repoRoot $skin.artwork) -PathType Leaf
    if ($RequireArtwork -and -not $artworkExists) { throw "Missing illustration: $($skin.artwork)" }
    $artWidth = 0; $artHeight = 0
    if ($Validate -and $artworkExists) {
        $image = [Drawing.Image]::FromFile((Join-Path $repoRoot $skin.artwork))
        try {
            $artWidth = $image.Width; $artHeight = $image.Height
            if ($artWidth -lt 1024 -or $artHeight -lt 512) { throw "Illustration resolution is too small: $($skin.slug)" }
        } finally { $image.Dispose() }
    }
    $ratios = @($seeds.Keys | ForEach-Object { WorstContrast $scheme[$_] $skin.background $opacity })
    $entries += [ordered]@{ slug=$skin.slug; name=$skin.name; scheme=$scheme; theme=$theme; chromePalette=@{background=$skin.background; accent=$skin.accent; surface=$skin.surface}; artwork=$skin.artwork; shader=$relativeShader; imageOpacity=$opacity; decorationWidthDip=24; padding='36, 32, 36, 32' }
    $results += [ordered]@{
        slug=$skin.slug; name=$skin.name; ansiColors=16
        minimumAnsiContrast=[Math]::Round(($ratios | Measure-Object -Minimum).Minimum,3)
        foregroundContrast=[Math]::Round((WorstContrast $scheme.foreground $skin.background $opacity),3)
        runningContrast=[Math]::Round((WorstContrast $scheme.green $skin.background $opacity),3)
        waitingContrast=[Math]::Round((WorstContrast $scheme.yellow $skin.background $opacity),3)
        errorContrast=[Math]::Round((WorstContrast $scheme.red $skin.background $opacity),3)
        shaderModel='ps_4_0'; shaderCompiledBytes=$bytes; artworkExists=[bool]$artworkExists
        artworkWidth=$artWidth; artworkHeight=$artHeight
        contrastIncludesWorstCaseImage=$true; centralGlyphTextureUnchanged=$true
    }
}
$manifest = [ordered]@{ version=1; paletteSource='skins/catalog.json'; skins=$entries }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'skins.json'),($manifest | ConvertTo-Json -Depth 30),$utf8)
if ($ReportPath) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($results | ConvertTo-Json -Depth 10),$utf8)
}
$results | ConvertTo-Json -Depth 10
