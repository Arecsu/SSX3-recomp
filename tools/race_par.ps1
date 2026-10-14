# Parallel reliability test: N game instances at once, each in its own
# directory (work\i<k>, see live.ps1 -Dir), each running race_test.ps1 for
# -Runs boots. One machine then does N times the boot->race runs per hour --
# what the intermittent bugs (1 failure in ~10 runs) need.
#   powershell -Command "& tools\race_par.ps1 -Instances 6 -Runs 2 [-Env @{...}] [-TimeoutSec 600]"
# Each instance gets RECOMP_RASTER_THREADS = cores / instances (unless -Env
# sets it), so the software rasteriser pools do not oversubscribe the CPU.
# Logs: work\i<k>\logs\ (one per run, as race_test keeps them); the summary
# is printed and saved as logs\race_par_<time>.txt.
param([int]$Instances = 6, [int]$Runs = 2, [int]$TimeoutSec = 600,
      [hashtable]$Env = @{}, [int]$StaggerSec = 8)

$root = Split-Path -Parent $PSScriptRoot
$test = Join-Path $PSScriptRoot "race_test.ps1"
$cores = [Environment]::ProcessorCount
$e = @{} + $Env
if (-not $e.ContainsKey("RECOMP_RASTER_THREADS")) {
    $e["RECOMP_RASTER_THREADS"] = "$([Math]::Max(2, [Math]::Floor($cores / $Instances)))"
}
$t0 = Get-Date
"race_par: $Instances instances x $Runs runs, raster threads $($e['RECOMP_RASTER_THREADS']) each ($cores cores)"

$jobs = @()
for ($k = 1; $k -le $Instances; $k++) {
    $dir = Join-Path $root "work\i$k"
    $jobs += Start-Job -Name "i$k" -ArgumentList $test, $dir, $Runs, $TimeoutSec, $e -ScriptBlock {
        param($test, $dir, $runs, $timeout, $env)
        & $test -Runs $runs -TimeoutSec $timeout -Env $env -Dir $dir
    }
    # Staggered, so the boots (disc reads, shader setup) do not all coincide.
    Start-Sleep -Seconds $StaggerSec
}
Wait-Job -Job $jobs | Out-Null

$lines = @()
foreach ($j in $jobs) {
    foreach ($l in (Receive-Job -Job $j)) { $lines += "$($j.Name) $l" }
}
Remove-Job -Job $jobs
$ok = @($lines | Where-Object { $_ -match ": OK" }).Count
$crash = @($lines | Where-Object { $_ -match ": CRASH" }).Count
$fail = @($lines | Where-Object { $_ -match ": FAIL" }).Count
$min = [Math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
$summary = @($lines) + "total: $ok OK, $fail FAIL, $crash CRASH of $($ok + $fail + $crash) runs in $min min"
$summary
New-Item -ItemType Directory -Force -Path (Join-Path $root "logs") | Out-Null
$summary | Set-Content (Join-Path $root ("logs\race_par_{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
