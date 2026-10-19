param([string]$ReportPath='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Join-Path $PSScriptRoot 'assets/refined-v1'
$reports=@()
foreach($file in (Get-ChildItem -LiteralPath $root -Filter '*.gif')) {
    $image=[Drawing.Image]::FromFile($file.FullName)
    try {
        $count=$image.GetFrameCount([Drawing.Imaging.FrameDimension]::Time)
        if($count -ne 96){throw ('Incomplete native GIF: '+$file.Name)}
        $center=$image.GetPixel(640,377).ToArgb()
        $samples=New-Object 'System.Collections.Generic.HashSet[int]'
        for($i=0;$i -lt $count;$i++){
            $null=$image.SelectActiveFrame([Drawing.Imaging.FrameDimension]::Time,$i)
            if($image.GetPixel(640,377).ToArgb() -ne $center){throw ('Native decoder changed the reading area: '+$file.Name)}
            $null=$samples.Add($image.GetPixel(512,4).ToArgb())
        }
        if($samples.Count -lt 2){throw ('Native decoder found no rim movement: '+$file.Name)}
        $reports += [ordered]@{file=$file.Name;frames=$count;centerStatic=$true;rimAnimation=$true;rimSampleColors=$samples.Count}
    } finally {$image.Dispose()}
}
if($reports.Count -ne 20){throw 'Expected ten artwork animations and ten independent frame-only animations.'}
if(-not ('OmniVibeFrameLayout' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'FrameLayout.cs')}
$dimensions=[OmniVibeFrameLayout]::MaximumLogicalScreen()
$report=[ordered]@{passed=$true;nativeGifCount=$reports.Count;nativeDecodedFrames=($reports.Count*96);files=$reports;logicalScreen=$dimensions;padding=[OmniVibeFrameLayout]::Padding($dimensions[0],$dimensions[1]);actualTerminalPlaybackVisuallyVerified=$false}
$json=$report|ConvertTo-Json -Depth 10
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),$json,(New-Object Text.UTF8Encoding($false)))}
$json
