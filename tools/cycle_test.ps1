# Race -> pause -> Quit -> menus -> race again, -Cycles times in one game
# session: catches what only goes wrong on the way back from a race (leaks,
# state left behind). Each cycle: to_race.ps1 to the briefing, A, Start to
# skip the race intro, ride -RaceSec, Start (pause), Quit (up, A), "Yes"
# (up, A), wait for the frontend. Reports per cycle, stops on a crash or a
# cycle that does not get back.
#   powershell -File tools\cycle_test.ps1 [-Cycles 5] [-RaceSec 8] [-Env @{...}] [-Dir instance]
#     [-Rider N -Mode N -Event N] [-ProfileEnd]
# -ProfileEnd: after the last cycle, into one more race and take a sampling
# profile of every thread there (tools/profile_tally.py reads it).
param([int]$Cycles = 5, [int]$RaceSec = 8, [hashtable]$Env = @{}, [string]$Dir = "",
      [int]$Rider = 0, [int]$Mode = 0, [int]$Event = 0, [switch]$ProfileEnd, [string]$Save = "unlocked", [switch]$NoAutonav, [int]$Peak = 0)

. (Join-Path $PSScriptRoot "game_state.ps1")
$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$live = Join-Path $PSScriptRoot "live.ps1"
$nav = Join-Path $PSScriptRoot "to_race.ps1"
$err = Join-Path $root "stderr.txt"
function Press([string]$b) { & $live press -Buttons $b -Dir $Dir | Out-Null }
function Crashed { Select-String -Path $err -SimpleMatch "[CRASH]" -List -ErrorAction SilentlyContinue }
function BadCalls { @(Select-String -Path $err -SimpleMatch "is not code" -ErrorAction SilentlyContinue).Count }

# The game drives its own menus (src/autonav.c, ~27 s to the briefing);
# -NoAutonav = the old pad presses from to_race.ps1 (~40 s).
if (-not $NoAutonav -and -not $Env.ContainsKey("RECOMP_AUTONAV")) {
    $Env = $Env.Clone(); $Env["RECOMP_AUTONAV"] = "race,rider=$Rider,peak=$Peak,mode=$Mode,event=$Event,brief"
}
$navArgs = @{ Autonav = [bool]($Env.ContainsKey("RECOMP_AUTONAV")) }
& $live start -Env $Env -Dir $Dir -Save $Save | Out-Null
Start-Sleep -Seconds 2
$result = "OK"
for ($c = 1; $c -le $Cycles; $c++) {
    $t0 = Get-Date
    $out = & $nav -TimeoutSec 240 -Dir $Dir -Rider $Rider -Mode $Mode -Event $Event @navArgs 2>&1 | Select-Object -Last 1
    if ($out -notmatch "briefing") { $result = "FAIL cycle ${c}: $out"; break }
    # Into the race, then paused: by screen (game_state.txt), not by time --
    # Start skips the race intro while it plays and pauses after it, and the
    # intro's length varies. Pause menu screen vt 002981D8, Quit confirm
    # 00297B60.
    Start-Sleep -Seconds 4
    Press "start:300"                       # skip the intro (or pause, if over)
    Start-Sleep -Seconds 2
    $gs = Get-GameState $root
    if ($gs.Screen -like "002981D8:*" -and $gs.ScreenState -eq 5) { Press "start:300"; Start-Sleep -Seconds 1 }   # was over: unpause
    Start-Sleep -Seconds ([Math]::Max(2, $RaceSec))
    # Pause -> Quit -> "Yes", driven by the screen that is up (game_state.txt)
    # rather than by a fixed sequence: menus ignore input for a moment after
    # they open, and a dropped press used to derail the whole cycle. Each
    # step waits 1 s after its menu is up. The pause menu wraps, so "up" from
    # Return is Quit; in the dialog "up" is Yes.
    $back = $false
    $fresh = $true
    for ($step = 0; $step -lt 20 -and -not $back; $step++) {
        $gs = Get-GameState $root
        if (Crashed) { break }
        if ($gs -and $gs.Name -eq "frontend") { $back = $true; break }
        $active = $gs.ScreenState -eq 5
        if ($gs.Screen -like "00297B60:*" -and $active) {            # Quit dialog
            Start-Sleep -Seconds 1
            Press "up:150"; Start-Sleep -Milliseconds 800
            Press "a:200"; Start-Sleep -Seconds 4
        } elseif ($gs.Screen -like "002981D8:*" -and $active) {      # pause menu
            # Fresh from Start the cursor is on Return; back from the dialog
            # ("No") it is still on Quit. A first: Return just unpauses.
            Start-Sleep -Seconds 1
            if ($fresh) { Press "up:150"; Start-Sleep -Milliseconds 800 }
            Press "a:200"; Start-Sleep -Seconds 2
            $fresh = $false
        } elseif ($active -and $gs.Name -eq "ingame" -and $gs.Screen -notlike "00297E30:*") {
            # Another in-race menu (a stray press opened Options or Audio):
            # back out to the pause menu.
            # back out to the pause menu, then unpause too: the next pause
            # starts on Return again.
            Press "b:200"; Start-Sleep -Seconds 2
            Press "b:200"; Start-Sleep -Seconds 2
        } elseif ($gs -and $gs.Name -eq "ingame") {                  # racing
            Press "start:300"; Start-Sleep -Seconds 2
            $fresh = $true
        } else {                                                     # loading out
            Start-Sleep -Seconds 1
        }
    }
    if (-not $back -and -not (Crashed)) {
        for ($w = 0; $w -lt 40; $w++) {
            Start-Sleep -Seconds 1
            $gs = Get-GameState $root
            if ($gs -and $gs.Name -eq "frontend") { $back = $true; break }
        }
    }
    $c0 = Crashed
    if ($c0) { $result = "CRASH in cycle ${c}: $c0"; break }
    if (-not $back) { $result = "FAIL cycle ${c}: not back in the frontend"; break }
    "cycle ${c}: OK in {0:N0} s, bad calls so far $(BadCalls)" -f ((Get-Date) - $t0).TotalSeconds
    Start-Sleep -Seconds 3
}
if ($result -eq "OK" -and $ProfileEnd) {
    $out = & $nav -TimeoutSec 240 -Dir $Dir -Rider $Rider -Mode $Mode -Event $Event @navArgs 2>&1 | Select-Object -Last 1
    Start-Sleep -Seconds 4; Press "start:300"; Start-Sleep -Seconds 10
    & $live dump -Mem profile -Dir $Dir | Out-Null
    Start-Sleep -Seconds 20
    & $live dump -Dir $Dir | Out-Null       # and the threads ([GUESTCPU]: who holds it)
    Start-Sleep -Seconds 15
    "profile and thread dump taken in the race after cycle $Cycles"
}
if ($result -ne "OK") {
    & $live snap -Out "cycle_fail.png" -Dir $Dir | Out-Null
    & $live dump -Dir $Dir | Out-Null; Start-Sleep -Seconds 20
}
& $live stop -Dir $Dir | Out-Null
"cycle_test: $result ($Cycles cycles asked, bad calls $(BadCalls))"
