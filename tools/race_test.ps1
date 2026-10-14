# Reliability test: N times, boot the game and drive it to the race briefing
# with to_race.ps1, then report the outcome (briefing / crash / timeout).
#   powershell -File tools\race_test.ps1 [-Runs 3] [-TimeoutSec 480] [-Env @{...}] [-Dir instance]
# (-Dir: run in an instance directory, see live.ps1; tools\race_par.ps1 runs
# several of these at once.)
param([int]$Runs = 3, [int]$TimeoutSec = 480, [hashtable]$Env = @{}, [string]$Dir = "")

$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$live = Join-Path $PSScriptRoot "live.ps1"
$nav = Join-Path $PSScriptRoot "to_race.ps1"

for ($i = 1; $i -le $Runs; $i++) {
    & $live start -Env $Env -Dir $Dir | Out-Null
    Start-Sleep -Seconds 15
    $out = & $nav -TimeoutSec $TimeoutSec -Dir $Dir 2>&1 | Select-Object -Last 1
    $err = Get-Content (Join-Path $root "stderr.txt") -ErrorAction SilentlyContinue
    $crash = ($err | Select-String -SimpleMatch "[CRASH]" | Select-Object -First 1)
    # Name the failure from the last screen seen: the known classes are a
    # pad that never enumerated (stuck on the title, < 200 draws), a hang in
    # the menus, and the race-load stall (309 / 22 = loading screens).
    $kind = ""
    if ($out -match "last screen: (\d+) draws") {
        $d = [int]$Matches[1]
        $kind = if ($d -eq 309 -or $d -eq 22) { "[load stall] " }
                elseif ($d -lt 200) { "[title: no input] " }
                elseif (@(339, 984, 382, 275, 367, 413, 329) -contains $d -or $d -ge 900) { "[menu hang] " }
                else { "[other] " }
    }
    $result = if ($out -match "briefing") { "OK   reached the race briefing" }
              elseif ($crash) { "CRASH $crash" }
              else { "FAIL $kind$out" }
    "run ${i}: $result"
    if ($result -like "FAIL*") {
        # A stall: dump every thread (and the RECOMP_JOB_TRACE ring) before
        # the run is killed; the log is kept in logs\ by the next start.
        & $live dump -Dir $Dir | Out-Null
        # The dump (threads + the 4096-entry job ring) takes a while to write.
        Start-Sleep -Seconds 20
    }
    & $live stop -Dir $Dir | Out-Null
    Start-Sleep -Seconds 3
}
