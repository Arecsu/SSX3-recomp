# Drive a running live session (tools\live.ps1 start) from boot into a race,
# reading the screen from the draw count in the window title:
#   main menu 339, character select ~960-990, setup 382, peak 275,
#   event 367/413, rules 329 -> press A; race loading 309 / black loading 22
#   -> wait; once loading has been seen, the race briefing (>= 600 draws)
#   -> press A and stop.
# Start presses get through the intro and title (screens with < 200 draws).
#   powershell -File tools\to_race.ps1 [-TimeoutSec 600] [-StopAtBriefing]
param([int]$TimeoutSec = 600, [switch]$StopAtBriefing)

$live = Join-Path $PSScriptRoot "live.ps1"
$menus = @(339, 984, 382, 275, 367, 413, 329)
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$lastPress = Get-Date "2000-01-01"
$loadingSeen = $false

while ((Get-Date) -lt $deadline) {
    $title = & $live snap -Out "nav.png" 2>$null
    if ($title -notmatch "draws: (\d+)") { Start-Sleep -Seconds 2; continue }
    $draws = [int]$Matches[1]
    $since = ((Get-Date) - $lastPress).TotalSeconds
    if ($draws -eq 309 -or $draws -eq 22) { $loadingSeen = $true }
    if ($loadingSeen -and $draws -ge 600) {
        if ($StopAtBriefing) { "at briefing ($draws draws)"; exit 0 }
        & $live press -Buttons "a:300" | Out-Null
        "briefing ($draws draws): pressed A, racing"
        exit 0
    } elseif ($loadingSeen) {
        # loading: wait
    } elseif ($menus -contains $draws -or $draws -ge 900) {
        if ($since -ge 4) { & $live press -Buttons "a" | Out-Null; $lastPress = Get-Date; "menu $draws -> A" }
    } elseif ($draws -lt 200 -and $draws -ne 22) {
        if ($since -ge 2) { & $live press -Buttons "start" | Out-Null; $lastPress = Get-Date }
    }
    Start-Sleep -Seconds 2
}
"timed out (last screen: $draws draws)"
exit 1
