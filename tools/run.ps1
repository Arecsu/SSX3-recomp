# Run build\ssx3_recomp.exe from the project root (it opens game\default.xbe
# relative to the working directory), capturing stdout/stderr to files.
# A hang is killed after -Seconds so a stuck run can't linger on the desktop.
#   powershell -File tools\run.ps1 [-Seconds 60] [-Watchdog 20] [-Env @{RECOMP_PEEK='...'}]
# -Watchdog N sets RECOMP_WATCHDOG_SECS: the toolkit dumps the guest stack and
# NV2A pushbuffer pointers after N seconds, then exits with code 3.
param([int]$Seconds = 60, [int]$Watchdog = 0, [int]$ThreadDump = 0, [hashtable]$Env = @{}, [string]$Build = "build")

if ($Watchdog -gt 0) { $env:RECOMP_WATCHDOG_SECS = "$Watchdog" }
# -ThreadDump N: native stacks of every thread after N s (symbolize with the .map)
if ($ThreadDump -gt 0) { $env:RECOMP_THREAD_DUMP_SECS = "$ThreadDump" }
foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value $Env[$k] }

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$p = Start-Process -FilePath "$root\$Build\ssx3_recomp.exe" -WorkingDirectory $root `
        -RedirectStandardOutput "$root\stdout.txt" -RedirectStandardError "$root\stderr.txt" `
        -PassThru
$null = $p.Handle   # without a cached handle, ExitCode/ExitTime come back empty
if ($p.WaitForExit($Seconds * 1000)) {
    "exited with code 0x{0:X8} after {1:N1}s" -f $p.ExitCode, ($p.ExitTime - $p.StartTime).TotalSeconds
} else {
    Stop-Process -Id $p.Id -Force
    "still running after ${Seconds}s - killed (hang or still loading)"
}
