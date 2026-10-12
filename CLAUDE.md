# SSX 3 (Xbox) static recompilation — agent notes

Static recompilation of SSX 3 (PAL, title ID 0x4541003C, XDK 5558, built
2003-09-19, entry point 0x00181AD2) with
[sp00nznet/xboxrecomp](https://github.com/sp00nznet/xboxrecomp), from the
owner's own disc rip. Target: the toolkit's Windows/MSVC/D3D11 path, driven
from WSL.

**Status (2026-10-12):** boots, loads its data, and renders the game's own
"Loading..." screen (orange font + snowflake spinner), see
`docs/screenshots/04-loading-screen-plain-run.png`. It stays there: the window
title shows only 2 flips and FPS 0. Next job: find what the loading screen
waits on (see "Next steps").

## Layout

```
<parent>/                      ~/Code/Xbox on the original machine
  xboxrecomp/                  toolkit clone: v0.13.1 (193e299) + patches/xboxrecomp-local.patch
  ssx3-recomp/                 this repo
  SSX3/                        the rip: default.xbe + data/ (NOT in git; default_analysis.json is written here)
C:\Code\Xbox\{xboxrecomp,ssx3-recomp}   Windows build copy; game data in ssx3-recomp\game\
```

In this repo:

| Path | What |
|---|---|
| `src/main.c` | Host entry (from the template). Fills in SSX 3's entry point, registers the D3D fence mirror, sets the runtime env defaults SSX 3 needs (see below), starts the thread dumper. |
| `src/ssx3_overrides.c` | Hand-written replacements for generated functions (`--exclude-manual` skips their bodies) + bring-up tracing wrappers. |
| `src/recomp_manual.c` | Template file; `recomp_lookup_manual` routes indirect calls to `ssx3_lookup_trace`. Do not use its `extern uint32_t g_eax` — see gotchas. |
| `src/thread_dump.c` | `RECOMP_THREAD_DUMP_SECS=N`: native stack + guest registers of every thread. |
| `tools/build.bat` | MSVC + Ninja release build (Windows), `[jobs]` arg, default 16. |
| `tools/run.ps1` | Run with stdout/stderr capture, timeout kill, `-Watchdog N`, `-ThreadDump N`, `-Env @{...}`. |
| `tools/shot.ps1` | Run, screenshot the game window after `-After N` s, kill. |
| `tools/split_named.py` | `tools.split` with Ghidra names kept (upstream drops them). |
| `scripts/setup.sh` | Clone toolkit at the base commit, apply the local patch, make the venv. |
| `scripts/regen.sh` | Re-run the pipeline: analysis, `decomp/` split, `src/recomp/gen/` lift. |
| `scripts/sync-windows.sh` | rsync to `/mnt/c/Code/Xbox` (`--game` copies the rip once). |
| `analysis/ghidra_names.json` | 143 FidDb CRT/XDK names from Ghidra 12.1.4, so regen needs no Ghidra. |
| `patches/xboxrecomp-local.patch` | Toolkit fixes made during bring-up (upstream candidates). |
| `docs/screenshots/` | Progress screenshots (LFS). |

Not in git (regenerate with `scripts/regen.sh`): `src/recomp/gen/` (77 files,
1.7M lines of C) and `decomp/` (19,096 byte-exact `.s` files) — both are the
game's code. Nor the rip, `build/`, logs.

## Fresh machine

```bash
scripts/setup.sh                 # toolkit + venv (needs git, curl, python3)
scripts/regen.sh                 # ~2 min; needs ../SSX3/default.xbe
scripts/sync-windows.sh --game   # first time; later without --game
cmd.exe /c 'C:\Code\Xbox\ssx3-recomp\tools\build.bat'     # full build ~18 min
cd /mnt/c/Code/Xbox/ssx3-recomp && powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Code\Xbox\ssx3-recomp\tools\shot.ps1' -After 35
```

Windows needs VS 2022 with the C++ workload (MSVC 14.43 used; CMake and Ninja
come with it). WSL interop drives everything: `cmd.exe`/`powershell.exe` run
fine from a `/mnt/c` cwd. Run from the project root — the exe opens
`game\default.xbe` relative to the working directory.

## Iteration loop

1. Edit in WSL (`src/`, or the toolkit — then refresh the patch:
   `git -C ../xboxrecomp diff > patches/xboxrecomp-local.patch`).
2. Added/removed an override in `src/ssx3_overrides.c`? `scripts/regen.sh lift`
   (changes `recomp_funcs.h` → full ~18 min rebuild). Otherwise no regen.
3. `scripts/sync-windows.sh` then `tools\build.bat` (seconds when only
   hand-written files or one toolkit lib changed).
4. `tools\run.ps1` / `tools\shot.ps1`, read `C:\Code\Xbox\ssx3-recomp\stderr.txt`.

## Diagnosing

- **Hang**: `run.ps1 -Seconds 50 -Watchdog 40 -ThreadDump 35`. Pipe the
  `[THREADS]` block through `../xboxrecomp/tools/symbolize.py build/ssx3_recomp.map`
  (map is in the Windows build dir) — generated functions are native symbols
  named `sub_<guest VA>`, so the native stack *is* the guest call chain; guest
  regs per thread come from their TLS. The watchdog block goes through
  `tools/stackwalk.py tools/disasm/output/functions.json`.
  The main thread parked in `sub_001ADF40` is the normal frame wait, not a hang.
- **Crash**: `[CRASH]` in stderr, or Windows event log (Id 1000) fault offset;
  `symbolize.py` on `0x140000000 + offset`. The template VEH silently ignores
  faults in native 0xFD000000–0xFE000000.
- **Read code**: `decomp/asm/<section>/sub_XXXXXXXX.s` (disassembly is in the
  comments); `decomp/manifest.json` has callers/callees.
- Toolkit env knobs: `RECOMP_VSH_TRACE`, `RECOMP_VSH_DUMP`, `RECOMP_PB_EXEC_VERBOSE`,
  `RECOMP_PB_UNHANDLED_ALL`, `RECOMP_NV2A_TRACE`, `RECOMP_PB_REPORT_MS`,
  `RECOMP_PEEK`, `RECOMP_POKE`, `RECOMP_WATCH`, `RECOMP_UNIMPL_TRAP`
  (see `../xboxrecomp/docs/pipeline/06-debugging.md`).
  `RECOMP_TRACE_FRAMETIMER=1` (ours) logs the frame-timer object's methods.

## What was fixed, in boot order

| Blocker | Cause | Fix |
|---|---|---|
| Quick-reboot at startup | XAPI media check `sub_00183EBB` reads the DVD security sector and verifies its RSA signature; impossible from a file rip | Override returns 0 (its own "no check needed" path) — `src/ssx3_overrides.c` |
| Spin in D3D `sub_00234BE0` (BlockOnTime) | GPU completion `*[dev+0x30]` never catches up with `[dev+0x2C]`; device ptr at 0x0024B0D8 | `xbox_Nv2aMirrorFence(0x0024B0D8, 0x2C, 0x30)` in main.c |
| XAPI timer thread `sub_0021C1B5` spinning | Toolkit `KeWaitForMultipleObjects` treated KTIMER/KEVENT pointers as handles; thread also builds its KEVENT by hand | Patch (kernel_bridge.c) + `RECOMP_TITLE_KEVENTS=1` |
| D3D waits on vblank event 0x0024CE8C between AvSetDisplayMode steps | No vblank interrupt delivered | `RECOMP_VBLANK=1` |
| Crash AddRef'ing 0xFFFFFFFF in DSOUND `sub_0025FC35` | DirectSoundCreate failed (E_OUTOFMEMORY): AC'97 codec not ready | `RECOMP_AC97_READY=1` |
| DSOUND spins at 0x0025BEE8 after effects download | Posts command 3 to GP DSP at scratch+0x810 and waits for a clear; DSP is a stub | `RECOMP_DSP_ACK=0x83818810` (fragile: allocation-order dependent; real fix = DSP stub acks) |
| All sprite triangles NaN/degenerate | Toolkit executor fed arrayless vertex attributes 0,0,0,1; SSX 3's sprite program reads its transforms from v8..v15 set by SET_VERTEX_DATA4F | Patch (nv2a_pb_exec.c `transform_vertex`) |
| Nothing visible | Window/executor are opt-in | `RECOMP_FB_WINDOW=1`, `RECOMP_PB_EXEC=1` |

All env defaults are set in `src/main.c` only when unset, so a run can override them.

## Known open items / next steps

- Loading screen does not advance: 2 flips total, FPS 0. Find what it waits on
  (thread dump; an EA audio thread `sub_00192280` sits in a multi-object wait —
  audio streaming / DSOUND notifications or APU interrupt vector 5 →
  0x0025CDAB are suspects; also check how flips/present are counted).
- Two unresolved indirect calls into XPP (USB/input): 0x00279960, 0x0027A16F.
- Frame timer runs at ~13 Hz (toolkit timer thread ticks at 10 ms).
- Untranslated instructions reached (no-ops): `wbinvd`, `out`/`in`, `ldmxcsr`.
- Upstream candidates: the two toolkit fixes in `patches/`; `tools.split`
  ignoring applied names (docs/DECOMP.md says otherwise); template
  `recomp_manual.c` declaring the thread-local registers as plain globals.

## Gotchas

- Hand-written C must use `g_eax`/`g_esp`/... via `#include "recomp/gen/recomp_types.h"`;
  the bare `eax`/`esp` macros exist only under `RECOMP_GENERATED_CODE`. The
  registers are `__declspec(thread)`: a plain `extern uint32_t g_eax`
  (as in the template's recomp_manual.c) names the wrong storage.
- An override is `void sub_X(void)`: set `g_eax`, then `g_esp += 4` (pop the
  return address; plus 4*n for stdcall args).
- Re-running `tools.disasm` wipes the names; `scripts/regen.sh` re-applies them.
- Never disassemble the DOLBY section (DSP56300 microcode).
- Sync with `rsync -rc` (no `-t`), or Ninja rebuilds all 77 generated files.
- `tools/split_named.py` / `regen.sh` print the disasm stats; the split was
  verified byte-identical against the XBE (19,096/19,096).
- Ghidra (only needed to redo naming): Linux build in WSL, Jython enabled by
  unzipping `Extensions/Ghidra/*Jython.zip` into `Ghidra/Extensions/`; the
  toolkit's `run_ghidra.sh` is Git-Bash-only, so call `support/analyzeHeadless`
  with the same flags (raw x86:LE:32, base 0x10000, `SetAnalysisOptions.java`,
  `ExportXbeNames.py`).
