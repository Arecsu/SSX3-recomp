# Drive xemu (the reference emulator) from scripts: boot it with the SSX 3
# ISO, press controller buttons, take screenshots, pause/resume and use
# snapshots. Used to compare our renderer against xemu frame by frame.
#
#   powershell -File tools\xemu.ps1 <command> [options]
#
#   start  [-Iso path] [-Exe path] [-Audio] [-Port 4455] [-Snapshot tag [-Paused]]
#          boot our own instance; -Snapshot restores a saved state right away
#          (~1 s, e.g. race_go) instead of playing through the menus
#   stop                                     quit our instance (QMP, then its PID)
#   status                                   instance, window, QMP run state
#   cap    [-Out file.png] [-Target ours|user]  client-area screenshot, no focus change
#   press  -Keys "right,wait:500,a:200,start" [-Target ours|user] [-Gap ms]
#   pause | resume                           stop/continue the emulated machine
#   save   -Name tag | load -Name tag [-Paused] | delete -Name tag | snapshots
#          VM snapshots, stored in our HDD copy (work\xemu\xbox_hdd.qcow2);
#          -Paused: run -SettleMs (150) after the load, then freeze (resume to
#          run). The first frames after a load show a stale picture.
#   hmp    -Cmd "info status"                any human-monitor command
#   qmp    -Cmd '{"execute":"query-status"}'  any raw QMP command
#
# Our instance is separate from the user's own xemu: its own config
# (work\xemu\xemu.toml), copies of the user's HDD image and EEPROM, muted
# (volume_limit 0; -Audio keeps sound), no real gamepad bound (the user's pad
# never reaches it), no shader cache (the cache is shared with the user's
# xemu), and a QMP socket on 127.0.0.1:<Port>. Bootrom and BIOS paths come from
# the user's xemu.toml. Both can run side by side.
#
# Buttons (xemu's default keyboard map, port 1 = keyboard): a b x y, up down
# left right (d-pad), start, back, white, black, lt, rt, ls/rs (stick
# clicks), lsup lsdown lsleft lsright, rsup rsdown rsleft rsright. A step is
# "button[+button...][:holdms]" (default hold 120 ms) or "wait:ms". Keys are
# posted to xemu's window (SDL reads them without focus), so the user's
# keyboard focus is never taken. -Target user sends to the user's own xemu
# window (any xemu not started by this script) -- only when asked.
param([Parameter(Position = 0)][string]$Command = "status",
      [string]$Iso = "", [string]$Exe = "", [int]$Port = 4455, [switch]$Audio,
      [string]$Out = "", [string]$Keys = "", [string]$Target = "",
      [int]$Gap = 250, [string]$Name = "", [string]$Cmd = "", [int]$BootWaitSec = 30,
      [string]$Snapshot = "", [switch]$Paused, [int]$SettleMs = 150)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root "work\xemu"
$pidFile = Join-Path $work "xemu.pid"
$userCfg = Join-Path $env:APPDATA "xemu\xemu\xemu.toml"
$defaultDir = Join-Path $env:USERPROFILE "Documents\xbox\XEMU FILES"

Add-Type -AssemblyName System.Drawing
if (-not ("XemuWin" -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices;
public class XemuWin {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  public struct RECT { public int L, T, R, B; }
  public struct POINT { public int X, Y; }
}
"@
}

# button -> (virtual key, set-1 scan code, extended)
$map = @{
    a = 0x41, 0x1E, 0; b = 0x42, 0x30, 0; x = 0x58, 0x2D, 0; y = 0x59, 0x15, 0
    left = 0x25, 0x4B, 1; up = 0x26, 0x48, 1; right = 0x27, 0x4D, 1; down = 0x28, 0x50, 1
    back = 0x08, 0x0E, 0; start = 0x0D, 0x1C, 0
    white = 0x31, 0x02, 0; black = 0x32, 0x03, 0; ls = 0x33, 0x04, 0; rs = 0x34, 0x05, 0
    lsup = 0x45, 0x12, 0; lsleft = 0x53, 0x1F, 0; lsright = 0x46, 0x21, 0; lsdown = 0x44, 0x20, 0
    lt = 0x57, 0x11, 0; rt = 0x4F, 0x18, 0
    rsup = 0x49, 0x17, 0; rsleft = 0x4A, 0x24, 0; rsright = 0x4C, 0x26, 0; rsdown = 0x4B, 0x25, 0
}

function OurProcess {
    if (-not (Test-Path $pidFile)) { return $null }
    $id = [int](Get-Content $pidFile -Raw)
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -eq "xemu") { return $p }
    return $null
}

function TargetWindow([string]$t) {
    $ours = OurProcess
    if (-not $t) { $t = "ours" }
    if ($t -eq "ours") {
        if (-not $ours) { throw "our xemu is not running (tools\xemu.ps1 start), or use -Target user" }
        $ours.Refresh(); return $ours.MainWindowHandle
    }
    $u = Get-Process xemu -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and (-not $ours -or $_.Id -ne $ours.Id) } | Select-Object -First 1
    if (-not $u) { throw "no user xemu window found" }
    return $u.MainWindowHandle
}

function TomlValue([string]$text, [string]$key) {
    $m = [regex]::Match($text, "(?m)^\s*$key\s*=\s*'([^']*)'")
    if (-not $m.Success) { $m = [regex]::Match($text, "(?m)^\s*$key\s*=\s*""([^""]*)""") }
    if ($m.Success) { return $m.Groups[1].Value } else { return "" }
}

function Qmp([string]$json) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect("127.0.0.1", $Port) } catch { throw "no QMP on port $Port (is our xemu running?)" }
    $s = $c.GetStream(); $s.ReadTimeout = 60000
    $r = New-Object IO.StreamReader($s); $w = New-Object IO.StreamWriter($s)
    $w.AutoFlush = $true; $w.NewLine = "`n"
    $null = $r.ReadLine()                                   # greeting
    $reply = { while ($true) { $l = $r.ReadLine(); if ($null -eq $l) { return $null }
                               if ($l -notmatch '"event"') { return $l } } }
    $w.WriteLine('{"execute":"qmp_capabilities"}'); $null = & $reply
    $w.WriteLine($json); $res = & $reply
    $c.Close()
    return $res
}

function Hmp([string]$line) {
    $j = @{ execute = "human-monitor-command"; arguments = @{ "command-line" = $line } } | ConvertTo-Json -Compress
    $res = Qmp $j | ConvertFrom-Json
    if ($res.error) { throw "HMP '$line': $($res.error.desc)" }
    return $res.return
}

function Capture([IntPtr]$h, [string]$file) {
    if ([XemuWin]::IsIconic($h)) { throw "xemu window is minimised" }
    $wr = New-Object XemuWin+RECT; [XemuWin]::GetWindowRect($h, [ref]$wr) | Out-Null
    $cr = New-Object XemuWin+RECT; [XemuWin]::GetClientRect($h, [ref]$cr) | Out-Null
    $pt = New-Object XemuWin+POINT; [XemuWin]::ClientToScreen($h, [ref]$pt) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($wr.R - $wr.L), ($wr.B - $wr.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc(); $ok = [XemuWin]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc); $g.Dispose()
    $rect = New-Object System.Drawing.Rectangle ($pt.X - $wr.L), ($pt.Y - $wr.T), $cr.R, $cr.B
    $client = $bmp.Clone($rect, $bmp.PixelFormat); $bmp.Dispose()
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
    $client.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $client.Dispose()
    "captured $($cr.R)x$($cr.B) (printwindow=$ok) -> $file"
}

function SendKey([IntPtr]$h, [string]$btn, [bool]$down) {
    $k = $map[$btn]
    if (-not $k) { throw "unknown button '$btn' (known: $($map.Keys -join ' '))" }
    $l = [Int64](1 -bor ($k[1] -shl 16) -bor ($k[2] -shl 24))
    if ($down) { [XemuWin]::PostMessage($h, 0x100, [IntPtr]$k[0], [IntPtr]$l) | Out-Null }
    else { [XemuWin]::PostMessage($h, 0x101, [IntPtr]$k[0], [IntPtr]($l -bor 0xC0000000L)) | Out-Null }
}

switch ($Command) {
"start" {
    if (OurProcess) { "already running (pid $((OurProcess).Id))"; break }
    if (-not $Exe) { $Exe = if ($env:XEMU_EXE) { $env:XEMU_EXE } else { Join-Path $defaultDir "xemu.exe" } }
    if (-not (Test-Path $Exe)) { throw "xemu.exe not found: $Exe (-Exe or XEMU_EXE)" }
    $u = if (Test-Path $userCfg) { Get-Content $userCfg -Raw } else { "" }
    if (-not $Iso) {
        $Iso = if ($env:XEMU_ISO) { $env:XEMU_ISO } else { TomlValue $u "dvd_path" }
        if (-not $Iso -or -not (Test-Path -LiteralPath $Iso)) {
            $Iso = (Get-ChildItem -LiteralPath (Split-Path -Parent $Exe) -Filter "*.iso" | Select-Object -First 1).FullName
        }
    }
    if (-not $Iso -or -not (Test-Path -LiteralPath $Iso)) { throw "ISO not found (-Iso or XEMU_ISO)" }
    $bootrom = TomlValue $u "bootrom_path"; $flash = TomlValue $u "flashrom_path"
    $hdd = TomlValue $u "hdd_path"; $eeprom = TomlValue $u "eeprom_path"
    if (-not $bootrom -or -not $flash -or -not $hdd) { throw "bootrom/flashrom/hdd paths missing in $userCfg" }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $ourHdd = Join-Path $work "xbox_hdd.qcow2"; $ourEeprom = Join-Path $work "eeprom.bin"
    if (-not (Test-Path $ourHdd)) { Copy-Item -LiteralPath $hdd $ourHdd }
    if (-not (Test-Path $ourEeprom) -and $eeprom -and (Test-Path -LiteralPath $eeprom)) { Copy-Item -LiteralPath $eeprom $ourEeprom }
    $vol = if ($Audio) { "1.0" } else { "0.0" }
    $cfg = Join-Path $work "xemu.toml"
    @"
[general]
show_welcome = false
skip_boot_anim = true

[input.bindings]
port1_driver = 'usb-xbox-gamepad'
port1 = 'keyboard'

[display]
renderer = 'VULKAN'

[audio]
volume_limit = $vol

[perf]
cache_shaders = false

[sys.files]
bootrom_path = '$bootrom'
flashrom_path = '$flash'
eeprom_path = '$ourEeprom'
hdd_path = '$ourHdd'
dvd_path = '$Iso'
"@ | Set-Content -Encoding ASCII $cfg
    $fg = [XemuWin]::GetForegroundWindow()
    $argList = @("-config_path", "`"$cfg`"", "-dvd_path", "`"$Iso`"",
                 "-qmp", "tcp:127.0.0.1:$Port,server=on,wait=off")
    $p = Start-Process -FilePath $Exe -ArgumentList $argList -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
    Set-Content -Path $pidFile -Value $p.Id
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 200; $p.Refresh()
        if ($p.HasExited) { throw "xemu exited at start (code $($p.ExitCode))" }
        if ($p.MainWindowHandle -ne 0) { break }
    }
    if ($fg -ne [IntPtr]::Zero) { [XemuWin]::SetForegroundWindow($fg) | Out-Null }   # give focus back
    $state = ""
    for ($i = 0; $i -lt $BootWaitSec; $i++) {
        try { $state = (Qmp '{"execute":"query-status"}' | ConvertFrom-Json).return.status; break } catch { Start-Sleep -Seconds 1 }
    }
    "started xemu pid $($p.Id) with '$Iso' (muted: $(-not $Audio)), QMP port $Port, state '$state'"
    if ($Snapshot) {
        $r = Hmp "loadvm $Snapshot"; if ($r) { $r }
        if ($Paused) { Start-Sleep -Milliseconds $SettleMs; $null = Qmp '{"execute":"stop"}' }
        "loaded snapshot '$Snapshot'$(if ($Paused) { ' (paused)' })"
    }
}
"stop" {
    $p = OurProcess
    if (-not $p) { "our xemu is not running"; break }
    try { $null = Qmp '{"execute":"quit"}' } catch {}
    if (-not $p.WaitForExit(10000)) { Stop-Process -Id $p.Id -Force }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    "stopped xemu pid $($p.Id)"
}
"status" {
    $p = OurProcess
    if ($p) {
        $p.Refresh()
        $st = try { (Qmp '{"execute":"query-status"}' | ConvertFrom-Json).return.status } catch { "no QMP" }
        "ours: pid $($p.Id), window '$($p.MainWindowTitle)', state $st"
    } else { "ours: not running" }
    Get-Process xemu -ErrorAction SilentlyContinue | Where-Object { -not $p -or $_.Id -ne $p.Id } |
        ForEach-Object { "user's xemu: pid $($_.Id), window '$($_.MainWindowTitle)'" }
}
"cap" {
    if (-not $Target) { $Target = if (OurProcess) { "ours" } else { "user" } }
    if (-not $Out) { $Out = Join-Path $root "shots\xemu\$Target.png" }
    Capture (TargetWindow $Target) $Out
}
"press" {
    $h = TargetWindow $Target
    foreach ($step in ($Keys -split ",")) {
        $step = $step.Trim(); if (-not $step) { continue }
        $parts = $step -split ":"
        if ($parts[0] -eq "wait") { Start-Sleep -Milliseconds ([int]$parts[1]); continue }
        $hold = if ($parts.Count -gt 1) { [int]$parts[1] } else { 120 }
        $btns = $parts[0] -split "\+"
        foreach ($b in $btns) { SendKey $h $b $true }
        Start-Sleep -Milliseconds $hold
        foreach ($b in $btns) { SendKey $h $b $false }
        Start-Sleep -Milliseconds $Gap
    }
    "pressed: $Keys"
}
"pause"     { $null = Qmp '{"execute":"stop"}'; "paused" }
"resume"    { $null = Qmp '{"execute":"cont"}'; "resumed" }
"save"      { if (-not $Name) { throw "-Name" }; Hmp "savevm $Name" }
"load"      { if (-not $Name) { throw "-Name" }
              # Loaded while running and paused -SettleMs later: right after a
              # load xemu still shows a stale frame from before the snapshot.
              $null = Qmp '{"execute":"cont"}'
              Hmp "loadvm $Name"
              if ($Paused) { Start-Sleep -Milliseconds $SettleMs; $null = Qmp '{"execute":"stop"}' }
              "loaded '$Name'$(if ($Paused) { ' (paused)' })" }
"delete"    { if (-not $Name) { throw "-Name" }; Hmp "delvm $Name"; "deleted '$Name'" }
"snapshots" { Hmp "info snapshots" }
"hmp"       { Hmp $Cmd }
"qmp"       { Qmp $Cmd }
default     { throw "unknown command '$Command'" }
}
