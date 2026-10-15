# SSX 3 native — roadmap

**Goal:** SSX 3 runs natively on Windows, **≥ 60 FPS on the GPU**, with
**working audio**, the **whole game playable** and **no crashes**.

This file is the plan *and* the tracker: tick a box in the same commit that
lands the work, and add a dated line to the [log](#progress-log) for every
milestone change. Gates are measured, not judged by eye — each phase says
which test proves it.

**Where we are (2026-10-15):** playable on the Vulkan renderer at a steady
60 FPS in races (GPU vertex programs), audio through the emulated APU with no
crackle, keyboard/XInput input with rumble, save/load, fullscreen. 20/20
boot→race, 2-hour soak 120/120 race/quit cycles. Character and race lighting
match xemu. Open: Peaks 2/3 coverage, audio by ear, effects DSP, native
Windows build, upstreaming. See README and CLAUDE.md.

---

## Definition of done

| Area | Gate |
|---|---|
| Speed | Race on every peak: **p99 frame time ≤ 16.7 ms** (60 FPS) for 5 min, measured by `tools/bench.ps1`; menus and cutscenes at 60. |
| Rendering | GPU output matches the software rasteriser (reference) within tolerance on the screenshot suite; no known artifacts. |
| Audio | Music, speech, SFX and 3D voices audible and in sync, no gaps/crackle at 60 FPS; effects (reverb) present. |
| Function | Every mode, peak, event, menu, save/load and option works (coverage checklist in Phase 6). |
| Stability | 20/20 boot→race runs; 2-hour soak (automated play) with 0 crashes / 0 hangs. |
| Native | One Windows build from a Windows checkout (no WSL needed), game data path configurable, double-click to play. |

---

## Phase 0 — Measurement harness (first, everything else depends on it)

- [x] `tools/bench.ps1`: boot → race → `-Seconds` of riding (periodic A taps); parses `[FRAMES]`, writes `logs/bench_<ts>.json` with fps avg, median p50, worst p99/max, crashes and the 60 FPS gate. (Executor/guest split: add `-Env @{RECOMP_EXEC_STATS='1'}`.)
- [x] Frame-time counter in the host: `RECOMP_FRAME_STATS=1` prints `[FRAMES] n fps p50 p99 max` once a second from per-flip QPC timestamps (toolkit `fb_present.c`).
- [x] Scripted play: periodic A taps ride a whole race (it finishes by itself); `tools/soak.ps1` races back to back via the restart dialog.
- [x] Navigation from game state only (2026-10-14): `tools/to_race.ps1` reads `game_state.txt` (state, sub-state, GPU draw count) and nothing else -- frontend: Start, then A every 2 s; event_enter/loading: wait; ingame after a load: the briefing. Works on every renderer and with the window covered. Freeze = draw count still for 15 s. Intro movies skipped by default (`RECOMP_SKIP_INTRO`, mask 0x3083B8, found by Corné): boot -> title 3.4 s, boot -> race briefing ~25 s.
- [x] Game state hook (`src/game_state.c`): the game's own state machine published as `[STATE]` lines and `game_state.txt` (`tools/game_state.ps1`); top-level states named. Next: map the in-race sub-states and switch the scripts from draw counts to it.
- [x] `tools/race_test.ps1` extended: all peaks/events (2026-10-15: `-Peak/-Mode/-Event/-Rider`, every Race and Freestyle event on Peaks 1-3 runs) (2026-10-14: `-Rider N -Mode N -Event N` pick the rider, mode and Peak 1 event by the frontend screen id in game_state.txt; Peaks 2/3 are locked on a fresh save -- 2026-10-15: the default save fixture `work\saves\unlocked` has everything unlocked; left: a peak choice in RECOMP_AUTONAV / to_race.ps1), configurable run count (done), summary table; failures auto-dump with a 20 s write window (done) and are classified from the last screen -- `[title: no input]`, `[menu hang]`, `[load stall]`, `[other]`, `CRASH` (done).
- [x] Parallel test runs (2026-10-14): `tools/race_par.ps1 -Instances N -Runs M [-Env @{...}]` runs N game instances at once, each in its own directory `work\i<k>` (junction `game` -> the shared rip; own pad file, pid, logs, triggers, `game_state.txt`; `live.ps1` / `to_race.ps1` / `race_test.ps1` take `-Dir`), with `RECOMP_RASTER_THREADS` = cores / N each. Summary printed and saved to `logs/race_par_<ts>.txt`. 2 instances = 2 runs in the time of one; use 6-10 for the ~1-in-10 bugs (63 GB RAM / 32 cores here). Default for reliability work from now on.
- [x] Watchdog in `to_race.ps1` (2026-10-14, default on, `-NoWatchdog` off): a run ends early with `stuck: [<class>]` when Start presses go unread for 45 s (`[no pad]`), FPS is 0 for 15 s in the menus/loading/race (`[freeze]`), or a game state outlives its budget (boot 60 s, intro 120 s, frontend 180 s, event_enter 30 s, loading 90 s: `[<state> stall]`); `race_test.ps1` reports that class and still dumps threads first. A stuck run costs 20-50 s instead of the 5-8 min timeout: race_par 8x2 went from 22 to 4.6 min.
- [x] Watchdog: also keep a screenshot of every stuck run (2026-10-15: race_test saves `logs\fail_<time>.png` before the dump).
- [ ] Use parallel runs everywhere: `bench.ps1` / `shots.ps1` / `soak.ps1` take `-Dir` too, so measurements can run beside a reliability batch (note: concurrent instances share the CPU, so benchmarks must run alone).
- [x] Screenshot suite: `tools/shots.ps1` saves every distinct menu screen (by draw count), the briefing and 4 race shots into `logs/shots_<ts>[_label]/`; first software-path reference set: `logs/shots_20261013-235549_software` (16 shots). Per-peak race spots come with the all-peaks navigator.
- [x] Baseline numbers recorded here (2026-10-13, default build, Snow Jam race, `tools/bench.ps1 -Seconds 90`):
  - **Software rasteriser, async executor:** 9.9 FPS avg, p50 101 ms, p99 267 ms, 0 crashes (`logs/bench_20261013-232858.json`).
  - **CPU floor** (`RECOMP_RASTER_SKIP=1`: everything but the pixels): 10–35 FPS in the race. Profile: the main thread waits on the GPU most of the time -- D3D fence waits (`KeWaitForSingleObject`, 54% of samples) and polling a GPU visibility-test result (`sub_0022DE70` = D3D query GetData returning D3DERR_TESTINCOMPLETE, 24%); real game logic is ~19% of samples, **≈ 10 ms per frame** -- under the 16.7 ms budget. The executor's time is mostly CPU vertex-program interpretation (`nv2a_vsh_run`), then software-method round trips and the pushbuffer survey's `note()` (pure overhead).
  - Conclusion: 60 FPS is reachable on the CPU side once vertex programs, pixels and query results come from a GPU; Phase 2 is the right critical path.

## Phase 1 — Stability on the current path

Fix the known failures before the renderer changes so regressions stay visible.

- [x] **43% race-load stall** (~1 in 6) -- FIXED 2026-10-14: guest CPU kept across uncontended RtlEnter/LeaveCriticalSection (toolkit `kernel_thunk_dispatch`, `RECOMP_CS_KEEP_CPU`); EA's STRM end-tag scan had been interleaved by the extra preemption points. 0 stalls in 24 parallel runs. Was: world streamer loses a request (resource 0/40 stuck in state 8). Job queues ruled out (CLAUDE.md). Next: trace the streamer's own request state (`sub_0020DB60` object +0xAC/+0xC0/+0xC8), compare a good and a stalled run.
- [ ] Loader-worker crash in world streaming (intermittent; seen at `0x0020D26A` and `sub_0020CAB0` with a garbage chunk index) -- same streamer object as the 43% stall: one corruption bug (CLAUDE.md, "WORLD STREAMER CORRUPTION"). **2026-10-14:** the two-thread race on the streamer is ruled out (all entries wrapped, 16 runs, no overlap); thread dumps now carry `[STREAMDUMP]` (request list, slot records, resource table, fence wait). Two failure classes look alike at "43%": streamer stall (loading screen keeps drawing) vs async GPU freeze (draws stop, main thread in BlockOnTime).
- [ ] Any remaining async-GPU hang (map-select/rules class): soak-test the idle wake; replace it with exact behaviour if a better model of D3D's NOP patching emerges. **2026-10-14:** caught one (fence already past the waited time, wake lost); watchdog `[BLOCK-RESCUE]` delivers the owed wake (default on) -- 10 runs, 2 rescues, both raced. Root cause of the lost wake still open. **Later 2026-10-14:** no rescue in 32 runs at 8 parallel instances after the clock fixes. **2026-10-15:** the watchdog now checks every 5 ms and wakes a wait whose fence is already reached after 20 ms (was 50/200 ms, GetTickCount): ~30 such wakes in a 10-minute session, each now ~25 ms instead of 200+ -- D3D's own wake for a reached fence evidently often takes > 20 ms. Then 1 ms polling, 2 ms threshold: rescued waits ~4 ms; race 60 FPS p99 19.3; cycle_test 12/12 on Happiness; race_par 4x2 8/8. (The executor's idle wake waits 30 ms on a 16 ms clock -- a GPU-side fix would post a wake only while a wait is active.)
- [x] ISRs and DPCs run under the guest-CPU lock (single-CPU semantics; `RECOMP_IRQ_LOCK=0` to disable). They used to run on host threads in parallel with guest threads; the USB driver's enumeration then stalled in about 1 boot in 6 (no pad on the title screen). After: 6/6 runs enumerated fully.
- [ ] Guest-thread priority scheduling in the guest lock (Xbox is single-CPU, strict priority) — only if Phase 1 bugs point at ordering.
- [x] Title-screen movie freeze (was filed as "USB enumeration under load": the pad is fine, the frontend's background movie stream stops -- EA STRM ring, CLAUDE.md "TITLE-SCREEN MOVIE FREEZE"); was ~1 in 6 at 8 parallel instances. **2026-10-14: gone** -- 32/32 at 8 parallel instances (two 8x2 batches) since KeTickCount runs at 1 ms (the movie player and the fair handover's waits timed themselves with the stale ~16 ms clock).
- [ ] Crash in EA movie/stream code on the main thread (2026-10-14, 1 in 16 parallel runs): read fault at 0xE0220705, guest stack 0x00173B36 <- 0x00173C05 <- 0x001731CD <- 0x001740C4; log kept as `logs/crash_20261014_i8_stderr.txt` (Windows build dir).
- [x] Gate: 20/20 boot→race (2026-10-14: race_par 4x5 on Vulkan, 20/20 in 3.4 min). Vulkan only by
  decision: the software renderer stays as the fallback, the reference and for the surfaces Vulkan
  still hands to it (shadow maps, offscreen), but is no longer gated or batch-tested.

## Phase 2 — GPU renderer (Vulkan), the big one

Approach (2026-10-14, adopted from Corné Dorrestijn's `linux` branch, MR !1,
see `docs/VULKAN.html`): keep the executor's pushbuffer walk, state tracking
and CPU vertex programs (`nv2a_pb_exec.c`), and hand each draw to a Vulkan
renderer (`src/vk/`, toolkit hook `nv2a_backend.h`, `RECOMP_GPU=vk`) in place
of the software rasteriser: register combiners ported to GLSL, 4 texture
stages, fog, blend, alpha test, depth. Frames are read back into guest memory
and presented as before. Runs on Linux (Asahi) and Windows (Vulkan SDK). The
software rasteriser stays the reference for differential testing. The D3D11
path below (2.1) is superseded except for its presentation work.

Windows, first numbers (RTX 4080 SUPER, one instance): title 43 FPS, race
briefing 13, race 22-28 (software: 5-8 menus, ~3 briefing, 9-12 race).
Per second in a race: renderer draws ~80 ms, flip readback ~240 ms; the rest
is guest code and CPU vertex programs. The black polygons in the sky
(docs/screenshots/25) are fixed (2.0b, docs/screenshots/28).

- [x] 2.0 Vulkan by default (2026-10-14; `RECOMP_GPU=sw` = software, also the
  fallback without a Vulkan device): race_par 6x2 with Vulkan 12/12 OK in
  1.9 min; title, menus, briefing and races checked by screenshot.
- [x] 2.0b Black shapes in races (docs/screenshots/25), FIXED 2026-10-14:
  not Vulkan-specific (software showed them too). The executor had no case
  for ARRAY_ELEMENT32 (0x1808), which D3D uses for the last index of an
  odd-length index list, so every such batch lost its last vertex. The
  mountain backdrop is a ring of 15- and 33-index strips; each lost its last
  triangle and the black clear colour showed through. Check:
  `tools\race_test.ps1 -Runs 1 -TimeoutSec 150 -RaceSec 22 -NoTaps -Snap x.png`
  (airborne over the first jump, docs/screenshots/28). Diagnostics from the
  hunt: RECOMP_VKR_TRACE_EVERY, RECOMP_VKR_TRACE_BLACK=<n> (vkr_black.txt),
  RECOMP_VKR_TRACE_VSH=a-b.
- [ ] 2.0c Flip without the readback: present the Vulkan image directly
  (swapchain on the game window) instead of copying it to guest memory.
  Step 1 done (2026-10-14): the readback buffer is HOST_CACHED memory --
  flip 240 -> 100-140 ms/s (~5 ms per flip). Race frame (~44 ms, 22 FPS):
  renderer ~13 ms (texture decode+upload 100-140 ms/s for 70-100 new
  textures/s -- the six rider shadow maps, re-rendered every frame and
  created anew each time: update them in place; flip ~5 ms), the other
  ~31 ms guest code + CPU vertex programs (2.0d, Phase 3).
  Step 2 done: profile (race_test -Profile) showed the main thread waiting
  on the executor 75% of the time and the executor split between CPU vertex
  programs (~45%), the flip wait (~28%) and software-method waits (~20%,
  Sleep(1) polling). Now: the executor wakes by event when a trap is
  handled, and the frame's GPU work is submitted in pieces every 64 draws
  so the flip waits only for the tail. Race 22 -> 34-36 FPS (p50 26 ms),
  flip ~60 ms/s. Step 3 done: render-target textures (the shadow maps) keep
  one GPU texture per address, updated in place (vkr_tex_update) instead of
  a new image every frame (which also filled the 768 MB cache and forced a
  full purge every ~85 s). Race 38-43 FPS (p50 23 ms); decode+upload
  200 -> 85 ms/s, still the shadow maps' CPU decode (~125/s). Next: skip
  the decode for maps the GPU could render itself (swizzled targets on the
  GPU, 2.2) and the CPU vertex programs (2.0d).
  Step 4: post-transform vertex cache per batch (a vertex named twice in a
  strip/list runs once: ~35% of vertex-program runs saved,
  RECOMP_VSH_STATS=1 counts) and a parallel vertex-program pool for batches
  >= 256 vertices (RECOMP_VSH_THREADS; SSX 3's batches are mostly smaller,
  so it rarely engages). Race 42-45 FPS, p50 ~21 ms.
  Step 5 -- the frame-rate ceiling was the clock: the vblank was scheduled
  with GetTickCount64 (~15.6 ms steps) as "now + 16", i.e. every 15.6 or
  31.2 ms, ~43 Hz, and the title paces its frames on vblank. Now a 60 Hz
  grid from the performance counter; the timer thread waits until the next
  vblank/timer with 1 ms resolution; kernel timers use the same clock and
  stay on their period grid. Race 53-58 FPS, p50 17 ms, p99 24-33 ms.
- [x] 2.0d Vertex programs on the GPU (2026-10-14, default on, RECOMP_GPU_VSH=0 = CPU):
  src/vk/shaders/xbox_vsh.vert interprets the NV2A microcode per vertex (a port of
  nv2a_vsh_run), reading the program (toolkit nv2a_vsh_export: 8 words per
  instruction), the 192 constants and the vertex's packed inputs from the frame's
  upload buffer (binding 5); program and constants are uploaded once per recording
  while unchanged. The executor only fetches the attributes the program reads and
  offers the batch to the backend's draw_vsh; shadow maps, programs that write c[]
  and traced frames keep the CPU path. Race: 60.0 FPS, p50 16.6 ms, p99 20 ms (was
  ~57.5 / ~27); process CPU 2.15 -> 1.63 cores; race_par 4x2 8/8; title, menus,
  Options and race checked by screenshot.
  **2026-10-14 measurements:** the frame timer is now steady, so what is left of
  the hitches is GPU-executor time: every slow frame (`[SLOWFRAME]`, > 22 ms
  between flips, RECOMP_FRAME_STATS) has the executor busy for the whole
  interval (~800-860 draws). Executor thread profile (`profile_tally.py --thread
  nv2a_ack_thread`): CPU vertex programs ~42% (`nv2a_vsh_run`) + ~17% waiting for
  the pool running them; the Vulkan backend ~17%. Not the lever: shadow maps on
  the GPU (RECOMP_VKR_SKIP_RT=1 gains ~2 FPS), pool sizing per draw
  (RECOMP_VSH_PER_THREAD, neutral). Plan: the backend gets the raw vertex
  attributes, the program and its constants instead of transformed vertices;
  microcode -> GLSL -> SPIR-V cached by program hash (xemu's vsh translation
  rules); clipping by the GPU; draws into software surfaces (shadow maps) keep
  the CPU path.
- [ ] 2.1 Device and presentation: D3D11 device + swap chain in the game window; flips present the front surface; vsync-paced at 60 Hz. **Done (opt-in `RECOMP_D3D_PRESENT=1`, toolkit `src/video/gpu_present.c`):** device + DISCARD swap chain on the window, each flipped frame uploaded to the back buffer and presented with vsync (`RECOMP_VSYNC=0` off). Screenshots now come from inside the process (`RECOMP_SNAP_TRIGGER`, used by `live.ps1 snap`), since PrintWindow cannot read a swap chain. **2026-10-14: default** (main.c; =0 for GDI, whose Sleep(16) loop presented at ~59 Hz against the game's 60 with tearing) -- user visual check pending. Left: share the device with the renderer.
The original D3D11 items below (2.2-2.9) are superseded by the Vulkan path
above; what is still open from them, in Vulkan terms:
- [ ] 2.2 Shadow maps (swizzled render targets) and offscreen surfaces on the
  GPU -- today drawn in software and uploaded as textures (~300/s); worth
  ~2 FPS only (RECOMP_VKR_SKIP_RT measurement), so low priority.
- [x] 2.3 Textures: swizzled/linear/DXT/palettised, cube maps (2026-10-14),
  content-hash cache, render targets updated in place.
- [x] 2.4/2.5 Geometry and vertex programs on the GPU (2.0d); clipping by the GPU.
- [x] 2.6 Pixel pipeline: combiners interpreted in GLSL, stage modes 2D/3D/cube/
  passthrough, alpha test, fog, blend, colour mask, depth (bump/dot modes and
  stencil still open, not used by SSX 3 so far).
- [ ] 2.7 Present without the readback (2.0c).
- [ ] 2.8 Differential test GPU vs software on the screenshot suite.
- [x] Gate: races render correctly on the GPU; frame rate then limited by the guest CPU, not rendering (2026-10-14: steady 60 FPS, executor no longer the bottleneck).

## Phase 3 — CPU side to 60 FPS

With rendering off the CPU, the game itself must fit in 16.7 ms.

- [ ] Profile guest time per frame (sampling profiler + `tools/profile_tally.py`); list the top recompiled functions and kernel calls.
- [ ] Remove waits: GPU hand-off, guest-lock contention, loop-yield cost, timer/DPC latency; fence waits answered as soon as the GPU reaches them.
- [ ] Recompiler-level wins: x87 emulation hot paths, memory access helpers, indirect-call dispatch, `RECOMP_LOOP_YIELD` granularity.
- [ ] Frame pacing: the title's 60 Hz clock (vblank, input ring) matched to the host display; no drift at 60. **2026-10-14:** vblank and kernel timers on the performance counter (were GetTickCount, ~43 Hz effective vblank); left: sync to the host display's refresh.
- [ ] Gate: bench p99 ≤ 16.7 ms on every peak. **2026-10-15** (tools/bench.ps1 -Peak/-Event, 60 s, A taps): Snow Jam 60.5 FPS p99 21.8, Ruthless Ridge 60.5 / 27.8, Gravitude 60.6 / 27.8 (single slow frames); Metro-City 50 FPS -- the game itself drops to 30 in the tunnel section, xemu identically (tools/xemu_fps.ps1), so that is not ours to fix.

## Phase 4 — Audio, complete

- [ ] Verify by ear: music (EA Radio), speech, menu SFX, race SFX, 3D voices (`RECOMP_APU_LEVEL=1` shows 48 kHz and real levels today).
- [x] waveOut fallback path gets the same VP fix as XAudio2. (2026-10-15: keeps the voice processor's 256-sample frames, eight per 2048-sample waveOut buffer; `RECOMP_AUDIO=waveout` selects it; race level meter: 188 buffers/s, peaks 10-30k, same as XAudio2.)
- [ ] GP/EP DSP: real effects (reverb, mixdown) — DSP56300 emulation or HLE of the XDK effect images; replaces the doorbell ack.
- [ ] A/V sync at 60 FPS, no underruns under load; volume/pan/3D positioning correct.
- [ ] Intro/cutscene movies with sound. **2026-10-15:** the three intro movies (eabig, thx, intro_dj) play with sound by the level meter (peaks 3-24k throughout, `RECOMP_SKIP_INTRO=0 RECOMP_APU_LEVEL=1`; the meter now measures before RECOMP_MUTE). Needs a check by ear.
- [ ] Gate: a full race and the intro play with all expected sound, no gaps.

## Phase 5 — Visual completeness

- [x] Shadow wedge (board shadow projected over steep terrain) — 2026-10-15: not reproduced on the Vulkan renderer: 25 race frames in bursts over Snow Jam's first jump and Metro-City (tools\burst.ps1) show soft grey rider shadows and no black wedge (it was 2 in 8 frames on the software path). Reopen if seen again.
- [x] Pink-lit start area — confirmed against xemu (2026-10-15, `tools\xemu.ps1` snapshot `race_briefing`/`race_go`): real lighting, not a bug.
- [x] Character lighting (2026-10-15): riders were washed out; vertex colours oD0/oD1 are now clamped to 0..1 before interpolation like the NV2A. Select Character and race riders match xemu.
- [ ] Particles, snow spray, trails, motion blur, glow, reflections, water; every peak's look. **2026-10-15:** line strips (board/hand trails) and point sprites (snow spray) drawn on the GPU (were declined by the Vulkan backend: lost or drawn black); Intimidator compared with xemu (`intimidator_brief` snapshot).
- [ ] Optional: 720p/widescreen, higher internal resolution (only after correctness).

## Phase 6 — Full game coverage

Each item is "reached, works, no crash" on the GPU path at speed.

- [ ] Every peak (1–3) and course; Race, Freestyle, Slopestyle, Superpipe, Big Air, Backcountry. **2026-10-15:** every Race event on Peaks 2/3 runs (race_test -Peak 1/2, unlocked save fixture; one-on-one races have their own briefing screen). Freestyle events 1-3 on every peak run too (halfpipe, slopestyle, big air, the night event with fireworks); Launch Time's sunset-orange snow matches xemu (snapshot `launchtime_brief`). **2026-10-14:** Peak 1 races Snow Jam, Metro-City, Happiness and the first Freestyle event load and run at 60 FPS (p99 19-20 ms), screenshots checked; riders Zoe, Moby, Psymon.
- [ ] World Tour / Conquer the Mountain progression; unlocks; character select and customisation; shop. **2026-10-15:** Conquer the Mountain starts (character select, the helicopter-drop intro, free-roam on Peak 1 with the snowflake/money HUD), its pause menu (Return, Transport, Session, Messages, Audio, Options, Quit), Transport (peaks, All Mountain totals, peak goals, freeride drop points) and a teleport (gondola loading screen) all work, 0 bad calls (menu_test). Left: the lodge shop (ride into a station's lodge) and progression over many events.
- [ ] Single Event, Practice, multiplayer split-screen (2 pads). **2026-10-15:** Multi Play works: with two emulated pads (`RECOMP_USB_PADS=2`; now the default whenever two XInput controllers are plugged in at start) player 2 picks a rider, both confirm Bragging Rights, and Snow Jam runs split-screen (side by side), 0 bad calls (menu_test with `p2-` presses).
- [ ] Save / load (memory unit and hard disk paths under `UDATA`), options, controller settings, rumble. **Rumble 2026-10-15:** SSX 3 sends XID output reports as SET_REPORT on the control pipe (decaying left-motor pulses on landings); the toolkit's OHCI now forwards them (and interrupt-OUT reports) to XInput (`RECOMP_RUMBLE=0` off, `RECOMP_RUMBLE_TRACE=1` logs; scripted runs never rumble). Needs a check by hand on a real pad. **2026-10-15:** Save game writes `game\UDATA\4541003c\<id>\` (Data.ssx 39 KB, SaveMeta "PLAYER 1", SaveImage); Load game lists it ("50,000+ blocks free"). Save times were UTC; the toolkit's EEPROM settings now carry the host's time zone (GetTimeZoneInformation: bias, DST dates and biases, and the XC_MAX_OS user block SSX 3 reads) -- the save list shows local time. Every Options sub-screen (Game, Sound, Controller, HUD, Save/Load, Enter Cheat, Credits), Rider Details, Music, Equip Gear and Conquer the Mountain's intro movie open and close with no bad indirect calls (menu_test sweep).
- [ ] Credits, all movies, replays, pause menu, quitting back to menus repeatedly (resource leaks). **2026-10-15:** `tools\cycle_test.ps1 -Cycles N` (race -> pause -> Quit -> Yes -> title -> race, one session, driven by game_state's screen + screen state): 12/12 on Metro-City, no crash, no bad indirect calls. Pause menu: Return, Restart, Audio, Options, Quit (wraps); the race intro takes Start as "skip". Menus drop a press made while they slide in -- the scripts wait for the screen and retry.

## Phase 7 — Native Windows product

- [x] Build from a Windows checkout without WSL (2026-10-15): `scripts\setup.ps1` (toolkit clone with LF endings + patch, venv with capstone) and `scripts\regen.ps1` (~7 min; output identical to WSL's), then `tools\build.bat` (~17 min).
- [x] Game data location configurable (2026-10-15): `RECOMP_GAME_DIR`, else `game\` in the working directory, else next to the exe or one level up; a message box lists where it looked when `default.xbe` is missing.
- [x] Release build: one exe, no console, logs to `logs\`, crash dump on failure (2026-10-15: the exe is a GUI program; started by double-click it logs to `logs\ssx3_<time>_stderr.txt`; minidumps since 2026-10-15).
- [x] Controller and keyboard remapping; fullscreen toggle. **Remapping 2026-10-15:** `keys.ini` (`keys.example.ini`): every key, and the controller's buttons (`pad.<control>`), toolkit input layer. **2026-10-15:** window opens at 2x (fits the work area, RECOMP_WINDOW_SCALE), resizable; Alt+Enter / F11 borderless fullscreen (DXGI's exclusive Alt+Enter off); the D3D11 presenter draws the frame letterboxed to 4:3 at any size (GDI fallback too). Remapping still open.
- [x] Gate: fresh Windows machine → follow README → playing. (2026-10-15: fresh clone in C:\Code\Xbox\wintest -> setup.ps1 -> regen.ps1 -> build.bat -> race_test OK, Snow Jam at 60 FPS, 0 bad calls. Same machine, so VS/Vulkan SDK/Python were already installed.)

## Phase 8 — Hardening

- [ ] 2-hour automated soak, 20/20 boot→race, every Phase 6 item: 0 crashes, 0 hangs. **2026-10-15:** 2-hour soak passed -- `cycle_test -Cycles 120 -RaceSec 20` in one session: 120/120 race -> pause -> quit -> title -> race, 0 crashes, 0 hangs, 0 bad indirect calls, race 58.6-59.4 FPS in every 10-minute block (6 fence-wake rescues, 3 guest-CPU holds over 25 ms). 20/20 boot->race done earlier (Phase 1 gate); Phase 6 coverage still partial (Peaks 2/3 locked).
- [ ] Upstream the toolkit fixes in `patches/xboxrecomp-local.patch` where they are general.

---

## Risks and decisions

- **GPU path scope.** Phase 2 is weeks of work; it is the critical path for 60 FPS. The translators exist but were built for the HLE layer (`d3d8_*`) — expect adaptation, not drop-in.
- **CPU ceiling.** If the recompiled game cannot reach 16.7 ms even with free rendering, Phase 3 needs recompiler work; measure early (Phase 0 bench with rendering disabled gives the CPU floor).
- **Async correctness.** The idle wake is a workaround for D3D's NOP-patch race; a GPU backend with honest progress reporting may remove the need.
- **Determinism for debugging.** Keep `RECOMP_NV2A_ACK_THREAD=0` and the software rasteriser as references until the GPU path passes the gates.

## Progress log

- 2026-10-15 — Audio: waveOut fallback fixed like XAudio2; intro movies and races produce sound by the meter (muted runs measure too).
- 2026-10-15 — 2-player split-screen (Multi Play) works; a second XInput controller now enables it. Reliability batch race_par 4x3: 12/12.
- 2026-10-15 — Frame-rate check on every peak: 60 FPS with occasional single slow frames; Metro-City's 30 FPS stretch is the game's own (xemu drops to 30 at the same point).
- 2026-10-15 — Conquer the Mountain: free-roam, pause menu, Transport and teleport work. Race shadow wedge not reproduced on Vulkan (25 frames).
- 2026-10-15 — Phase 7 done: Windows-only build path (setup.ps1/regen.ps1, verified from a fresh clone), game folder found next to the exe, double-click logging, keys.ini remapping.
- 2026-10-15 — Freestyle on Peaks 1-3 (8 events) loads and runs, 0 bad calls; autonav takes any event type's briefing screen.
- 2026-10-15 — Peaks 2/3: all five races (Ruthless Ridge, Intimidator, Ruthless, Gravitude, The Throne) load and run with random riders, 0 crashes / bad calls. Lines and points now drawn on the GPU (they were dropped / came out black): board trails are white ribbons as in xemu, snow-spray point sprites (oPts size, gl_PointCoord on stage 3, xemu rules).
- 2026-10-15 — Faster, isolated test runs: RECOMP_AUTONAV (in-process menu driver, boot -> briefing ~27 s instead of ~40 s, re-arms per race; default in race_test/cycle_test) and RECOMP_SAVE_DIR + save fixtures (tests never write the player's saves; default fixture has everything unlocked).
- 2026-10-15 — xemu as a scripted reference: tools/xemu.ps1 + xemu skill (boot with the ISO, snapshots at character select / briefing / race start, button presses without focus, screenshots). Confirms the pink start area is real and the race riders match.
- 2026-10-15 — Character lighting matches xemu: vertex colours (oD0/oD1) are now clamped to 0..1 before interpolation, as on the NV2A. Lit riders were washed out (Griff's shirt pale cyan instead of deep blue).
- 2026-10-15 — 2-hour soak: 120/120 race/quit cycles in one session, no crash or hang, 58.6-59.4 FPS throughout.
- 2026-10-15 — Long-session slowdown fixed (60 -> ~20 FPS after ~5 min): two threads blocked while holding the guest CPU (unimpl-instruction warning, APU waiting for audio-queue room under its lock). 20-cycle soak at 59-60 FPS throughout.
- 2026-10-15 — Race/quit cycles: tools/cycle_test.ps1, 12/12. Fence-wake rescue at 20 ms (was 200).
- 2026-10-15 — Frontend sweep: every Options sub-screen, Rider Details, Music, Equip Gear, Conquer the Mountain intro; save and load work (hard disk).
- 2026-10-15 — Equip Gear fixed (its screen setup code was outside every function); unresolved jump targets now run as entries into their function (61 of 87 stubs). Options, races 8/8, no bad indirect calls.
- 2026-10-14 — Frontend screens identified (game_state.txt screen field); race_test -Rider/-Mode/-Event: Metro-City, Happiness and Freestyle verified at 60 FPS.
- 2026-10-14 — 32/32 boot→race at 8 parallel instances, no watchdog rescues: title-movie freeze closed. Phase 2 gate passed; D3D11-era items folded into the Vulkan status.
- 2026-10-14 — D3D11 vsync presentation is the default (GDI presented at ~59 Hz with tearing); 8 parallel instances 16/16 OK, no watchdog rescues.
- 2026-10-14 — Vertex programs on the GPU (2.0d): race at a steady 60 FPS (p99 20 ms), CPU 1.63 cores.
- 2026-10-14 — Frame timer steady (KeTickCount at 1 ms from QPC on its own thread; it was GetTickCount between executor passes): timer intervals 14-19 ms (were 3-30), race ~57.5 FPS p99 ~27 ms. Test runs muted (RECOMP_MUTE).
- 2026-10-14 — GPU ack thread sleeps between kickoff bursts (RECOMP_ACK_IDLE_US, default 2000): race CPU 2.92 → 2.15 cores, FPS unchanged (55.9 vs 53.7).
- 2026-10-14 — Phase 1 gate passed: 20/20 boot→race on Vulkan (race_par 4x5, 3.4 min); software renderer no longer gated.
- 2026-10-14 — Playtest fixes: Options menu crash (stub for a shared `pop esi; ret 8` epilogue never restored esi -- toolkit stub generator), audio crackle (output queue cushion, wait instead of drop), Vulkan cube maps.
- 2026-10-14 — Black race shapes FIXED (executor ARRAY_ELEMENT32, both renderers; found by a subagent on its own instance).
- 2026-10-14 — MR !3 (Corné's vulkan-race-perf) merged: two frames in flight, pre-decoded vertex programs, LensFX nowait; race 53-58 FPS.
- 2026-10-14 — Vulkan is the default renderer (6x2 batch 12/12).
- 2026-10-14 — Race 53-58 FPS on Vulkan: vblank/timers on the performance counter (the ~43 FPS ceiling was a ~43 Hz vblank).
- 2026-10-14 — Race 42-45 FPS (post-transform vertex cache).
- 2026-10-14 — Race 38-43 FPS on Vulkan (shadow-map textures updated in place).
- 2026-10-14 — Race 22 -> 34-36 FPS on Vulkan: trap waits by event, GPU work submitted in pieces, cached readback memory.
- 2026-10-14 — Vulkan: target = surface with the clip as scissor, only flipped surfaces drawn on the GPU; black race shapes shown to be shared with software (not fixed). race_test -RaceSec/-NoTaps/-Snap for one-command checks.
- 2026-10-14 — to_race.ps1 navigates from game state only; intro movies skipped by default (boot -> briefing ~25 s).
- 2026-10-14 — Vulkan renderer (MR !1, Corné) merged with MR !2 (APC guest-CPU fix); builds and runs on Windows with the Vulkan SDK: race 22-28 FPS vs 9-12 software.

- 2026-10-14 — Title freeze = guest-CPU starvation (unfair critical-section handoff at loop yields/kernel calls); fair handoff in the toolkit (RECOMP_FAIR_YIELD). race_par 8x4 29/32; [GUESTCPU] holder report added.
- 2026-10-14 — The "[no pad]" runs are a title-screen movie stream freeze (EA STRM ring), not USB; ring trace added. RECOMP_PRIO_LOCK=1 still worse (16/24 vs 20/24).
- 2026-10-14 — Watchdog in to_race.ps1 ([no pad] / [freeze] / [<state> stall]); race_par 8x2 in 4.6 min (was 22).
- 2026-10-14 — 43% stall FIXED (guest CPU kept across uncontended critical sections): race_par 8x3 = 18 OK, 0 load stalls, 6 title/no-pad (USB under load, new item).
- 2026-10-14 — Parallel test runs: tools/race_par.ps1 (N instances in work\i<k>); 2x1 trial OK in 1.5 min.
- 2026-10-14 — 43% stall traced to EA's STRM manager reading the next request at the old file position (skipped seek after a 'CEND'); [EAREAD]/[STRM] logging built, next: catch a stall with it (resume note in CLAUDE.md).
- 2026-10-14 — 43% stall = the first world-stream block decodes to a garbage asset header (reader retries forever); not pool exhaustion, not a thread race. Bank/pool/chunk wrappers added.
- 2026-10-14 — Async GPU freeze caught and worked around (fence-wake rescue watchdog); streamer stall traced to EA's STRM stream manager never delivering the world stream (suspected lost wake-up). race_test 8/10 (both failures streamer stalls).
- 2026-10-14 — Streamer: two-thread race ruled out; [STREAMDUMP] in thread dumps; "43%" split into streamer stall vs GPU freeze. race_test 6/6 then.
- 2026-10-14 — Phase 2.1 started: D3D11 device/swap chain presentation (opt-in), in-process screenshots.
- 2026-10-14 — Game state hook; soak/scripted race; streamer crash + 43% stall traced to one corrupted streamer object; async GPU freeze shown to be a BlockOnTime loop (idle wake reaches it).
- 2026-10-13 — Baseline measured: 9.9 FPS (software), CPU floor ≈ 10 ms/frame of game logic -> 60 FPS feasible with a GPU path.
- 2026-10-13 — Interrupt/DPC lock landed; race_test 4/6 (both failures being classified; the dump wait was too short to capture them).
- 2026-10-13 — Plan created. Baseline: races 9–12 FPS (async executor, software rasteriser), audio working (XAudio2 VP path), boot→race 5/6.
