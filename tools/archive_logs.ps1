# Keep every run's log: move the previous run's stdout/stderr into logs\
# before a new run overwrites them. Named after the time the previous run
# last wrote its log, so a file says when that run happened:
#   logs\20261013-160758_stderr.txt  (+ _stdout.txt)
# The newest $Keep runs are kept; older ones are deleted.
# Dot-source and call:   . "$PSScriptRoot\archive_logs.ps1"; Save-PreviousLogs $root
#   (prefix "play_" for play.bat's play_stdout.txt / play_stderr.txt)
function Save-PreviousLogs([string]$Root, [string]$Prefix = "", [int]$Keep = 40) {
    $dir = Join-Path $Root "logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $err = Join-Path $Root "${Prefix}stderr.txt"
    $out = Join-Path $Root "${Prefix}stdout.txt"
    if (Test-Path $err) {
        $stamp = (Get-Item $err).LastWriteTime.ToString("yyyyMMdd-HHmmss")
        foreach ($f in @($err, $out)) {
            if (Test-Path $f) {
                $name = "${stamp}_" + (Split-Path -Leaf $f)
                Move-Item -Force -Path $f -Destination (Join-Path $dir $name) -ErrorAction SilentlyContinue
            }
        }
    }
    # Prune by run (one stderr file per run), oldest first.
    $runs = Get-ChildItem -Path $dir -Filter "*stderr.txt" | Sort-Object LastWriteTime -Descending
    foreach ($old in ($runs | Select-Object -Skip $Keep)) {
        $base = $old.FullName -replace "stderr\.txt$", ""
        Remove-Item -Force -ErrorAction SilentlyContinue "${base}stderr.txt", "${base}stdout.txt"
    }
}
