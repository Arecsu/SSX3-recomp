# Drive a running live session (tools\live.ps1 start) from boot into a race,
# using only the game's own state (game_state.txt, src/game_state.c) -- no
# window title, no draw counts, so it works the same on every renderer and
# with the window covered or minimised.
#
#   frontend     every screen from the title to the rules: Start for the first
#                6 s, then A every 2 s (title, main, Single Event, Zoe,
#                Continue, Peak 1, Snow Jam, My Rules are all A).
#   event_enter / loading   wait
#   ingame       after a loading state: the race briefing -> A, racing; done.
#
# The title screen starts an attract demo after ~40 s idle; we press within
# seconds, and a demo would not pass through our own loading screen.
#
#   powershell -File tools\to_race.ps1 [-TimeoutSec 300] [-StopAtBriefing] [-ShotDir dir] [-Dir instance] [-NoWatchdog]
#
# Watchdog (default on): ends the run early, printing "stuck: [<class>] ..."
# and exiting 2, when
#   [no pad]     buttons have been pressed for 45 s and the game read none of
#                them (no "PAD: live" line in stderr: the pad never enumerated)
#   [freeze]     the GPU draw count has not moved for 15 s
#   [<state> stall]  a state outlives its budget: boot 60 s, intro 120 s,
#                frontend 180 s, event_enter 30 s, loading 90 s
# -ShotDir <dir>: also save a screenshot when each new state is entered.
# -Rider N / -Mode N / -Event N: which rider (right presses on Select
# Character), mode (0 Race, 1 Freestyle) and event of Peak 1 (Race: 0 Snow
# Jam, 1 Metro-City, 2 Happiness). The frontend screens are told apart by
# game_state.txt's screen field (src/ssx3_overrides.c sub_00202460):
#   0 title, 1 hard-disk check, 2 main menu, 9 Select Character, 12 Setup Character,
#   19 Select Peak -> Mode -> Event (one screen, three pages), 20 My Rules.
# -Autonav: the game drives its own menus (RECOMP_AUTONAV=race,...,brief set
# at start, src/autonav.c); this script presses nothing until the briefing,
# waits for the next "[AUTONAV] t=<ms> at the briefing" line in stderr and
# keeps its watchdogs.
param([int]$TimeoutSec = 300, [switch]$StopAtBriefing, [string]$ShotDir = "", [string]$Dir = "",
      [switch]$NoWatchdog, [int]$Rider = 0, [int]$Mode = 0, [int]$Event = 0, [switch]$Autonav)

$liveScript = Join-Path $PSScriptRoot "live.ps1"
function live { & $liveScript @args -Dir $Dir }
. (Join-Path $PSScriptRoot "game_state.ps1")
$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$budget = @{ boot = 60; intro = 120; frontend = 180; event_enter = 30; loading = 90 }
$loadingSeen = $false
$frontSince = $null
$lastPress = Get-Date "2000-01-01"
$firstPress = $null; $padOk = $false; $lastPadCheck = Get-Date "2000-01-01"
$lastDraws = -1; $drawsSince = Get-Date
$lastState = ""; $stateSince = Get-Date
$gs = $null
$scripted = @{}         # screens whose extra presses have been sent
$errFile = Join-Path $root "stderr.txt"
function BriefingCount { @(Select-String -Path $errFile -Pattern '\[AUTONAV\] t=\d+ at the briefing' -ErrorAction SilentlyContinue).Count }
$briefBase = if ($Autonav) { BriefingCount } else { 0 }

function Stuck([string]$why) {
    "stuck: [$why] (state $($gs.Name) for $([int]$inState) s, $($gs.Draws) draws)"
    exit 2
}
function Press([string]$b) {
    live press -Buttons $b | Out-Null
    $script:lastPress = Get-Date
    if (-not $script:firstPress) { $script:firstPress = Get-Date }
}

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $gs = Get-GameState $root
    if (-not $gs) { continue }
    if ($gs.Name -ne $lastState) {
        "state $($gs.Name) ($($gs.Vt)) after $([int]((Get-Date) - $deadline.AddSeconds(-$TimeoutSec)).TotalSeconds) s"
        if ($ShotDir) {
            New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null
            live snap -Out "nav.png" | Out-Null
            Copy-Item (Join-Path $root "nav.png") (Join-Path $ShotDir ("{0}.png" -f $gs.Name)) -ErrorAction SilentlyContinue
        }
        $lastState = $gs.Name
        $stateSince = Get-Date
    }
    # Seconds in this state by name: game_state.txt's own count restarts on
    # every sub-state change, and in-game the sub-state changes all the time.
    $inState = ((Get-Date) - $stateSince).TotalSeconds
    if ($gs.Name -eq "loading" -or $gs.Name -eq "event_enter") { $loadingSeen = $true }

    if (-not $NoWatchdog) {
        if ($budget.ContainsKey($gs.Name) -and $inState -gt $budget[$gs.Name]) { Stuck "$($gs.Name) stall" }
        if (-not $padOk -and $firstPress -and ((Get-Date) - $lastPadCheck).TotalSeconds -ge 5) {
            $lastPadCheck = Get-Date
            $padOk = [bool](Select-String -Path (Join-Path $root "stderr.txt") -SimpleMatch 'PAD: live "' -List -ErrorAction SilentlyContinue)
            if (-not $padOk -and ((Get-Date) - $firstPress).TotalSeconds -ge 45) { Stuck "no pad" }
        }
        if ($gs.Draws -ge 0) {
            if ($gs.Draws -ne $lastDraws) { $lastDraws = $gs.Draws; $drawsSince = Get-Date }
            elseif (((Get-Date) - $drawsSince).TotalSeconds -ge 15 -and
                    @("frontend", "loading", "ingame") -contains $gs.Name) { Stuck "freeze" }
        }
    }

    if ($Autonav) {
        if ((BriefingCount) -gt $briefBase) {
            if ($StopAtBriefing) { "at briefing ($($gs.Draws) draws)"; exit 0 }
            Press "a:300"
            "briefing: pressed A, racing"
            exit 0
        }
        if (-not $firstPress) { $firstPress = Get-Date }    # the game presses: arm the pad check
        continue
    }
    $since = ((Get-Date) - $lastPress).TotalSeconds
    switch ($gs.Name) {
        "frontend" {
            if (-not $frontSince) { $frontSince = Get-Date }
            $inFront = ((Get-Date) - $frontSince).TotalSeconds
            $scr = $gs.Screen
            if ($inFront -lt 6) { if ($since -ge 1.5) { Press "start" } }
            elseif ($scr -like "*:9" -and $Rider -gt 0 -and -not $scripted[$scr]) {
                $scripted[$scr] = $true
                Start-Sleep -Seconds 1
                for ($r = 0; $r -lt $Rider; $r++) { Press "right"; Start-Sleep -Milliseconds 700 }
                Start-Sleep -Seconds 1; Press "a"
            }
            elseif ($scr -like "*:19" -and -not $scripted[$scr]) {
                # Peak 1, then the mode, then the event: one screen, so by time.
                $scripted[$scr] = Get-Date
                Start-Sleep -Seconds 1.5; Press "a"; Start-Sleep -Seconds 2.5
                for ($m = 0; $m -lt $Mode; $m++) { Press "down"; Start-Sleep -Milliseconds 800 }
                Start-Sleep -Milliseconds 500; Press "a"; Start-Sleep -Seconds 2.5
                for ($e = 0; $e -lt $Event; $e++) { Press "down"; Start-Sleep -Milliseconds 800 }
                Start-Sleep -Milliseconds 500; Press "a"
            }
            elseif ($scr -like "*:19") {
                # Waiting for the event to load the rules. A press the menu
                # dropped leaves it on the event page: after 10 s, A again
                # (the event page is the last, so this only goes forward).
                if (((Get-Date) - $scripted[$scr]).TotalSeconds -ge 10 -and $since -ge 3) { Press "a" }
            }
            elseif ($since -ge 2) { Press "a" }
        }
        "intro" { if ($since -ge 2) { Press "start" } }   # only if the movies play (RECOMP_SKIP_INTRO=0)
        "ingame" {
            if ($loadingSeen -and $inState -ge 2) {
                if ($StopAtBriefing) { "at briefing ($($gs.Draws) draws)"; exit 0 }
                Press "a:300"
                "briefing: pressed A, racing"
                exit 0
            }
        }
    }
}
"timed out (state $($gs.Name) for $([int]$inState) s, $($gs.Draws) draws)"
exit 1
