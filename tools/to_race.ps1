# Drive a running live session (tools\live.ps1 start) from boot into a race,
# reading the screen from the draw count in the window title:
#   main menu 339, character select ~960-990, setup 382, peak 275,
#   event 367/413, rules 329 -> press A; race loading 309 / black loading 22
#   -> wait; once loading has been seen, the race briefing (>= 600 draws)
#   -> press A and stop.
# Start presses get through the intro and title (screens with < 200 draws).
# -ShotDir <dir>: also save each distinct screen once as it is passed
# (screen_<draws>.png, and briefing.png) -- the menu half of tools\shots.ps1.
#   powershell -File tools\to_race.ps1 [-TimeoutSec 600] [-StopAtBriefing] [-ShotDir dir] [-Dir instance]
param([int]$TimeoutSec = 600, [switch]$StopAtBriefing, [string]$ShotDir = "", [string]$Dir = "")

$liveScript = Join-Path $PSScriptRoot "live.ps1"
function live { & $liveScript @args -Dir $Dir }
. (Join-Path $PSScriptRoot "game_state.ps1")
$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$seen = @{}
$menus = @(339, 984, 382, 275, 367, 413, 329)
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$lastPress = Get-Date "2000-01-01"
$loadingSeen = $false

while ((Get-Date) -lt $deadline) {
    $title = live snap -Out "nav.png" 2>$null
    if ($title -notmatch "draws: (\d+)") { Start-Sleep -Seconds 2; continue }
    $draws = [int]$Matches[1]
    $since = ((Get-Date) - $lastPress).TotalSeconds
    # Each new screen once, with the game's own state for it -- how the state
    # names in src/game_state.c are learned (and checked).
    $gs = Get-GameState $root
    if ($gs -and -not $seen.ContainsKey("$draws")) {
        $seen["$draws"] = 1
        "screen $draws draws = state $($gs.Vt) $($gs.Name)"
    }
    if ($ShotDir) {
        # Menus have fixed draw counts; the loading screens and the race do
        # not, so only named screens and the first frame of each count.
        $shot = Join-Path $ShotDir ("screen_{0}.png" -f $draws)
        if (($menus -contains $draws -or ($draws -lt 200 -and $draws -gt 0)) -and -not (Test-Path $shot)) {
            Copy-Item (Join-Path $root "nav.png") $shot -ErrorAction SilentlyContinue
        }
    }
    if ($draws -eq 309 -or $draws -eq 22) { $loadingSeen = $true }
    if ($loadingSeen -and $draws -ge 600) {
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
        if ($since -ge 2) { live press -Buttons "start" | Out-Null; $lastPress = Get-Date }
    }
    Start-Sleep -Seconds 2
}
"timed out (last screen: $draws draws)"
exit 1
