# Frames per second as SSX 3 renders them in xemu (the reference emulator),
# read from the game's own renderer frame counter ([0x369528] + 0x771C, one
# increment per renderer flush) through xemu's monitor -- the same measure
# works for our build (RECOMP_FRAME_STATS), so the two compare directly.
#   powershell -File tools\xemu_fps.ps1 [-Seconds 10] [-Tap]     (-Tap: press A every second, as bench.ps1 rides)
# Needs our xemu instance (tools\xemu.ps1 start) in a race.
param([int]$Seconds = 10, [switch]$Tap)
# Rendered frames per second in xemu: SSX 3's renderer frame counter
# ([0x369528] + 0x771C, incremented by every flush), read through the monitor.
$x = Join-Path $PSScriptRoot "xemu.ps1"
function ReadMem([string]$a) { $r = & $x hmp -Cmd "x/1wx $a"; if ($r -match ": 0x([0-9a-f]+)") { [Convert]::ToUInt32($Matches[1], 16) } }
$ren = ReadMem "0x369528"
$ctr = "0x{0:x}" -f ($ren + 0x771C)
$prev = ReadMem $ctr; $t0 = Get-Date
$out = @()
for ($i = 0; $i -lt $Seconds; $i++) {
    if ($Tap) { & $x press -Keys "a:200" | Out-Null; Start-Sleep -Milliseconds 600 } else { Start-Sleep -Milliseconds 1000 }
    $v = ReadMem $ctr; $t1 = Get-Date
    $out += "{0:N1}" -f (($v - $prev) / ($t1 - $t0).TotalSeconds)
    $prev = $v; $t0 = $t1
}
"xemu fps: " + ($out -join " ")
