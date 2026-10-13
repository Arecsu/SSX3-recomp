# Interactive session: start the game detached with a live pad file, take
# screenshots of the running window, press buttons, stop it.
#   powershell -File tools\live.ps1 start [-Env @{...}]   launch; pad file = pad_live.txt
#   powershell -File tools\live.ps1 snap  [-Out snap.png] screenshot the running window
#   powershell -File tools\live.ps1 press -Buttons "a"    append "a" (any RECOMP_PAD_SCRIPT button syntax)
#   powershell -File tools\live.ps1 key -Key 0x0D [-Hold 200]  post a key to the window (RECOMP_KEYBOARD=1 path)
#   powershell -File tools\live.ps1 dump [-Mem "va:len,..."] all-thread stack dump (+ guest memory) into stderr.txt
#   powershell -File tools\live.ps1 stop
# stdout/stderr go to stdout.txt / stderr.txt in the project root as usual.
param([Parameter(Position = 0)][string]$Cmd = "snap", [string]$Out = "snap.png",
      [string]$Buttons = "", [string]$Mem = "", [hashtable]$Env = @{},
      [string]$Key = "0x0D", [int]$Hold = 200)

$root = Split-Path -Parent $PSScriptRoot
$pad = Join-Path $root "pad_live.txt"
$pidFile = Join-Path $root "live.pid"

function Get-Game {
    if (-not (Test-Path $pidFile)) { return $null }
    $id = [int](Get-Content $pidFile)
    Get-Process -Id $id -ErrorAction SilentlyContinue
}

switch ($Cmd) {
    "start" {
        $g = Get-Game; if ($g) { Stop-Process -Id $g.Id -Force }
        Set-Content -Path $pad -Value $null
        $env:RECOMP_PAD_LIVE = $pad
        $env:RECOMP_THREAD_DUMP_TRIGGER = (Join-Path $root "dump.trigger")
        foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value $Env[$k] }
        $p = Start-Process -FilePath "$root\build\ssx3_recomp.exe" -WorkingDirectory $root `
                -RedirectStandardOutput "$root\stdout.txt" -RedirectStandardError "$root\stderr.txt" -PassThru
        Set-Content -Path $pidFile -Value $p.Id
        "started pid $($p.Id)"
    }
    "press" {
        Add-Content -Path $pad -Value $Buttons
        "pressed $Buttons"
    }
    "snap" {
        $g = Get-Game
        if (-not $g) { "not running"; exit 1 }
        Add-Type -AssemblyName System.Drawing
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LiveWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
}
"@
        $g.Refresh()
        $h = $g.MainWindowHandle
        if ($h -eq [IntPtr]::Zero) { "no window yet"; exit 1 }
        $r = New-Object LiveWin+RECT
        [void][LiveWin]::GetWindowRect($h, [ref]$r)
        $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
        $gr = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $gr.GetHdc(); [void][LiveWin]::PrintWindow($h, $hdc, 2); $gr.ReleaseHdc($hdc)
        $bmp.Save((Join-Path $root $Out), [System.Drawing.Imaging.ImageFormat]::Png)
        "'{0}' -> {1}" -f $g.MainWindowTitle, $Out
    }
    "key" {
        $g = Get-Game
        if (-not $g) { "not running"; exit 1 }
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LiveKey {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@
        $g.Refresh()
        $h = $g.MainWindowHandle
        $vk = [int]$Key
        [void][LiveKey]::PostMessage($h, 0x0100, [IntPtr]$vk, [IntPtr]1)
        Start-Sleep -Milliseconds $Hold
        [void][LiveKey]::PostMessage($h, 0x0101, [IntPtr]$vk, [IntPtr]0xC0000001)
        "key $Key"
    }
    "dump" {
        Set-Content -Path (Join-Path $root "dump.trigger") -Value $Mem -NoNewline
        Start-Sleep -Seconds 2
        "dump requested"
    }
    "stop" {
        $g = Get-Game; if ($g) { Stop-Process -Id $g.Id -Force; "stopped" } else { "not running" }
        Remove-Item $pidFile -ErrorAction SilentlyContinue
    }
}
