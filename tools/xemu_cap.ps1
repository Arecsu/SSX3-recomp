# Capture the xemu window (for side-by-side comparisons) without focusing or
# touching it: PrintWindow with PW_RENDERFULLCONTENT.
#   powershell -File tools\xemu_cap.ps1 [-Out shots\xemu\cap.png]
param([string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) "shots\xemu\cap.png"))
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class X { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 public struct RECT { public int L, T, R, B; } }
"@
$p = Get-Process xemu -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "xemu not running"; exit 1 }
$h = $p.MainWindowHandle
$r = New-Object X+RECT; [X]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc(); $ok = [X]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"xemu '$($p.MainWindowTitle)' ${w}x${hh} printwindow=$ok -> $Out"
