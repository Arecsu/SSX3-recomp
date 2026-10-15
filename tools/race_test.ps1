# Reliability test: N times, boot the game and drive it to the race briefing
# with to_race.ps1, then report the outcome (briefing / crash / timeout).
#   powershell -File tools\race_test.ps1 [-Runs 3] [-TimeoutSec 480] [-Env @{...}] [-Dir instance]
# (-Dir: run in an instance directory, see live.ps1; tools\race_par.ps1 runs
# several of these at once.)
# -RaceSec N: after a run reaches the race, stay N s (A taps keep riding;
# -NoTaps: ride without them, the same path every time), -Profile samples
# every thread for 3 s at the end (tools/profile_tally.py sums it),
# then -Snap <file> takes a screenshot before the run is stopped -- a whole
# single-instance check in one command. -Rider/-Mode/-Event pick the race
# (see to_race.ps1; default Zoe, Race, Snow Jam).
param([int]$Runs = 3, [int]$TimeoutSec = 480, [hashtable]$Env = @{}, [string]$Dir = "",
      [int]$RaceSec = 0, [string]$Snap = "", [switch]$NoTaps, [switch]$Profile,
      [int]$Rider = 0, [int]$Mode = 0, [int]$Event = 0, [string]$Save = "unlocked", [switch]$NoAutonav, [int]$Peak = 0)

$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$live = Join-Path $PSScriptRoot "live.ps1"
$nav = Join-Path $PSScriptRoot "to_race.ps1"

# The game drives its own menus (src/autonav.c, ~27 s to the briefing);
# -NoAutonav = the old pad presses from to_race.ps1 (~40 s).
if (-not $NoAutonav -and -not $Env.ContainsKey("RECOMP_AUTONAV")) {
    $Env = $Env.Clone(); $Env["RECOMP_AUTONAV"] = "race,rider=$Rider,peak=$Peak,mode=$Mode,event=$Event,brief"
}
$navArgs = @{ Autonav = [bool]($Env.ContainsKey("RECOMP_AUTONAV")) }
for ($i = 1; $i -le $Runs; $i++) {
    & $live start -Env $Env -Dir $Dir -Save $Save | Out-Null
    Start-Sleep -Seconds 2
    $out = & $nav -TimeoutSec $TimeoutSec -Dir $Dir -Rider $Rider -Mode $Mode -Event $Event @navArgs 2>&1 | Select-Object -Last 1
    $err = Get-Content (Join-Path $root "stderr.txt") -ErrorAction SilentlyContinue
    $crash = ($err | Select-String -SimpleMatch "[CRASH]" | Select-Object -First 1)
    # Name the failure: the watchdog's verdict ("stuck: [no pad] ..."), else
    # the state the run timed out in (to_race.ps1 works from game state only).
    $kind = ""
    if ($out -match "^stuck: (\[[^\]]+\])") {
        $kind = "$($Matches[1]) "
    } elseif ($out -match "timed out \(state (\S+)") {
        $kind = "[$($Matches[1]) timeout] "
    }
    $result = if ($out -match "briefing") { "OK   reached the race briefing" }
              elseif ($crash) { "CRASH $crash" }
              else { "FAIL $kind$out" }
    "run ${i}: $result"
    if ($result -like "OK*" -and $RaceSec -gt 0) {
        $t0 = Get-Date
        while (((Get-Date) - $t0).TotalSeconds -lt $RaceSec) {
            # -NoTaps still taps through the briefing (its first 6 s).
            if (-not $NoTaps -or ((Get-Date) - $t0).TotalSeconds -lt 6) {
                & $live press -Buttons "a:200" -Dir $Dir | Out-Null
            }
            Start-Sleep -Seconds 3
        }
        if ($Snap) { & $live snap -Out $Snap -Dir $Dir }
        if ($Profile) {
            # Sampling profile of every thread (src/thread_dump.c: 300 x 10 ms)
            # into stderr.txt; tools/profile_tally.py <map> stderr.txt sums it.
            & $live dump -Mem profile -Dir $Dir | Out-Null
            Start-Sleep -Seconds 12
        }
    }
    if ($result -like "FAIL*") {
        # What it looked like: logs\fail_<time>.png (kept beside the logs).
        $shot = "logs\fail_{0:yyyyMMdd-HHmmss}.png" -f (Get-Date)
        & $live snap -Out $shot -Dir $Dir | Out-Null
        "  screenshot: $shot"
        # A stall: dump every thread (and the RECOMP_JOB_TRACE ring) before
        # the run is killed; the log is kept in logs\ by the next start.
        & $live dump -Dir $Dir | Out-Null
        # The dump (job and stream traces, threads) can take a while under
        # load: wait for its end marker (src/thread_dump.c), at most 90 s.
        $t0 = Get-Date
        do {
            Start-Sleep -Seconds 2
            $done = Select-String -Path (Join-Path $root "stderr.txt") -SimpleMatch "[THREADS-END]" -List -ErrorAction SilentlyContinue
        } while (-not $done -and ((Get-Date) - $t0).TotalSeconds -lt 90)
    }
    & $live stop -Dir $Dir | Out-Null
    Start-Sleep -Seconds 3
}
