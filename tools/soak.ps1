# Soak test: boot, drive into a race, then race back to back for -Minutes.
# In the race A is tapped now and then; after the finish A picks "Restart",
# which opens a confirm dialog (256 draws) where up + A answers "Yes" and the
# race restarts from its briefing (A again). Stops on a crash, or on a hang:
# FPS 0 for -HangSec seconds (threads + job ring dumped first, kept in logs\).
#   powershell -File tools\soak.ps1 [-Minutes 120] [-HangSec 60] [-Env @{...}]
param([int]$Minutes = 120, [int]$HangSec = 60, [hashtable]$Env = @{})

$root = Split-Path -Parent $PSScriptRoot
$live = Join-Path $PSScriptRoot "live.ps1"
$nav  = Join-Path $PSScriptRoot "to_race.ps1"
$err  = Join-Path $root "stderr.txt"

$start = Get-Date
& $live start -Env $Env | Out-Null
Start-Sleep -Seconds 15
$navOut = & $nav -TimeoutSec 480 2>&1 | Select-Object -Last 1
if ($navOut -notmatch "briefing") {
    "soak: FAIL before the first race ($navOut)"
    & $live dump | Out-Null; Start-Sleep -Seconds 20; & $live stop | Out-Null
    exit 1
}

$races = 1; $restarts = 0; $frozenSince = $null; $result = "OK"
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
    $title = & $live snap -Out "soak.png" 2>$null
    if ($title -eq "not running") { $result = "CRASH (process gone)"; break }
    if (@(Get-Content $err -ErrorAction SilentlyContinue | Select-String -SimpleMatch "[CRASH]").Count) {
        $result = "CRASH (" + (Get-Content $err | Select-String -SimpleMatch "[CRASH]" | Select-Object -First 1) + ")"
        break
    }
    if ($title -match "FPS: ([\d.]+) \| draws: (\d+)") {
        $fps = [double]$Matches[1]; $draws = [int]$Matches[2]
        if ($fps -eq 0) {
            if (-not $frozenSince) { $frozenSince = Get-Date }
            elseif (((Get-Date) - $frozenSince).TotalSeconds -ge $HangSec) {
                $result = "HANG (FPS 0 for ${HangSec}s at $draws draws)"; break
            }
        } else { $frozenSince = $null }
        if ($draws -eq 256) {                    # "Restart -- Are you sure?"
            & $live press -Buttons "up:200" | Out-Null
            Start-Sleep -Milliseconds 800
            & $live press -Buttons "a:300" | Out-Null
            $restarts++; $races++
            "soak: race $races (restart $restarts) at {0:N0} min" -f ((Get-Date) - $start).TotalMinutes
            Start-Sleep -Seconds 10
            & $live press -Buttons "a:300" | Out-Null   # dismiss the briefing
        } else {
            & $live press -Buttons "a:200" | Out-Null
        }
    }
    Start-Sleep -Seconds 8
}
if ($result -ne "OK") {
    & $live dump | Out-Null; Start-Sleep -Seconds 20
}
& $live stop | Out-Null
"soak: {0} after {1:N1} min, {2} races" -f $result, ((Get-Date) - $start).TotalMinutes, $races
