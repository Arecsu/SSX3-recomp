# Burst of screenshots during a race: boots with RECOMP_AUTONAV (straight to
# the race), then takes a screenshot every -Every seconds between -From and
# -To seconds after the briefing, into -Dir (contact sheet: tools\montage.ps1).
#   powershell -File tools\burst.ps1 [-Nav "race,rider=3,peak=0,event=1"] [-From 14] [-To 30] [-Every 1.5] [-Dir shots\burst] [-Env @{...}]
param([string]$Nav = "race,rider=3", [int]$From = 14, [int]$To = 30, [double]$Every = 1.5, [string]$Dir = "shots\burst", [hashtable]$Env = @{})
$root = Split-Path -Parent $PSScriptRoot; $t = $PSScriptRoot
New-Item -ItemType Directory -Force -Path "$root\$Dir" | Out-Null
$e = $Env.Clone(); $e["RECOMP_AUTONAV"] = $Nav
& "$t\live.ps1" start -Env $e | Out-Null
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 90) {
    Start-Sleep -Milliseconds 200
    if (Select-String -Path "$root\stderr.txt" -Pattern "t=\d+ at the briefing" -List -ErrorAction SilentlyContinue) { break }
}
$tr = Get-Date
$k = 0
while (((Get-Date) - $tr).TotalSeconds -lt $To) {
    $s = ((Get-Date) - $tr).TotalSeconds
    if ($s -ge $From) {
        & "$t\live.ps1" snap -Out ("{0}\b{1:D2}_{2:N0}s.png" -f $Dir, $k, $s) | Out-Null
        $k++
        Start-Sleep -Milliseconds ([int]($Every * 1000))
    } else { Start-Sleep -Milliseconds 300 }
}
& "$t\live.ps1" stop | Out-Null
"$k shots"
