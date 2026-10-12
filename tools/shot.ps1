# Start the game, screenshot its window after -After seconds, then stop it.
#   powershell -File tools\shot.ps1 [-After 15] [-Out shot.png] [-Env @{RECOMP_PB_EXEC='1'}]
# Output: shot.png (window), stdout.txt / stderr.txt in the project root.
param([int]$After = 15, [string]$Out = "shot.png", [hashtable]$Env = @{})

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
}
"@

foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value $Env[$k] }
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$p = Start-Process -FilePath "$root\build\ssx3_recomp.exe" -WorkingDirectory $root `
        -RedirectStandardOutput "$root\stdout.txt" -RedirectStandardError "$root\stderr.txt" -PassThru
$null = $p.Handle
Start-Sleep -Seconds $After
$p.Refresh()
if ($p.HasExited) { "exited early with code 0x{0:X8}" -f $p.ExitCode; exit 1 }
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "no window"; Stop-Process -Id $p.Id -Force; exit 1 }
$r = New-Object Win+RECT
[void][Win]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hgt = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
# PrintWindow with PW_RENDERFULLCONTENT (2) captures even when covered.
$hdc = $g.GetHdc(); [void][Win]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc)
$bmp.Save("$root\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
"window '{0}' {1}x{2} -> {3}" -f $p.MainWindowTitle, $w, $hgt, $Out
Stop-Process -Id $p.Id -Force
