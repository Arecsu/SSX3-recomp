# Boot to the main menu and run a list of button presses, with a screenshot
# after each, then report whether the game crashed -- for menu bugs.
#   powershell -File tools\menu_test.ps1 -Steps "down,down,a" [-ShotDir shots\menu] [-WaitSec 2]
#     [-Env @{...}] [-Dir instance] [-Keep]
# Steps are RECOMP_PAD_SCRIPT buttons (up/down/left/right/a/b/start/...), one
# press per step, -WaitSec apart; "wait" sleeps one step. The main menu is
# reached by pressing Start on the title until game_state.txt shows the main menu (screen id 2).
# -Keep leaves the game running (stop it with tools\live.ps1 stop).
param([string]$Steps = "", [string]$ShotDir = "shots\menu", [double]$WaitSec = 2,
      [hashtable]$Env = @{}, [string]$Dir = "", [switch]$Keep, [int]$TimeoutSec = 120)

. (Join-Path $PSScriptRoot "game_state.ps1")
$root = if ($Dir) { $Dir } else { Split-Path -Parent $PSScriptRoot }
$live = Join-Path $PSScriptRoot "live.ps1"
New-Item -ItemType Directory -Force -Path (Join-Path $root $ShotDir) | Out-Null

function Crashed { Select-String -Path (Join-Path $root "stderr.txt") -SimpleMatch "[CRASH]" -List -ErrorAction SilentlyContinue }
function Snap([string]$name) {
    & $live snap -Out (Join-Path $ShotDir "$name.png") -Dir $Dir | Out-Null
}

& $live start -Env $Env -Dir $Dir | Out-Null
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$front = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $gs = Get-GameState $root
    if ($gs -and $gs.Name -eq "frontend") { $front = Get-Date; break }
}
if (-not $front) { "no frontend after $TimeoutSec s"; if (-not $Keep) { & $live stop -Dir $Dir | Out-Null }; exit 1 }
# The title ignores input for a while after it appears, for a varying time:
# press Start on the title (screen id 0, game_state.txt's screen field)
# every 3 s until the main menu (id 2) is up.
$t0 = Get-Date
$lastPress = Get-Date "2000-01-01"
do {
    Start-Sleep -Milliseconds 500
    $gs = Get-GameState $root
    if ($gs -and $gs.Screen -notlike "*:2" -and ((Get-Date) - $lastPress).TotalSeconds -ge 3) {
        & $live press -Buttons "start" -Dir $Dir | Out-Null
        $lastPress = Get-Date
    }
} while (-not ($gs -and $gs.Screen -like "*:2") -and ((Get-Date) - $t0).TotalSeconds -lt 60)
if (-not ($gs -and $gs.Screen -like "*:2")) { "main menu not reached"; if (-not $Keep) { & $live stop -Dir $Dir | Out-Null }; exit 1 }
Start-Sleep -Seconds 4
Snap "00-main"
$k = 0
foreach ($s in ($Steps -split "," | Where-Object { $_ })) {
    $k++
    if ($s -ne "wait") { & $live press -Buttons $s -Dir $Dir | Out-Null }
    Start-Sleep -Milliseconds ([int]($WaitSec * 1000))
    if (Crashed) { "step ${k} ($s): CRASH"; break }
    Snap ("{0:D2}-{1}" -f $k, $s)
    $gs = Get-GameState $root
    "step ${k} ($s): state $($gs.Name) sub $($gs.Sub) screen $($gs.Screen)"
}
$c = Crashed
if ($c) { "CRASH $c" } else { "no crash" }
if (-not $Keep) { & $live stop -Dir $Dir | Out-Null }
