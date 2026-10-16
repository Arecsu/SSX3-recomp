# Every Race / Freestyle event on Peaks 1-3: where the game asks for its
# 30 Hz mode ([FPS30], ssx3_overrides.c sub_000CC8F0) and what FPS is reached.
#   powershell -File tools\fps30_scan.ps1 [-RideSec 180] [-Out logs\fps30_scan.txt]
param([int]$RideSec = 180, [string]$Out = "logs\fps30_scan.txt")
$root = Split-Path -Parent $PSScriptRoot
$live = Join-Path $root "tools\live.ps1"
$err = Join-Path $root "stderr.txt"
"fps30 scan $(Get-Date -Format s), ride $RideSec s" | Set-Content (Join-Path $root $Out)
foreach ($peak in 0, 1, 2) { foreach ($mode in 0, 1) { foreach ($ev in 0, 1, 2) {
    $e = @{ RECOMP_FRAME_STATS = "1"; RECOMP_AUTONAV = "race,rider=0,peak=$peak,mode=$mode,event=$ev" }
    & $live start -Env $e | Out-Null
    $t0 = Get-Date; $ok = $false
    while (((Get-Date) - $t0).TotalSeconds -lt 150) {
        if (Select-String -Path $err -Pattern "t=\d+ at the briefing" -List -ErrorAction SilentlyContinue) { $ok = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if ($ok) {
        $tr = Get-Date
        while (((Get-Date) - $tr).TotalSeconds -lt $RideSec) { & $live press -Buttons "a:200" | Out-Null; Start-Sleep -Seconds 5 }
    }
    $lines = @(Get-Content $err)
    & $live stop | Out-Null
    $f30 = @($lines | Select-String -SimpleMatch "[FPS30]" | ForEach-Object { $_.Line })
    $fps = @($lines | Select-String -Pattern "\[FRAMES\].* fps ([\d.]+)" | ForEach-Object { [double]$_.Matches[0].Groups[1].Value })
    $min = if ($fps.Count) { ($fps | Select-Object -Skip 3 | Measure-Object -Minimum).Minimum } else { "-" }
    $n30 = @($f30 | Where-Object { $_ -match "wants 30" }).Count
    $row = "peak $peak mode $mode event $ev : briefing=$ok  30Hz requests=$n30  min fps=$min  crash=$(@($lines | Select-String -SimpleMatch '[CRASH]').Count)"
    $row | Add-Content (Join-Path $root $Out)
    $f30 | ForEach-Object { "    $_" } | Add-Content (Join-Path $root $Out)
    Copy-Item $err (Join-Path $root ("logs\fps30_p{0}m{1}e{2}_stderr.txt" -f $peak, $mode, $ev)) -Force
}}}
"done" | Add-Content (Join-Path $root $Out)
