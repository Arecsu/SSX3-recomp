# Frame-time benchmark: boot, drive into a race (to_race.ps1), then sample the
# [FRAMES] lines (RECOMP_FRAME_STATS, one per second: fps, p50/p99/max frame
# time) for -Seconds of riding. Writes logs\bench_<timestamp>.json and prints
# a one-line summary. ROADMAP gate: p99 <= 16.7 ms.
#   powershell -File tools\bench.ps1 [-Seconds 120] [-Env @{...}] [-Label name]
param([int]$Seconds = 120, [hashtable]$Env = @{}, [string]$Label = "",
      [int]$TimeoutSec = 480)

$root = Split-Path -Parent $PSScriptRoot
$live = Join-Path $PSScriptRoot "live.ps1"
$nav  = Join-Path $PSScriptRoot "to_race.ps1"
$err  = Join-Path $root "stderr.txt"

$Env["RECOMP_FRAME_STATS"] = "1"
& $live start -Env $Env | Out-Null
Start-Sleep -Seconds 15
$navOut = & $nav -TimeoutSec $TimeoutSec 2>&1 | Select-Object -Last 1
if ($navOut -notmatch "briefing") {
    & $live stop | Out-Null
    "bench: did not reach the race ($navOut)"
    exit 1
}
# Make sure the briefing is dismissed, then let the race start.
Start-Sleep -Seconds 8
& $live press -Buttons "a:300" | Out-Null
Start-Sleep -Seconds 30

$skip = @(Get-Content $err | Select-String -SimpleMatch "[FRAMES]").Count
$rows = @()
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    # A tap of A now and then: jumps/tricks keep the scene moving.
    & $live press -Buttons "a:200" | Out-Null
    Start-Sleep -Seconds 5
}
$lines = @(Get-Content $err | Select-String -SimpleMatch "[FRAMES]") | Select-Object -Skip $skip
foreach ($l in $lines) {
    if ($l.Line -match "n (\d+) fps ([\d.]+) p50 ([\d.]+) p99 ([\d.]+) max ([\d.]+) ms draws (\d+)") {
        $rows += [pscustomobject]@{ n = [int]$Matches[1]; fps = [double]$Matches[2];
            p50 = [double]$Matches[3]; p99 = [double]$Matches[4];
            max = [double]$Matches[5]; draws = [int]$Matches[6] }
    }
}
$crash = @(Get-Content $err | Select-String -SimpleMatch "[CRASH]").Count
& $live stop | Out-Null
if ($rows.Count -eq 0) { "bench: no [FRAMES] samples"; exit 1 }

$frames = ($rows | Measure-Object n -Sum).Sum
$secs   = $rows.Count
$p50s   = $rows | ForEach-Object { $_.p50 } | Sort-Object
$summary = [pscustomobject]@{
    label      = $Label
    time       = (Get-Date).ToString("s")
    seconds    = $secs
    frames     = $frames
    fps_avg    = [math]::Round($frames / $secs, 1)
    p50_median = $p50s[[int]($p50s.Count / 2)]
    p99_worst  = ($rows | Measure-Object p99 -Maximum).Maximum
    max_worst  = ($rows | Measure-Object max -Maximum).Maximum
    crashes    = $crash
    gate_60fps = (($rows | Measure-Object p99 -Maximum).Maximum -le 16.7)
    env        = $Env
    per_second = $rows
}
$dir = Join-Path $root "logs"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir ("bench_" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path $out
"bench: {0} s, {1} fps avg, p50 {2} ms, p99 worst {3} ms, max {4} ms, crashes {5}, 60fps gate {6} -> {7}" -f `
    $secs, $summary.fps_avg, $summary.p50_median, $summary.p99_worst, $summary.max_worst, $crash,
    $summary.gate_60fps, (Split-Path -Leaf $out)
