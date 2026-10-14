# SSX 3 native — roadmap

**Goal:** SSX 3 runs natively on Windows, **≥ 60 FPS on the GPU**, with
**working audio**, the **whole game playable** and **no crashes**.

This file is the plan *and* the tracker: tick a box in the same commit that
lands the work, and add a dated line to the [log](#progress-log) for every
milestone change. Gates are measured, not judged by eye — each phase says
which test proves it.

**Where we are (2026-10-13):** playable races at 9–12 FPS on the software
rasteriser (asynchronous GPU executor), audio through the emulated APU,
keyboard/XInput input, boot→race reliability ~5/6. See README and CLAUDE.md.

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
- [x] Game state hook (`src/game_state.c`): the game's own state machine published as `[STATE]` lines and `game_state.txt` (`tools/game_state.ps1`); top-level states named. Next: map the in-race sub-states and switch the scripts from draw counts to it.
- [ ] `tools/race_test.ps1` extended: all peaks/events (open), configurable run count (done), summary table; failures auto-dump with a 20 s write window (done) and are classified from the last screen -- `[title: no input]`, `[menu hang]`, `[load stall]`, `[other]`, `CRASH` (done).
- [x] Screenshot suite: `tools/shots.ps1` saves every distinct menu screen (by draw count), the briefing and 4 race shots into `logs/shots_<ts>[_label]/`; first software-path reference set: `logs/shots_20261013-235549_software` (16 shots). Per-peak race spots come with the all-peaks navigator.
- [x] Baseline numbers recorded here (2026-10-13, default build, Snow Jam race, `tools/bench.ps1 -Seconds 90`):
  - **Software rasteriser, async executor:** 9.9 FPS avg, p50 101 ms, p99 267 ms, 0 crashes (`logs/bench_20261013-232858.json`).
  - **CPU floor** (`RECOMP_RASTER_SKIP=1`: everything but the pixels): 10–35 FPS in the race. Profile: the main thread waits on the GPU most of the time -- D3D fence waits (`KeWaitForSingleObject`, 54% of samples) and polling a GPU visibility-test result (`sub_0022DE70` = D3D query GetData returning D3DERR_TESTINCOMPLETE, 24%); real game logic is ~19% of samples, **≈ 10 ms per frame** -- under the 16.7 ms budget. The executor's time is mostly CPU vertex-program interpretation (`nv2a_vsh_run`), then software-method round trips and the pushbuffer survey's `note()` (pure overhead).
  - Conclusion: 60 FPS is reachable on the CPU side once vertex programs, pixels and query results come from a GPU; Phase 2 is the right critical path.

## Phase 1 — Stability on the current path

Fix the known failures before the renderer changes so regressions stay visible.

- [ ] **43% race-load stall** (~1 in 6): world streamer loses a request (resource 0/40 stuck in state 8). Job queues ruled out (CLAUDE.md). Next: trace the streamer's own request state (`sub_0020DB60` object +0xAC/+0xC0/+0xC8), compare a good and a stalled run.
- [ ] Loader-worker crash in world streaming (intermittent; seen at `0x0020D26A` and `sub_0020CAB0` with a garbage chunk index) -- same streamer object as the 43% stall: one corruption bug (CLAUDE.md, "WORLD STREAMER CORRUPTION"). **2026-10-14:** the two-thread race on the streamer is ruled out (all entries wrapped, 16 runs, no overlap); thread dumps now carry `[STREAMDUMP]` (request list, slot records, resource table, fence wait). Two failure classes look alike at "43%": streamer stall (loading screen keeps drawing) vs async GPU freeze (draws stop, main thread in BlockOnTime).
- [ ] Any remaining async-GPU hang (map-select/rules class): soak-test the idle wake; replace it with exact behaviour if a better model of D3D's NOP patching emerges.
- [x] ISRs and DPCs run under the guest-CPU lock (single-CPU semantics; `RECOMP_IRQ_LOCK=0` to disable). They used to run on host threads in parallel with guest threads; the USB driver's enumeration then stalled in about 1 boot in 6 (no pad on the title screen). After: 6/6 runs enumerated fully.
- [ ] Guest-thread priority scheduling in the guest lock (Xbox is single-CPU, strict priority) — only if Phase 1 bugs point at ordering.
- [ ] Gate: 20/20 boot→race on both GPU modes.

## Phase 2 — GPU renderer (D3D11), the big one

Approach: keep the executor's pushbuffer walk and state tracking
(`nv2a_pb_exec.c`, already accurate) and replace the software rasteriser with
D3D11 draws. Reuse the toolkit's translators: NV2A vertex-program microcode →
HLSL (`d3d8_vsh_parse` / `d3d8_vsh_generate_hlsl`) and register combiners →
HLSL pixel shaders (`d3d8_combiners.c`). The software rasteriser stays as the
reference (`RECOMP_GPU=0`) for differential testing.

- [ ] 2.1 Device and presentation: D3D11 device + swap chain in the game window; flips present the front surface; vsync-paced at 60 Hz. **Done (opt-in `RECOMP_D3D_PRESENT=1`, toolkit `src/video/gpu_present.c`):** device + DISCARD swap chain on the window, each flipped frame uploaded to the back buffer and presented with vsync (`RECOMP_VSYNC=0` off). Screenshots now come from inside the process (`RECOMP_SNAP_TRIGGER`, used by `live.ps1 snap`), since PrintWindow cannot read a swap chain. Left: make it the default after a visual check; share the device with the renderer (2.2+).
- [ ] 2.2 Surfaces: colour/depth render targets as D3D11 textures keyed by guest address and format, including **swizzled RTs** (rider shadow maps) and clear rects; Z24S8/Z16 depth, stencil.
- [ ] 2.3 Textures: upload from guest memory (swizzled, linear, DXT1/3/5, palettised, cube maps), cached by address + content hash with invalidation on CPU writes; render-target-as-texture without a round trip; sampler state (filter, address modes incl. border colour).
- [ ] 2.4 Geometry: vertex attributes (all NV2A types incl. stride 0, packed normals, immediate/inline arrays) into dynamic vertex/index buffers; primitive types incl. quads/polygons; near-plane clipping by the GPU.
- [ ] 2.5 Vertex programs: microcode → HLSL with a cache keyed by program hash; the 192 constants as a constant buffer; fixed-function T&L path for non-program batches.
- [ ] 2.6 Pixel pipeline: combiners → HLSL (cache by combiner state), texture stage modes (2D/3D/cube/projective, clip planes, bump/dot later), alpha test, fog, blend equations/factors incl. constant colour, colour mask, depth/stencil ops.
- [ ] 2.7 CPU read-back: surfaces the title reads (screenshots, lock of an RT) copied back to guest memory on demand only.
- [ ] 2.8 Differential test: per-frame compare GPU vs software output on the screenshot suite; fix until within tolerance.
- [ ] 2.9 Performance: state-change batching, shader/PSO caches, no per-draw stalls; target executor ≤ 4 ms/frame.
- [ ] Gate: races render correctly on the GPU; frame rate then limited by the guest CPU, not rendering.

## Phase 3 — CPU side to 60 FPS

With rendering off the CPU, the game itself must fit in 16.7 ms.

- [ ] Profile guest time per frame (sampling profiler + `tools/profile_tally.py`); list the top recompiled functions and kernel calls.
- [ ] Remove waits: GPU hand-off, guest-lock contention, loop-yield cost, timer/DPC latency; fence waits answered as soon as the GPU reaches them.
- [ ] Recompiler-level wins: x87 emulation hot paths, memory access helpers, indirect-call dispatch, `RECOMP_LOOP_YIELD` granularity.
- [ ] Frame pacing: the title's 60 Hz clock (vblank, input ring) matched to the host display; no drift at 60.
- [ ] Gate: bench p99 ≤ 16.7 ms on every peak.

## Phase 4 — Audio, complete

- [ ] Verify by ear: music (EA Radio), speech, menu SFX, race SFX, 3D voices (`RECOMP_APU_LEVEL=1` shows 48 kHz and real levels today).
- [ ] waveOut fallback path gets the same VP fix as XAudio2.
- [ ] GP/EP DSP: real effects (reverb, mixdown) — DSP56300 emulation or HLE of the XDK effect images; replaces the doorbell ack.
- [ ] A/V sync at 60 FPS, no underruns under load; volume/pan/3D positioning correct.
- [ ] Intro/cutscene movies with sound.
- [ ] Gate: a full race and the intro play with all expected sound, no gaps.

## Phase 5 — Visual completeness

- [ ] Shadow wedge (board shadow projected over steep terrain) — resolve on the GPU path (likely matches hardware once depth/clip are exact).
- [ ] Pink-lit start area and the stage-1 texture holding unrelated bytes — confirm against xemu or real footage.
- [ ] Particles, snow spray, trails, motion blur, glow, reflections, water; every peak's look.
- [ ] Optional: 720p/widescreen, higher internal resolution (only after correctness).

## Phase 6 — Full game coverage

Each item is "reached, works, no crash" on the GPU path at speed.

- [ ] Every peak (1–3) and course; Race, Freestyle, Slopestyle, Superpipe, Big Air, Backcountry.
- [ ] World Tour / Conquer the Mountain progression; unlocks; character select and customisation; shop.
- [ ] Single Event, Practice, multiplayer split-screen (2 pads).
- [ ] Save / load (memory unit and hard disk paths under `UDATA`), options, controller settings, rumble.
- [ ] Credits, all movies, replays, pause menu, quitting back to menus repeatedly (resource leaks).

## Phase 7 — Native Windows product

- [ ] Build from a Windows checkout without WSL (Python pipeline + CMake on Windows; scripts in PowerShell or Python).
- [ ] Game data location configurable (`game\` next to the exe or a config file); clear message when the rip is missing.
- [ ] Release build: one exe, no console, logs to `logs\`, crash dump on failure.
- [ ] Controller and keyboard remapping; fullscreen toggle.
- [ ] Gate: fresh Windows machine → follow README → playing.

## Phase 8 — Hardening

- [ ] 2-hour automated soak, 20/20 boot→race, every Phase 6 item: 0 crashes, 0 hangs.
- [ ] Upstream the toolkit fixes in `patches/xboxrecomp-local.patch` where they are general.

---

## Risks and decisions

- **GPU path scope.** Phase 2 is weeks of work; it is the critical path for 60 FPS. The translators exist but were built for the HLE layer (`d3d8_*`) — expect adaptation, not drop-in.
- **CPU ceiling.** If the recompiled game cannot reach 16.7 ms even with free rendering, Phase 3 needs recompiler work; measure early (Phase 0 bench with rendering disabled gives the CPU floor).
- **Async correctness.** The idle wake is a workaround for D3D's NOP-patch race; a GPU backend with honest progress reporting may remove the need.
- **Determinism for debugging.** Keep `RECOMP_NV2A_ACK_THREAD=0` and the software rasteriser as references until the GPU path passes the gates.

## Progress log

- 2026-10-14 — Streamer: two-thread race ruled out; [STREAMDUMP] in thread dumps; "43%" split into streamer stall vs GPU freeze. race_test 6/6 then.
- 2026-10-14 — Phase 2.1 started: D3D11 device/swap chain presentation (opt-in), in-process screenshots.
- 2026-10-14 — Game state hook; soak/scripted race; streamer crash + 43% stall traced to one corrupted streamer object; async GPU freeze shown to be a BlockOnTime loop (idle wake reaches it).
- 2026-10-13 — Baseline measured: 9.9 FPS (software), CPU floor ≈ 10 ms/frame of game logic -> 60 FPS feasible with a GPU path.
- 2026-10-13 — Interrupt/DPC lock landed; race_test 4/6 (both failures being classified; the dump wait was too short to capture them).
- 2026-10-13 — Plan created. Baseline: races 9–12 FPS (async executor, software rasteriser), audio working (XAudio2 VP path), boot→race 5/6.
