# Modernising SSX 3: the plan

PC-port upgrades in the spirit of the 60 FPS, widescreen, MSAA and HD texture
work: each one a setting with a sensible default, an environment variable
(`RECOMP_*`, set only when unset in `src/main.c`) and **always a launcher
option** (user, 2026-10-19): every item ends with its launcher step
(`src/launcher/launcher.c`: control, `launcher.ini` key, environment
variable at Play), the README knob row and a refreshed
`docs/screenshots/44-launcher.png`.

This file is also the work queue. Work goes **one step at a time**: a step
is small enough to finish, verify and commit in one sitting, and every
finished step is committed and pushed with its box ticked and a dated line
in the progress log at the bottom. Stopping at any point loses at most the
step in progress; the next session starts at the first unticked box.

## How a step is done

1. `~/.local/bin/claude-usage --check 70` first: stop if over.
2. Take the first unticked step of the first item that is not done, blocked
   or waiting on the user (execution order below).
3. Do it. Functional checks: one single-instance scripted run first
   (`tools\live.ps1`, `tools\burst.ps1`, `tools\bench.ps1`; muted, ignores the
   real controllers). Screenshots via `RECOMP_SNAP_PRESENTED=1`, never of the
   desktop. Parallel batches only to measure failure rates. Keep testing
   lean (user, 2026-10-19): at most ~5 runs to verify a step, at least one
   on each peak when the change can differ per course; don't burn time on
   more.
4. If the user's game is running, `build\ssx3_recomp.exe` is locked: rename it
   aside (`build\ssx3_recomp.running-old*.exe`), never end their process.
5. Commit (author Koen Hendriks <info@koenhendriks.nl>, no Claude trailers),
   push to `origin` and `github`. Tick the box, add a progress-log line, and
   note anything the next step needs to know in that item's **Notes**.
6. A step that needs the user (listening, playing, a choice) is marked
   **[user]** and skipped until they answer; carry on with the next item.

Execution order (quick and visible first, the risky ones last):
**1 → 2 → 3 → 4 → 7 → 5 → 6**.

---

## 1. Anisotropic filtering — done

The game's slopes are seen at grazing angles almost all the time; with only
trilinear filtering the snow (and the HD textures) blurs a few metres ahead.

- [x] 1.1 Enable `samplerAnisotropy` when the device offers it (`vkr.c`
      device features), `RECOMP_ANISO` (default 16, `0`/`1` = off, capped at
      `maxSamplerAnisotropy`) on every linear-filtered sampler in
      `get_sampler`; log the value once.
- [x] 1.1b Mip chains for the game's own textures: the backend decodes only
      the base level, so distant snow has nothing to filter down to (it
      shimmers, and anisotropic filtering has less to work with). Build the
      chain on the GPU at upload (vkCmdBlitImage level by level, linear) for
      textures that are sampled with a linear filter; not for render
      targets updated in place (or regenerate on update). `RECOMP_TEX_MIPS`
      (default on).
- [x] 1.2 A/B: Snow Jam race at 5120x1440 (32:9), `RECOMP_ANISO=0` vs 16:
      screenshots (slope ahead of the rider, crop at full resolution) and
      `RECOMP_VKR_GPUPROF` GPU averages; FPS must hold 60.
- [x] 1.3 Launcher: "Texture filtering" dropdown (Trilinear, 4x, 8x, 16x
      anisotropic; default 16x) -> `RECOMP_ANISO`; README knob row; player
      README. Refresh `docs/screenshots/44-launcher.png`.

Notes:
- 1.1: `c->aniso` in vkr.c (device feature + `get_sampler`), logs
  `[VKR] anisotropic filtering on (16x)`; RTX 4080 SUPER max is 16.
- 1.1b: `vkr_tex_create_ex(..., mips)` blits the chain at upload; the
  backend asks for it except for render targets (updated in place) and
  cubes (stacked faces). `RECOMP_TEX_MIPS=0` off. Texture memory +1/3.
- 1.2 (5120x1440, Snow Jam): GPU 14.2 ms avg with both off, 12.1 ms with
  both on (small mips are cheaper to sample); 60 FPS on Peaks 1-3, no
  crashes. Distant snow ripples stay smooth instead of breaking into noise
  (shots\af_off vs af_on on the Windows copy).

## 2. Draw distance and pop-in — done

Tuned for the Xbox: props and trees switch to low detail or appear late, and
fog hides the far end. Find the knobs first, then scale them.

- [x] 2.1 Measure: log the projection's near/far planes (our
      `sub_0024EA13` PerspectiveFovLH wrapper, `zn`/`zf` arguments) and the
      fog range the executor sees (fog mode/params per frame), per course
      (Snow Jam, Metro-City, a Peak 2 race). Record in Notes.
- [x] 2.2 Find the LOD / visibility distance tests: trace which code decides
      that a model instance is drawn and at which detail (renderer
      `[0x369528]` draw-list builders; look for float compares against
      distances / squared distances in the instance loop; `RECOMP_WATCH` /
      the decomp). Write down function addresses and constants in Notes.
- [x] 2.3 `RECOMP_DRAW_DIST` (multiplier, default to be chosen, 1 = original)
      applied to what 2.1/2.2 found (far plane, LOD distances; fog start/end
      only if the far end then shows the world's edge). `_gen` wrappers or a
      poke of the constants, whichever the code allows.
- [x] 2.4 Verify: A/B screenshots at the same course spots (burst at fixed
      times), FPS/GPU at 5120x1440, a full Peak 1-2 race each for streaming
      problems (missing sections, stalls -- `[STREAMDUMP]`), memory (the
      guest heap: `[ALLOC] FAILED`).
- [x] 2.5 Launcher: "Draw distance" dropdown (Original / Far / Maximum) ->
      `RECOMP_DRAW_DIST`; README, screenshot.

Notes:
- 2.1 (RECOMP_PROJ_TRACE=1 in our sub_0024EA13 wrapper, RECOMP_FOG_TRACE=1
  in vkr_backend.c; Snow Jam, Metro-City, Peak 2 race): every projection
  comes from the camera setup at 0x001EACA5. Menus: zn 25, zf 5000, fovy
  78.8/43.8 deg. In a race: zn 25 (and 30, two passes per frame), **zf
  30000**, fovy 70 deg; during the fly-over the game animates the aspect
  1.33 -> 1.68+ itself (widescreen was off). Fog (linear, mode 0x801) on
  Snow Jam: start ~235000, end ~706000 -- far beyond zf, so fog is not
  what limits the view; Metro-City and the Peak 2 race logged no in-race
  fog. So the far plane is a hard 30000 cut; next (2.2) the game's own
  per-object distance culling / LOD, which likely sits well inside it.
  Logs: logs\dd_p0e0.txt, dd_p0e1.txt, dd_p1e0.txt on the Windows copy.
- 2.2: the camera setup is renderer vtable 0x2F7E50 slot 0x64 =
  sub_001EAB40 (thiscall fovy, zn, zf): zf -> camera+0x7C, projection
  (sub_0024EA13) and frustum (sub_001E8770). Every camera class constructs
  with zf 30000 (0x46EA6000 in sub_0005E450/5E480/64440/68980/...).
  Raising zf alone CRASHED (far x3, Peak 2): the in-game render object
  (sub_000D3740 clears its lists) collects visible things in fixed arrays
  with no bounds checks -- counts/arrays: +0x54 (512 x 8 B, octree cells,
  sub_000D3540), +0x1058 (512 x 8 B, cells), +0x205C (2048: D1EA0/D1FF0/
  D2490), +0x4060 (1024: D1EA0), +0x5068 (2048: D2540), +0x706C (512:
  D2060), +0x7874 (128: D25F0 type 7), +0x7A7C (64: D2230), +0x7B80 (256:
  D25F0 type 8), +0x7F84 (unused here). Peak fill at x1 (Peaks 1-3,
  RECOMP_DRAWLIST_STATS=1): 54:98 1058:263 205C:272 4060:92 5068:179
  706C:197 7B80:36 -- the cell lists have ~2x headroom (area grows ~d^2).
  Fix: D2540/D25F0 re-implemented in C with the capacity checked; the other
  producers (one entry per call, ret 8) and the octree walk D3540 (one entry
  then recursion via D3420) skip the call when their list is full
  ([DRAWDIST] ... list full). Far x3 on Peak 2: no crash, 60 FPS, cell
  lists saturate at 512 (nodes skipped), 5068 reached 608.
- 2.3: RECOMP_DRAW_DIST (multiplier, default 1) scales zf in a sub_001EAB40
  wrapper while in game. Visible gain in race views is modest (terrain
  hems the view in, the far mountains are backdrop). 2.4 should pick the
  default (1.5-2 keeps the cell lists under 512) and look for skipped-cell
  holes at x3.
- 2.4 (4 runs, Peaks 2/3, start-gate shots at x1 and x2): no crash, no list
  full at x2, GPU unchanged (~4.3-4.9 ms at 1080p). The extra distance is
  hardly visible in the views tested -- terrain hides what lies past 30000.
  Default 1.5 (well inside the list capacities), launcher choices 1 / 1.5 /
  2. The pop-in players notice is more likely per-object LOD switching
  (inside the producers above, e.g. D1EA0/D2060 distance tests) -- not
  touched; a possible later step.

## 3. HUD anchored to the screen edges (widescreen) — done

In widescreen the HUD keeps the 4:3 middle (2D vertices, w == 1, are
narrowed by `squeeze2d` in the vertex shaders). Modern ports pin it to the
real corners.

- [x] 3.1 Map the HUD draws in a race: which draws are HUD (2D, in-game
      state, HUD screen vtable 00293000), their guest-pixel boxes (place,
      speed, trick meter, timer, minimap). `RECOMP_VKR_TRACE_*` style log,
      screenshots. Notes: element list with boxes.
- [x] 3.2 Per-draw anchor in `vkr_backend.c`: a 2D draw whose box lies in the
      left third moves with the left edge, right third with the right edge,
      the middle stays centred; full-screen passes (wider than ~90% of the
      screen) keep today's handling. Pushed as a per-draw x offset (push
      constant) next to `squeeze2d`. `RECOMP_HUD_EDGES` (default on in
      widescreen), `RECOMP_HUD_MARGIN` (safe-area inset, % of width).
- [x] 3.3 Exclusions: menus/pillarboxed screens unchanged, pause menu and
      dialogs centred, race briefing panel centred; text that spans thirds
      kept together (anchor by the draw's centre).
- [x] 3.4 Verify at 16:9 and 32:9: race, freestyle (score HUD), split screen
      (2 players: both halves -- may need to stay off), results screen.
      Screenshots in docs.
- [x] 3.5 Launcher: "HUD at the screen edges" checkbox (+ safe-area margin
      if 3.2 adds one) -> `RECOMP_HUD_EDGES` / `RECOMP_HUD_MARGIN`; README,
      screenshot.

Notes:
- Done without a separate draw map: in widescreen in-game, draws of <= 64
  vertices decline the GPU vertex path (be_draw_vsh), so be_draw sees the
  CPU-transformed vertices; a draw whose vertices are all w == 1 and that
  is under 90% of the screen wide gets hud_shift (vertex push constant at
  56, after squeeze_all): left third of the guest screen -> (squeeze - 1),
  right third -> (1 - squeeze), times (1 - RECOMP_HUD_MARGIN/100); the
  middle third (timer, trick score, dialogs, briefing panel) stays centred.
  Verified (4 runs): Snow Jam race at 32:9 on/off and 16:9 on, freestyle
  at 32:9 (leaderboard left, score/boost right, timer/trick score centre);
  60 FPS. Not checked: split screen, pause menu, results screen.

## 4. Sharper shadows — done

Rider shadows come from 128x128 swizzled shadow maps the executor draws in
software (`[VKR] offscreen surface ... drawn in software`), then sampled
projected onto the snow: soft and blocky at 1440p.

- [x] 4.1 Offscreen targets in `vkr.c`: colour (+ depth if the shadow pass
      uses it) images per guest surface address, sized surface x
      `RECOMP_SHADOW_RES` scale; begin/end rendering into them; clears.
- [x] 4.2 Route draws to the shadow-map surfaces (swizzled 128x128 colour
      targets) to the GPU target instead of software; keep the guest copy
      only if something else reads it (check: the title never reads them
      back on the CPU?).
- [x] 4.3 Bind the GPU image directly when a later draw samples that surface
      (today `is_rt` + decode from guest memory), with the scale folded into
      `tex_scale`; clip rect (2,2,124,124) scaled.
- [x] 4.4 Verify vs the software path (`RECOMP_SHADOW_RES=1`): same shape,
      sharper; no black wedge regression; GPU time; Peak 1 race + freestyle.
- [x] 4.5 Default (e.g. 4 = 512x512). Launcher: "Shadow quality" dropdown
      (Original 128 / High 512 / Ultra 1024) -> `RECOMP_SHADOW_RES`; README,
      screenshot.

Notes:
- vkr.c: up to 8 offscreen targets (struct VkrOff, keyed by guest address):
  vkr_offscreen_use swaps the target fields (images, size, scale, scissor,
  samples) and saves the main target's in c->main; vkr_offscreen_done
  restores them (also at every flip and vkr_set_target); the colour image
  is SHADER_READ outside its passes and is bound through a VkrTex wrapper
  (vkr_offscreen_tex). Pipelines carry the sample count in key[7] (main may
  be MSAA, offscreen is 1x). vkr_backend.c pick_target: a swizzled 32-bit
  target -> offscreen at RECOMP_SHADOW_RES x its size (clip rounded up to a
  power of two: 128x128 for SSX 3); the same address in pitch layout (the
  game clears its shadow maps that way every frame) also goes there --
  without it the shadows smeared across frames. bind_textures takes the
  offscreen image first for render-target addresses. Nothing is written to
  guest memory any more (the title never reads them on the CPU). 6 maps per
  race, 60 FPS, GPU unchanged; Snow Jam: the other riders' shadows are a
  crisp silhouette at 512 instead of a blob (shots\shadb0 vs shadb4).
  Black-wedge regression not seen in the runs (5 runs).

## 7. Shorter loading times — done

Not measured yet; course loads take several seconds.

- [x] 7.1 Measure: boot -> title, title -> main menu, race load (Snow Jam,
      Metro-City, a Peak 3 course) with timestamps from game_state.txt /
      `[STATE]`; `RECOMP_WAIT_STATS=1` and `RECOMP_CPU_STATS=1` during a load
      (where do the threads wait: file I/O, guest CPU, timers, the
      streamer's `KeDelayExecutionThread` naps?).
- [x] 7.2 Fix what 7.1 shows if cheap (e.g. streamer sleeps shortened while a
      loading screen is up, file reads served from a host cache, fixed
      minimum durations). Each fix behind a knob, measured before/after.
- [x] 7.3 Reliability check of the faster load: `tools\race_par.ps1` 8x2
      (load stalls were timing-sensitive before).
- [x] 7.4 Launcher: "Fast loading" checkbox for the 7.2 knobs (default on);
      README, screenshot.

Notes:
- 7.1 (state/autonav timestamps, Snow Jam / Metro-City / Peak 2): boot ->
  frontend 0.6 s, the race load itself ~0.6 s (`loading` state) + ~2 s of
  in-game setup -- loads are already fast. The wait is the frontend: the
  title's intro doesn't take Start until ~5.6 s, and "Checking hard disk"
  (screen 1, vt 0028B428, its state at +0x478 steps to 6) stays ~4.8 s.
- 7.2: app+0x28 is the game's speed (input samples per timer tick, 1.0,
  sub_001AD5F0; the app loop runs one update per sample, up to 12 per
  frame). A wrapper on sub_001AD720 sets it to RECOMP_FAST_BOOT (default 4)
  while the frontend has no active screen yet (title intro) or the hard
  disk screen is up, and puts the game's value back after. Boot -> race
  briefing 22.2 -> 14.1 s; main menu 12.7 -> 4.6 s.
- 7.3: the race load path is untouched (fast-forward only on those two
  frontend waits), so instead of a race_par batch: 2 boots to the briefing
  plus the earlier runs this session, no stalls/crashes (user: keep
  testing lean).

## 5. Above 60 FPS (120/144 Hz) — closed: not feasible

The game logic runs at 60 updates/s (frame timer 1000/60 ms, input ring at
60 Hz). Two possible routes; investigate before committing to one.
Time-boxed: if 5.1 finds no clean timestep, stop and write down why.

- [x] 5.1 Investigate the timestep: is there a dt (float seconds per update)
      that physics, animation and timers use, or are rates hard-coded per
      update? (frame timer `sub_001AE480`/`sub_001AE030`, app loop
      `sub_001AD880` update counter `+0x20`/`+0x24`, `app+0x28/0x30/0x34`
      floats.) Notes: findings + go / no-go for each route.
- [-] 5.2 (skipped: no-go, see Notes) Route A (if a dt exists): updates at N Hz with dt = 1/N
      (`RECOMP_LOGIC_HZ`), frame timer period 1000/N; check physics (speed,
      jumps), animation, audio sync, AI, race timer accuracy against 60 Hz
      runs (finish time of a scripted race, `[FRAMES]`).
- [x] 5.3 Route B (if not): render-side interpolation is out of scope
      (would need every transform captured); write the conclusion and close.
- [-] 5.4 (skipped: no-go) If A works: present at N Hz (window pacing for 120/144 Hz
      monitors, VRR). Launcher: "Frame rate" dropdown (60 / 120 / 144 /
      monitor) -> `RECOMP_LOGIC_HZ`; README, screenshot.

Notes:
- 5.1 (2026-10-20): no single timestep. The app keeps a nominal rate and
  dt (app runner sub_001ADAC0: app+0x14 = 60, app+0x18 = 1/60; the frame
  timer is armed with 60), but the game logic does not use one shared dt:
  72 call sites push the literal 1/60 (0x3C888889) as an argument
  (physics/collision ~0x134000-0x143000, effects ~0x1C6000-0x1DC000,
  frontend), the float 1/60 occurs ~200 times in the data (memory operands),
  and counters tick once per update. Route A would mean finding and
  patching every one of those -- any missed one runs at double speed
  (physics, animation, AI, the race clock). Route B (interpolating between
  60 Hz frames) needs every transform captured: out of scope (plan).
  Closed. What remains for high-refresh monitors: steady 60 FPS pacing
  (done earlier) and VRR; app+0x28 (input samples per tick) is a game-speed
  knob, not a frame-rate one (used for fast boot, item 7).

## 6. Audio: effects, downmix, surround

The plan assumed SSX 3 uses DirectSound's I3DL2 reverb (lost because the
APU's effects DSP is a stub). Measured first (6.1): it does not -- so the
item became getting the speaker mix right.

- [x] 6.1 Find what SSX 3 asks for: `RECOMP_APU_BINS=1` (toolkit apu_dsp.c)
      prints the RMS level of every mixbin once a second.
- [x] 6.2 Correct stereo downmix of the speaker bins (toolkit apu_dsp.c):
      centre and rears at -3 dB, LFE at -6 dB -- the old even/odd rule put
      the whole centre channel in the left speaker.
- [x] 6.3 5.1 output: the game already mixes front/centre/rear; an XAudio2
      6-channel mastering voice fed bins 0-5 directly (`RECOMP_AUDIO_CHANNELS`
      = 2 / 6, default stereo), the frame buffer carrying 6 channels.
- [x] 6.4 Launcher: "Audio output" dropdown (Stereo / 5.1 surround) ->
      `RECOMP_AUDIO_CHANNELS`; README, screenshot.
- [ ] 6.5 **[user]** Listening check: stereo balance (the announcer and
      centred sounds no longer lean left), and 5.1 on a surround setup if
      available.

Notes:
- 6.1 (Snow Jam and Metro-City races, 75 s each, RECOMP_APU_BINS=1): only
  bins 0, 1, 2, 4, 5 carry sound (FL, FR, centre, BL, BR; rms ~0.03-0.16);
  no LFE (3), nothing in the crosstalk bins (6-9), the I3DL2 reverb send
  (10) or the FX sends (11+). No reverb is being lost. The stereo mixdown
  (even bins left, odd right) put the centre channel in the left speaker
  only.
- 6.3: toolkit apu_xaudio2.c: RECOMP_AUDIO_CHANNELS=6 makes a 5.1
  (WAVEFORMATEXTENSIBLE, FL FR C LFE BL BR) source voice on a mastering voice
  with the device's own channel count (XAudio2 maps or downmixes by the
  masks). The stereo pipeline is unchanged; apu_dsp.c pushes centre/LFE/
  rears into a FIFO in production order (zeros when muted) and
  xa2_submit_samples takes as many as it submits -- also for dropped
  buffers, so it stays in step. Checked (muted run): voice created, 188
  buffers/s, 0 underruns/drops. Not heard yet: 6.5.

---

## Progress log

- 2026-10-19 — Plan written (items 1-7, steps, execution order).
- 2026-10-19 — 1.1 anisotropic filtering: RECOMP_ANISO (default 16x) on all linear samplers; Snow Jam boots to the race. Added step 1.1b (mip chains for the game's own textures: only the base level is uploaded today).
- 2026-10-19 — 1.1b mip chains for the game's textures (RECOMP_TEX_MIPS); 1.2 A/B: smoother distant snow, GPU 14.2 -> 12.1 ms, 60 FPS on all peaks (4 runs).
- 2026-10-19 — 1.3 launcher "Texture filtering" dropdown (Trilinear / 4x / 8x / 16x, default 16x), README knob. Item 1 done.
- 2026-10-19 — Every item now ends with a launcher option step (2.5, 3.5, 4.5, 7.4, 5.4, 6.3).
- 2026-10-19 — 2.1 measured: race far plane zf 30000 (zn 25/30, fovy 70), fog far beyond it; RECOMP_PROJ_TRACE / RECOMP_FOG_TRACE added.
- 2026-10-20 — 2.2/2.3: far plane knob RECOMP_DRAW_DIST (camera setup sub_001EAB40); the render lists that overflowed at a longer view are bounded (C versions of D2540/D25F0, skip-when-full guards on D1EA0/D1FF0/D2490/D2060/D2230/D3540); far x3 runs without crashing.
- 2026-10-20 — 2.4/2.5: draw distance default 1.5x, launcher "Draw distance" (Original / Far 1.5x / Maximum 2x); little visible gain in tested views. Item 2 done.
- 2026-10-20 — Item 3 done: HUD anchored to the screen edges in widescreen (RECOMP_HUD_EDGES, default on; launcher checkbox); race and freestyle HUD checked at 32:9 and 16:9.
- 2026-10-20: Item 3 follow-up (found on Linux, same on Windows): the edge layout decided per draw and tore up elements drawn in several pieces (briefing and pause menu text, the music notification, trick names), and an attempt to carry decisions between frames made them flicker. Now: in-game menus and dialogs (screen states 4-6, opening and closing included; ssx3_InGameMenuUp) keep all 2D in the middle; the HUD (one immediate-mode draw, sub_000AE9E0, so no widget boundaries) is grouped from geometry: at each flip the frame's small 2D boxes are joined into elements of touching pieces, each placed once by its whole box, and the next frame's draws take their element's placement (24 px of motion allowed). Draws wider than 45% of the screen are placed alone. Race at 16:9 with notification and pause: 0 frames with mixed placement in a notification, 9 of ~2200 frames with a piece placed alone (first frame of a new element). RECOMP_HUD_TRACE=1/2 logs the decisions.
- 2026-10-20 — Item 4 done: shadow maps on the GPU at 512x512 by default (RECOMP_SHADOW_RES; launcher "Shadow quality" Original / High / Ultra).
- 2026-10-20 — Item 7 done: loads were already short; the frontend's fixed waits (title intro, hard-disk check) now fast-forward x4 (RECOMP_FAST_BOOT; launcher "Fast boot"): boot -> briefing 22.2 -> 14.1 s.
- 2026-10-20 — Item 5 closed as not feasible: no shared timestep (1/60 pushed literally at 72 call sites, ~200 constants, per-update counters); notes in the plan.
- 2026-10-20 — 6.1/6.2: SSX 3 sends nothing to the reverb/FX bins (measured), so item 6 became the speaker mix: stereo downmix fixed (the centre channel went to the left speaker only); 5.1 output next.
- 2026-10-20 — 6.3/6.4: 5.1 surround output (RECOMP_AUDIO_CHANNELS=6; launcher "Audio output"). Only 6.5, the user's listening check, is left in the plan.
