# Drive a running live session (tools\live.ps1 start) from boot into a race,
# reading the screen from the draw count in the window title:
#   main menu 339, character select ~960-990, setup 382, peak 275,
#   event 367/413, rules 329 -> press A; race loading 309 / black loading 22
#   -> wait; once loading has been seen, the race briefing (>= 600 draws)
#   -> press A and stop.
# Start presses get through the intro and title (screens with < 200 draws).
# -ShotDir <dir>: also save each distinct screen once as it is passed
# (screen_<draws>.png, and briefing.png) -- the menu half of tools\shots.ps1.
#   powershell -File tools\to_race.ps1 [-TimeoutSec 600] [-StopAtBriefing] [-ShotDir dir] [-Dir instance] [-NoWatchdog]
# Watchdog (default on): ends the run early, printing "stuck: [<class>] ..."
# and exiting 2, when
#   [no pad]     Start has been pressed for 45 s and the game read none of the
#                presses (no "PAD: live" line in stderr: the pad never enumerated)
#   [freeze]     FPS 0 for 15 s in the menus, a loading screen or a race
#   [<state> stall]  the game state (game_state.txt) outlives its budget:
#                boot 60 s, intro 120 s, frontend 180 s, event_enter 30 s,
#                loading 90 s (a normal race load takes 15-25 s)
param([int]$TimeoutSec = 600, [switch]$StopAtBriefing, [string]$ShotDir = "", [string]$Dir = "",
      [switch]$NoWatchdog)

$liveScript = Join-Path $PSScriptRoot "live.ps1"
function live { & $liveScript @args -Dir $Dir }
. (Join-Path $PSScriptRoot "game_state.ps1")
$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$seen = @{}
$menus = @(339, 984, 382, 275, 367, 413, 329)
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$lastPress = Get-Date "2000-01-01"
$loadingSeen = $false
$budget = @{ boot = 60; intro = 120; frontend = 180; event_enter = 30; loading = 90 }
$firstStart = $null; $padOk = $false; $lastPadCheck = Get-Date "2000-01-01"
$zeroSince = $null
function Stuck([string]$why) {
    "stuck: [$why] (state $($gs.Name) for $($gs.Seconds) s, last screen: $draws draws)"
    exit 2
}

while ((Get-Date) -lt $deadline) {
    $title = live snap -Out "nav.png" 2>$null
    if ($title -notmatch "draws: (\d+)") { Start-Sleep -Seconds 2; continue }
    $draws = [int]$Matches[1]
    $fps = if ($title -match "FPS: ([0-9.]+)") { [double]$Matches[1] } else { -1 }
    $since = ((Get-Date) - $lastPress).TotalSeconds
    # Each new screen once, with the game's own state for it -- how the state
    # names in src/game_state.c are learned (and checked).
    $gs = Get-GameState $root
    if ($gs -and -not $seen.ContainsKey("$draws")) {
        $seen["$draws"] = 1
        "screen $draws draws = state $($gs.Vt) $($gs.Name)"
    }
    if (-not $NoWatchdog -and $gs) {
        if ($budget.ContainsKey($gs.Name) -and $gs.Seconds -gt $budget[$gs.Name]) { Stuck "$($gs.Name) stall" }
        # The pad: once Start presses are going out, the game must read one.
        if (-not $padOk -and $firstStart -and ((Get-Date) - $lastPadCheck).TotalSeconds -ge 5) {
            $lastPadCheck = Get-Date
            $padOk = [bool](Select-String -Path (Join-Path $root "stderr.txt") -SimpleMatch 'PAD: live "' -List -ErrorAction SilentlyContinue)
            if (-not $padOk -and ((Get-Date) - $firstStart).TotalSeconds -ge 45) { Stuck "no pad" }
        }
        # Frames: in the menus, loading screens and races something is always drawn.
        if ($fps -eq 0 -and @("frontend", "loading", "ingame") -contains $gs.Name) {
            if (-not $zeroSince) { $zeroSince = Get-Date }
            elseif (((Get-Date) - $zeroSince).TotalSeconds -ge 15) { Stuck "freeze" }
        } else { $zeroSince = $null }
    }
    if ($ShotDir) {
        # Menus have fixed draw counts; the loading screens and the race do
        # not, so only named screens and the first frame of each count.
        $shot = Join-Path $ShotDir ("screen_{0}.png" -f $draws)
        if (($menus -contains $draws -or ($draws -lt 200 -and $draws -gt 0)) -and -not (Test-Path $shot)) {
            Copy-Item (Join-Path $root "nav.png") $shot -ErrorAction SilentlyContinue
        }
    }
    if ($draws -eq 309 -or $draws -eq 22 -or ($gs -and $gs.Name -eq "loading")) { $loadingSeen = $true }
    # In the race: the game's own state says so (draw counts alone missed
    # briefings drawn with fewer than 600 calls, and runs sat there for good).
    $inRace = $gs -and $gs.Name -eq "ingame" -and $gs.Seconds -ge 3
    if ($loadingSeen -and ($draws -ge 600 -or $inRace)) {
        if ($ShotDir) { Copy-Item (Join-Path $root "nav.png") (Join-Path $ShotDir "briefing.png") -ErrorAction SilentlyContinue }
        if ($StopAtBriefing) { "at briefing ($draws draws)"; exit 0 }
        live press -Buttons "a:300" | Out-Null
        "briefing ($draws draws): pressed A, racing"
        exit 0
    } elseif ($loadingSeen) {
        # loading: wait
    } elseif ($menus -contains $draws -or $draws -ge 900) {
        if ($since -ge 4) { live press -Buttons "a" | Out-Null; $lastPress = Get-Date; "menu $draws -> A" }
    } elseif ($draws -lt 200 -and $draws -ne 22) {
        if ($since -ge 2) {
            live press -Buttons "start" | Out-Null; $lastPress = Get-Date
            if (-not $firstStart) { $firstStart = Get-Date }
        }
    }
    Start-Sleep -Seconds 2
}
"timed out (last screen: $draws draws)"
exit 1
