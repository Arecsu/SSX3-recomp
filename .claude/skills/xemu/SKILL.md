---
name: xemu
description: Control the xemu Xbox emulator for SSX 3 reference comparisons - boot it with the ISO, restore saved snapshots (character select, race briefing, race start) in about a second, press controller buttons, pause/resume and take lossless screenshots without stealing the user's focus. Use whenever our recompiled build's output needs checking against real Xbox behaviour (lighting, colours, geometry, menus, race scenes).
---

# xemu control (SSX 3 reference)

Everything goes through `tools\xemu.ps1` in the ssx3-recomp repo (Windows
side). From WSL:

```bash
cd /mnt/c/Code/Xbox/ssx3-recomp
X() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\\xemu.ps1 "$@"; }
X start -Snapshot race_go -Paused     # boot + restore a state: ~2.5 s
X cap -Out 'C:\Code\Xbox\ssx3-recomp\shots\xemu\race.png'
X stop
```

After editing the script in WSL run `scripts/sync-windows.sh` first (the
Windows copy is what runs).

## Commands

| Command | What |
|---|---|
| `start [-Snapshot tag [-Paused]] [-Iso p] [-Exe p] [-Audio] [-Port 4455]` | Boot **our own instance** (see below). With `-Snapshot` it restores that state right away. |
| `stop` | Quit our instance (QMP `quit`, then its PID). Never kills other xemu processes. |
| `status` | Our instance (pid, run state) and any user xemu. |
| `cap [-Out file] [-Target ours\|user]` | Screenshot of the client area (1280x960 = 2x our 640x480), PrintWindow: no focus change, works when covered, not when minimised. Default target: ours if running, else the user's. |
| `press -Keys "..." [-Target ours\|user] [-Gap 250]` | Button steps, comma-separated: `a`, `start:300` (hold ms), `a+down:500` (together), `wait:2000`. |
| `pause` / `resume` | Freeze / continue the emulated machine (QMP stop/cont). |
| `save -Name t` / `load -Name t [-Paused]` / `delete -Name t` / `snapshots` | VM snapshots (~1 s each way, ~55 MB, inside our HDD copy). |
| `hmp -Cmd "..."` / `qmp -Cmd '{...}'` | Raw monitor access (e.g. `hmp -Cmd "info status"`). |

Buttons (xemu's default keyboard map): `a b x y up down left right start back
white black lt rt ls rs lsup lsdown lsleft lsright rsup rsdown rsleft rsright`.

## Our instance vs the user's xemu

`start` launches a separate xemu: config `work\xemu\xemu.toml` (regenerated
each start), its own copies of the user's HDD image and EEPROM in
`work\xemu\`, **muted** (pass `-Audio` only if sound is needed and the user is
around), only the keyboard bound (the user's real pad never reaches it), no
shader cache (that cache is shared with the user's xemu), QMP on
127.0.0.1:4455. It runs fine next to the user's own xemu. Key presses are
posted window messages: SDL reads them without focus, so the user's keyboard
focus is never taken (`start` also hands focus back after the window opens).

- Never `press` into the user's xemu (`-Target user`) unless they asked for
  it; `cap -Target user` is harmless.
- `stop` our instance when done; restarting from a snapshot is ~2.5 s.
- Snapshots belong to the ISO + HDD copy they were made with. Deleting
  `work\xemu\xbox_hdd.qcow2` deletes all snapshots.

## Snapshots (SSX 3 PAL, Griff, Snow Jam race)

| Tag | State |
|---|---|
| `charsel_griff` | Select Character, Griff highlighted (the lighting reference screen) |
| `race_briefing` | Snow Jam race briefing (Griff, Nate, Marisol, Marty, Psymon, Allegra) |
| `race_go` | Race start, "GO!" (with `-Paused`: ~1 s into the race, riders leaving the gate) |

A load restores a stale picture for the first frames; `-Paused` runs 150 ms
(`-SettleMs`) before freezing, so the captured frame is current. Check what
exists with `X snapshots`.

Recreating them from a cold boot (`X start`, fresh save, ~2.5 min):

1. Wait ~20 s (EA/intro movies), `press -Keys "start,wait:3000"` until the
   title shows "Press START", then `start:200` -> Main Menu (fades in ~1.5 s).
2. `a:200` (Single Event) -> Select Character. On a fresh save the default
   rider is one left of Griff (3x `right` landed on Elise, 2x `left` back on
   Griff) -- step with `left`/`right` and `cap` to read the name under the
   silhouettes. `save -Name charsel_griff`.
3. `a:200,wait:3000,a:200,wait:3000,a:200,wait:3000` (Griff, Continue,
   Peak 1) -> Select Mode; `a:200,wait:3000,a:200,wait:3000` (Race, Snow Jam)
   -> My Rules; `a:200,wait:25000` -> briefing. `save -Name race_briefing`.
4. `a:200,wait:2500`, `pause`, `cap` to check for "GO!", `save -Name race_go`.

Start during the race intro opens the pause menu (Return/Restart/Audio/
Options/Quit); `start` again resumes.

## Comparing with our build

Our side: `tools\menu_test.ps1 -Steps 'start,wait,right,wait,right,wait,right,wait,wait' -ShotDir shots\griff`
(Select Character, Griff) or `tools\race_test.ps1 -Runs 1 -RaceSec 5 -NoTaps -Rider 3 -Snap shots\race.png`
(Snow Jam as Griff). Our frames are 640x480, xemu's 1280x960: compare at
the same scale. Timing never matches to the frame (animation, AI riders), so
compare materials/lighting/colour, not exact poses.
