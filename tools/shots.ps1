# Screenshot suite: boot and drive to a race, saving every distinct menu
# screen on the way (to_race.ps1 -ShotDir), the briefing, and race shots at
# fixed times after the start, into logs\shots_<timestamp>\. Menus have fixed
# content and compare run to run; race shots are for eyeballing (riders and
# camera differ). The renderer work in docs\ROADMAP.md (Phase 2) compares a
# GPU set against a software-rasteriser set taken the same way.
#   powershell -File tools\shots.ps1 [-Env @{...}] [-Label name] [-RaceShots 4]
param([hashtable]$Env = @{}, [string]$Label = "", [int]$RaceShots = 4,
      [int]$TimeoutSec = 480)

$root = Split-Path -Parent $PSScriptRoot
$live = Join-Path $PSScriptRoot "live.ps1"
$nav  = Join-Path $PSScriptRoot "to_race.ps1"
$name = "shots_" + (Get-Date).ToString("yyyyMMdd-HHmmss") + $(if ($Label) { "_$Label" } else { "" })
$dir  = Join-Path (Join-Path $root "logs") $name
New-Item -ItemType Directory -Force -Path $dir | Out-Null

& $live start -Env $Env | Out-Null
Start-Sleep -Seconds 15
$navOut = & $nav -TimeoutSec $TimeoutSec -StopAtBriefing -ShotDir $dir 2>&1 | Select-Object -Last 1
if ($navOut -notmatch "briefing") {
    & $live stop | Out-Null
    "shots: stopped before the race ($navOut); partial set in $name"
    exit 1
}
Start-Sleep -Seconds 8
& $live press -Buttons "a:300" | Out-Null
Start-Sleep -Seconds 30
for ($i = 1; $i -le $RaceShots; $i++) {
    & $live snap -Out ("logs\{0}\race_{1}.png" -f $name, $i) | Out-Null
    & $live press -Buttons "a:200" | Out-Null
    Start-Sleep -Seconds 8
}
& $live stop | Out-Null
$n = @(Get-ChildItem $dir -Filter *.png).Count
"shots: $n screenshots in logs\$name"
