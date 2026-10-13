# Reliability test: N times, boot the game and drive it to the race briefing
# with to_race.ps1, then report the outcome (briefing / crash / timeout).
#   powershell -File tools\race_test.ps1 [-Runs 3] [-TimeoutSec 480] [-Env @{...}]
param([int]$Runs = 3, [int]$TimeoutSec = 480, [hashtable]$Env = @{})

$root = Split-Path -Parent $PSScriptRoot
$live = Join-Path $PSScriptRoot "live.ps1"
$nav = Join-Path $PSScriptRoot "to_race.ps1"

for ($i = 1; $i -le $Runs; $i++) {
    & $live start -Env $Env | Out-Null
    Start-Sleep -Seconds 15
    $out = & $nav -TimeoutSec $TimeoutSec 2>&1 | Select-Object -Last 1
    $err = Get-Content (Join-Path $root "stderr.txt") -ErrorAction SilentlyContinue
    $crash = ($err | Select-String -SimpleMatch "[CRASH]" | Select-Object -First 1)
    $result = if ($out -match "briefing") { "OK   reached the race briefing" }
              elseif ($crash) { "CRASH $crash" }
              else { "FAIL $out" }
    "run ${i}: $result"
    if ($result -like "FAIL*") {
        # A stall: dump every thread (and the RECOMP_JOB_TRACE ring) before
        # the run is killed; the log is kept in logs\ by the next start.
        & $live dump | Out-Null
        Start-Sleep -Seconds 4
    }
    & $live stop | Out-Null
    Start-Sleep -Seconds 3
}
