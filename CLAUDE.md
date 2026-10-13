# SSX 3 (Xbox) static recompilation — agent notes

Static recompilation of SSX 3 (PAL, title ID 0x4541003C, XDK 5558, built
2003-09-19, entry point 0x00181AD2) with
[sp00nznet/xboxrecomp](https://github.com/sp00nznet/xboxrecomp), from the
owner's own disc rip. Target: the toolkit's Windows/MSVC/D3D11 path, driven
from WSL.

**Status (2026-10-13):** playable. Boots, intro, menus, race load and live
races on Snow Jam with HUD, rider shadows and (newly) audio; 4-9 FPS with
the toolkit's software rasteriser. `tools\play.bat` starts it with the
keyboard as player 1 (an XInput pad also works). Reliability boot -> race
briefing ~8/9 runs (an intermittent race-load stall at 43% remains). Open:
speed (no GPU path), an intermittent black shadow wedge in races, the
pink-lit start area. Details under "Known open items" below; the toolkit
changes are all in `patches/xboxrecomp-local.patch` (base 193e299).

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
| `tools/play.bat` | **Play it**: starts the build with `RECOMP_KEYBOARD=1` (keyboard = player 1, merged with any XInput pad); key map in the file; logs to `play_std*.txt`. |
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
| Stuck on "Loading..." (fade never ends) | State machine `sub_001AD880` keeps 0 in ebx; the loading draw `sub_001AD7B0` calls CRT `exp()` (`sub_00213850` → `ctrandisp1`), whose lifted x87 dispatcher returns with ebx = 0x000D1284 (confirmed by the ABI check; most likely its `pop ebx` reads a stale slot because a computed-jump tail leaves guest esp 4 high — not yet verified). `cmp [esi+0x38], bl` then never matches → no render → update counter (`app+0x20`) never resets → updates stop at the 12-per-frame cap. Found with `tools\build.bat 16 abi` (`[ABI] sub_00213850: ebx 0->000D1284`) | Native `exp`/`fmod` overrides (`sub_00213850`, `sub_00212C18`, the only stubs into ctrandisp1/2) in `src/ssx3_overrides.c` |

All env defaults are set in `src/main.c` only when unset, so a run can override them.

## Known open items / next steps

- Status (2026-10-13): PLAYABLE to gameplay, reliably (3/3 boot→race) —
  boot → intro → menus → race load → live race on Snow Jam with full HUD
  (docs/screenshots/12-15), 6-8 FPS (was ~4-5) with the toolkit's software rasteriser (multithreaded; the D3D11
  pgraph translator is not used for vertex-program titles). The fix that got
  the race to load was seeding script native 0x69 (below). Next: speed
  (hardware rendering), audio output check, real-pad/keyboard play.
- Performance (measured with the profiler, `tools\live.ps1 dump -Mem profile`
  + `tools/profile_tally.py build/ssx3_recomp.map stderr.txt`): in a race the
  main thread spends ~86% spinning in D3D kickoff `sub_00234A10`, waiting for
  the PFB flush bit (NV2A 0x100410 bit 16) to clear. The toolkit clears it in
  `nv2a_ack_thread`, the same loop that executes and software-rasterises the
  pushbuffer, so title and "GPU" run strictly in turn and FPS = rasteriser
  speed (~5 with 300-850 draws; most triangles are below the worker-pool
  threshold and are drawn on the executor thread). A dedicated ack thread
  (toolkit patch, opt-in `RECOMP_NV2A_ACK_THREAD=1`) removes the serialisation
  but then the title wraps the pushbuffer ring more than once per executor
  pass and stalls in MakeSpace (0x00234BE0 → 0x00234850): needs multi-wrap
  ring tracking or PUT throttling. Follow-up (in the toolkit patch, active
  only with that flag): the executor now performs BACK_END_WRITE_SEMAPHORE_
  RELEASE (0x1D70, D3D's fence "time"; SSX 3 emits thousands) via
  `xbox_Nv2aSemaphoreRelease`, writing the fence (`*[dev+0x30]`) and PGRAPH
  0x400B10, and the fence mirror stands down. Fences are then honest, but the
  title stalls in BlockOnTime `sub_00234BE0` waiting for a time whose
  commands were written (dev write ptr past PUT) yet never kicked off — the
  lock-step mirror hid that D3D expects something else to kick them. Next
  step there: work out sub_00234BE0's kick conditions. Real speed needs hardware rendering
  (vertex-program titles into the D3D11 pgraph translator) or batch-parallel
  rasterising.
  DONE (toolkit patch): batch-level parallel rasterising — vertex-program
  draw calls queue their set-up triangles and the pool draws the batch split
  by screen row (y % n), preserving per-pixel order; opt-out
  `RECOMP_RASTER_BATCH=0`. Race: 4-5 → 6-7 FPS on heavier scenes; executor
  ~10.5 ms/batch (was ~15). `RECOMP_EXEC_STATS=1` prints executor busy %,
  batches, KB and ms/batch every 5 s. `tools\to_race.ps1` drives a live
  session from boot into a race by draw count (start it after
  `tools\live.ps1 start`; press A at the briefing if it lands mid-transition).
  Executor phase split in a race (RECOMP_EXEC_STATS): raster ~65-70%, vertex
  programs ~15%, setup ~2%, other (parsing etc.) ~15%. Raising the toolkit's
  NV_RASTER_MAX_THREADS cap 16 → 32 (pool = cores-4 = 28 here) gave 7-8 FPS.
  Flush accounting (RECOMP_EXEC_STATS "[EXEC] flushes:" line): ~96% of
  raster area already goes through the parallel pool; in a race the title
  draws ~3.5-5 M bounding-box pixels per frame (11-17 screens; the race
  briefing ~25 M). What remains is the per-pixel cost of software register
  combiners + texturing + blending (a few hundred ns/pixel/thread). The
  toolkit's D3D11 pgraph translator is a 650-line stub; a real GPU path means
  porting xemu-style vertex-program and combiner shader generation (weeks).
- Race-briefing glitch (pink ground / torn shapes behind the briefing panel):
  ruled out so far — texture formats (all DXT1/DXT3, supported and cached),
  missing texture stages (0 batches), and the vertex programs:
  `RECOMP_VSH_BADSTATS=1` (toolkit patch) counts non-finite/absurd output
  positions per program hash and dumps the worst; every program is <=0.1%.
  The executor's large "degenerate/NaN" count is EA's stitched triangle
  strips (zero-area joins), not a bug.
  `tools\to_race.ps1 -StopAtBriefing` parks a live session on that screen.
  FIXED (2026-10-13, toolkit patch nv2a_pb_exec.c):
  * Torn streaks at the screen edges: near clipping. The executor clipped only
    at w = 0.001 and rebuilt clip space from c[58]/c[59], which are 0 for
    SSX 3 (its programs keep the viewport elsewhere), so every clipped
    triangle collapsed to a point and geometry between eye and near plane
    was drawn at huge coordinates. Now clipped in (x*w, y*w, z*w, w) — an
    affine image of clip space, no constants needed — against w > 0.001 and
    z >= 0. `RECOMP_CLIP_NEAR_Z=0` = old w-only behaviour.
  * Swizzled render targets (SURFACE_FORMAT type 2): SSX 3 draws six 128x128
    rider shadow maps per frame (124x124 clip) and samples them projected
    onto the snow; the executor wrote them row-major. Now written at Morton
    offsets (put_pixel / clear_surface), cleared over CLEAR_RECT (0x1D98/
    0x1D9C, swizzled surfaces only). Rider shadows now render.
    `RECOMP_SWIZZLED_RT=0` = old behaviour.
  * Texture address modes MIRROR (2) and BORDER (4, with
    SET_TEXTURE_BORDER_COLOR 0x1B24 when FORMAT bit 3 = border source colour).
  The pink ground itself is (very likely) real: the start gate is lit by pink
  neon (see the race-start cinematic), and the combiner (t0*t1 modulate-2x +
  fog lerp) and A8R8G8B8 decode were verified. Its stage-1 128x128 ARGB
  texture holds unrelated DXT bytes (never written during the briefing —
  watchpoint), origin unknown.
  OPEN: an intermittent hard-edged black wedge in races (~1-3% of the screen
  in 2 of 8 frames, worst with an airborne rider over a falling slope) = a
  rider's shadow map projected onto the terrain where the map is black with
  alpha 1. What is known (2026-10-13):
  * Per frame and rider: CLEAR (format 0x07070128, pitch layout, 128x128,
    colour 0 -> whole map transparent), then ~6-8 batches of the rider with
    shadow program BC25EF09 (oD0 = c[57].yzwx; c[57] = (1,.3,.3,.3) -> grey,
    alpha 1), then 2 batches (66 and 72 indices) with c[57] = (1,0,0,0) ->
    black, alpha 1, identical render state. The game uploads both c[57]
    values itself ([C57] trace). Those two meshes span the map (y ~0..127
    at x ~50..80) -- probably the board, long under a top-down light. Clip
    is (2,2) 124x124 so the border stays transparent.
  * Receiver pass (vsh CF752D6F): stage 0 = the map, PROJECT2D, clamp,
    colour r0 = t0, alpha r0.a = t0.a (no distance attenuation), final =
    fog.a * r0, alpha test GREATER 0x14, blend ZERO/SRC_COLOR. Texture
    coordinates are sane (q = 1). So black map texels darken to black.
  * Checked and matching xemu: vsh swizzle fields (C swizzle bits 2-9),
    disabled stage reads (0,0,0,1), r0.a init. Not the cause: stale c[57]
    (SET_FOG_PLANE 0x09D0 -> c[57] and SET_EYE_POSITION 0x0A50 -> c[56] are
    now mapped like xemu, no change), stride-0 attributes (tried, reverted),
    clear ring, border colour.
  Reliability with this build: race_test 5/6 (one timeout, log lost; the
  next 3 were OK).
  Next idea: compare against real footage/xemu for whether the board shadow
  is meant to be black, and check the receiver depth test / the board
  meshes' role. `RECOMP_SWIZZLED_RT=0` removes shadows and wedges together.
  Instruments: `RECOMP_RT_TRACE=1` ([RT] draws sampling a render target,
  [RTDRAW] draws into one, [RTBLACK] black samples with combiner/tex coords,
  [RTPIX], [RTWRITE] opaque-black writes into a render target, [RTCLR]
  clears of shadow maps, [RTC57] c[57] per surface, [RTSEQ] shadow-related
  batch sequence once a black sample is seen, [RTVTX] caster inputs,
  [RTEXT] caster screen extents), `RECOMP_C57_TRACE=1` (every value change
  of c[57], method vs upload), `RECOMP_SURF_TRACE=1` (distinct surface/format pairs),
  `RECOMP_PIXEL_PROBE=x,y[,delay_ms[,max]]` (every write to one pixel with
  src/dst/blend/combiner/texture state, [PROBE]/[PROBE-RC]),
  `live.ps1 dump -Mem "watch <va>"` (hardware write watchpoint on a guest
  dword, all threads, [WATCH] with native RIP + guest stack; ours,
  src/thread_dump.c). Unhandled-method report keys now include the
  subchannel (0xS_MMMM); SSX 3 binds image-blit/surfaces-2D objects on
  subch 2/3 but never blits.
- AUDIO (fixed 2026-10-13, toolkit patch src/apu): SSX 3 was silent. Its
  statically linked DirectSound drives the emulated APU directly; the voice
  processor's mix was written into `monitor.frame_buf` and then cleared by
  the XAudio2 output path, which only ever submitted the HLE software mixer
  + test tone. Now a VP frame (256 samples) is kept, the software mixer is
  added on top and exactly those samples are submitted (up to 12 queued).
  The frame thread's throttle also reset its schedule whenever a wake came
  more than one 5.3 ms frame late (Windows 15.6 ms timer tick), running the
  APU at ~85% of real time; it now resyncs only when >64 ms behind and asks
  for 1 ms timer resolution. `RECOMP_APU_LEVEL=1` prints the submitted peak
  and buffers/s once a second: 188/s = 48 kHz, peaks 12-23k in intro,
  menus and race. Not yet checked by ear. The waveOut fallback path still
  has the old behaviour (XAudio2 is used on Windows).
  Reliability after the audio fix: race_test 3/3; one live session stalled
  at the race-load 43% (the old intermittent stall) -- watch for it.
- Guest CPU lock (`RECOMP_GUEST_LOCK=1`, toolkit feature, now a main.c
  default): one guest thread runs guest code at a time, switching at kernel
  calls, like the Xbox's single CPU. Without it the race load intermittently
  hung at 43% (resource-table entries 0 and 40 stuck in state 8 = "streaming",
  set by `sub_000E0490` → streamer `sub_0020B700`; poll loop `sub_000CC0A0`)
  or crashed in the world streamer (0x0020D26A). `tools\race_test.ps1 -Runs N`
  repeats boot→briefing and reports OK / CRASH / FAIL per run.
  The lock alone deadlocked 2/2 runs at the race load: the loader thread
  polls its I/O slots in `sub_001795A0` (called from `sub_00175500`) with no
  kernel call, holding the guest CPU, while the worker that completes them
  waits for it. Fix (toolkit patch): the recompiler emits
  `RECOMP_LOOP_YIELD();` at every loop head (label with a back-edge
  predecessor, translator.py); it is a TLS countdown that every 4096
  iterations releases the guest CPU, SwitchToThread()s and re-takes it —
  preemption at loop granularity, like the console's quantum. Regenerating
  needs the new templates/runtime/recomp_types.h: delete
  src/recomp/gen/recomp_types.h first (the pipeline never overwrites it).
  Result: `race_test.ps1 -Runs 3` → 3/3 reached the race briefing (lock
  alone: 0/2). Gameplay 6-7 FPS with the yields (7-8 without; within run
  variance). RECOMP_DSP_ACK is no longer needed: the `sub_0025BD81` `_gen`
  wrapper registers the DirectSound DSP command word at run time via the
  toolkit's new `xbox_DspAckAdd` ("DSP ack: command word 0x83818810
  registered at run time").
- Known intermittent crash: race load sometimes faults in the loader worker
  (thread #4) in the world-streaming code (guest 0x0020D26A ← 0x0020D788 ←
  0x0020DD16 ← 0x0020E089 ← loader poll 0x000CC2C0) on a garbage pointer
  while processing worlds/BAM.big; an identical rerun passes. Suspect a data
  race that a single-core Xbox never exposes (guest threads run truly in
  parallel here).
- History of the race-load stall (fixed): entering the race (Snow Jam,

  Zoe) stalled in one of two ways, timing-dependent:
  (a) race loading screen stops at 43%: job worker thread #4 polls a resource
      package in `sub_000CC0A0` (start `sub_000E0370`, done? `sub_000DFE40`,
      per-resource state at 0x00312AC8 + id*16, 1/2 = loaded) while pumping
      `sub_000E0490` / `sub_0020AF20`;
  (b) black screen with a small yellow "Loading...", 0 FPS: the main thread
      is inside the script VM `sub_0016AB50` (fetch/dispatch: opcode <= 0x2A,
      jump table 0x0016B444; reached via sub_000CC8F0 → sub_000CABD0 →
      sub_000D4FB0 → sub_00166E30 → sub_00166C60 → sub_0016B4F0), spinning a
      "short script loop" — actually it runs from a NULL bytecode pointer.
  Root cause: with `RECOMP_GUARD_NULL=1` (guest page 0 inaccessible) the
  load faults at guest VA 0x8 in VM opcode 0x21 ("call native": table of 111
  script natives at 0x003319F0, entry = instruction byte 2). Native 0x69 =
  `sub_00159930` was the only one tools.disasm never detected; its ICALL
  failed ("[ICALL] Failed to resolve VA 0x00159930"), the fallback returned
  0, and `sub_00169A90` read the NULL result's type at +8. Now seeded
  (plus 0x000267B0, found by scanning .data/.rdata for pointers to
  undetected code after a ret/padding — only 2 real hits). An allocation-
  failure theory was ruled out: EA's allocator `sub_001A9BD0` is wrapped
  (`_gen`) to log `[ALLOC] FAILED`, and it never failed.
  Lesson: grep every run for `Failed to resolve` — each is a missed function.
- Live driving: `tools\live.ps1 start|snap|press -Buttons a|key -Key 0x0D|dump|stop`
  (`key` posts WM_KEYDOWN/UP to the window, exercising the real keyboard
  path; verified 2026-10-13: Enter presses reach the menus with
  `RECOMP_KEYBOARD=1`. `RECOMP_INPUT_DIAG=1` logs what the pad layer sees.)
  (RECOMP_PAD_LIVE + a trigger-file thread dump; `RECOMP_DUMP_MEM=va:len`
  adds guest memory to each dump). Menu path from boot: Start presses until
  the main menu (~40 s), then A ×7 (title/main, Single Event, Zoe, Continue,
  Peak 1, Snow Jam, My Rules). Window-title draw counts identify screens:
  main 339, character 984, setup 382, peak 275, event 367/413, rules 329,
  race loading 309, black race-load 22.
- Game flow: app runner `sub_001ADAC0` → state machine `sub_001AD880`, app
  object 0x00369550 = `[0x3A930C]`, phase `+0x5C`, current/next state `+4`/`+8`,
  updates `+0x20`; renderer object `[0x369528]` (vtable 0x002F7E50: `+0x44`
  "draw list empty?" `sub_001EA6A0`, `+0x50` flush/present `sub_001F3020`).
- Game logic is clocked by input: app `vtbl[5]` = `sub_000E1A80` consumes one
  sample from a 30-entry ring (input manager `[0x36952C]`, read `+0x2EE0`,
  write `+0x2EE4`) filled at ~60 Hz on the timer thread by `sub_000E1AE0`.
- Other `[ABI]` reports in the abi build are expected (SEH_prolog/epilog,
  `_chkstk`, CRT internals) except any new one in game code.
- USB/controller (works; `RECOMP_USB=1` default): main.c now calls
  `xbox_OhciInit()` and routes OHCI register faults (0xFED00000/0xFED08000)
  in the VEH — the template did neither. XAPI's USB class-driver table is at
  0x00279794 (entries: memory unit 0x08, XID 0x58, HID 0x03, hub 0x09; each
  `{0x82, class, .., Init, AddDevice, Remove}`). Its method pointers live in
  the XPP *code* section, which tools.disasm does not scan for pointers, so
  Init/AddDevice/Remove were missing; they are seeded in
  `analysis/icall_seeds.json` (8 entries). Enumeration stage byte is
  0x003A1B1B (stage 6 = config descriptor parsed → class AddDevice).
  Pad probes: `RECOMP_PAD_PRESS=0x10` (Start pulses), `RECOMP_PAD_SCRIPT`,
  `RECOMP_PAD_LIVE`, `RECOMP_KEYBOARD`; traces `RECOMP_USB_TRACE`,
  `RECOMP_USB_STATS`, `RECOMP_DPC_TRACE=<n>`, `RECOMP_TIMER_TRACE` (ours).
- Intro movie data/movies/Intro_DJ.mad is 155 MB (minutes long); skip with Start.
- Untranslated instructions reached (no-ops): `wbinvd`, `out`/`in`, `ldmxcsr`.
- Upstream candidates: the toolkit fixes in `patches/`; `tools.split`
  ignoring applied names (docs/DECOMP.md says otherwise); template
  `recomp_manual.c` declaring the thread-local registers as plain globals;
  the x87 dispatcher stack imbalance (ctrandisp1/trandisp1 tails); the ABI
  check not flagging esp returning too *high*.

## Gotchas

- Hand-written C must use `g_eax`/`g_esp`/... via `#include "recomp/gen/recomp_types.h"`;
  the bare `eax`/`esp` macros exist only under `RECOMP_GENERATED_CODE`. The
  registers are `__declspec(thread)`: a plain `extern uint32_t g_eax`
  (as in the template's recomp_manual.c) names the wrong storage.
- An override is `void sub_X(void)`: set `g_eax`, then `g_esp += 4` (pop the
  return address; plus 4*n for stdcall args).
- Re-running `tools.disasm` wipes the names; `scripts/regen.sh` re-applies them.
- Never disassemble the DOLBY section (DSP56300 microcode).
- Wrapping a function with many direct callers: declare
  `extern void sub_X_gen(void);` and define `void sub_X(void)` that calls it;
  the recompiler then emits the original body as `sub_X_gen` (regen + full
  rebuild).
- `--exclude-manual` only recognises `void sub_XXXXXXXX(void)` with nothing
  else on that line; a trailing comment silently keeps the generated body.
- Callee-saved register bugs: `tools\build.bat 16 abi` builds `build-abi\`
  with `-DRECOMP_ABI_CHECK`; run it with `run.ps1 -Build build-abi`.
- Field watching: `RECOMP_PEEK=<addrs> RECOMP_PEEK_EVERY_MS=2000` (ours,
  src/thread_dump.c) samples guest memory on a clock; `RECOMP_TRACE_FRAMETIMER=1`
  also logs the update gate (`[GATE]`) with return values and guest regs.
- Sync with `rsync -rc` (no `-t`), or Ninja rebuilds all 77 generated files.
- `tools/split_named.py` / `regen.sh` print the disasm stats; the split was
  verified byte-identical against the XBE (19,096/19,096).
- Ghidra (only needed to redo naming): Linux build in WSL, Jython enabled by
  unzipping `Extensions/Ghidra/*Jython.zip` into `Ghidra/Extensions/`; the
  toolkit's `run_ghidra.sh` is Git-Bash-only, so call `support/analyzeHeadless`
  with the same flags (raw x86:LE:32, base 0x10000, `SetAnalysisOptions.java`,
  `ExportXbeNames.py`).
