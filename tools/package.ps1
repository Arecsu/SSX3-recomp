# Release folder + zip for players: launcher.exe, ssx3_recomp.exe, LICENSE,
# keys.example.ini and a short README -- no game files (the player points the
# launcher at their own SSX 3 rip). Build first (tools\build.bat).
#   powershell -File tools\package.ps1 [-Out dist] [-Name SSX3-recomp]
param([string]$Out = "dist", [string]$Name = "SSX3-recomp")
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path (Join-Path $root $Out) $Name
foreach ($f in @("build\launcher.exe", "build\ssx3_recomp.exe")) {
    if (-not (Test-Path (Join-Path $root $f))) { throw "$f missing: run tools\build.bat first" }
}
Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item (Join-Path $root "build\launcher.exe") $dir
Copy-Item (Join-Path $root "build\ssx3_recomp.exe") $dir
Copy-Item (Join-Path $root "keys.example.ini") $dir
Copy-Item (Join-Path $root "LICENSE") (Join-Path $dir "LICENSE.txt")
Copy-Item (Join-Path $root "docs\PLAYER-README.txt") (Join-Path $dir "README.txt")
$zip = Join-Path (Join-Path $root $Out) "$Name.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $dir -DestinationPath $zip
"$dir"
"$zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
