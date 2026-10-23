# Logging: plan and tracker

Goal: a log a person can read after a play session -- what the player did,
on which settings, and what went wrong -- with levels, so a normal session
writes a short story and a bug hunt can turn everything back on. Work
queue for the logging loop: one item per commit, first unticked box next;
tick it (and add a dated line to the log at the bottom) in the commit that
lands it.

## Design

**Levels** (lowest to highest): `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`,
`CRITICAL`. `RECOMP_LOG_LEVEL=trace|debug|info|warn|error|critical`
(default `info`); the launcher's "Log detail" dropdown sets it.

**Line format**: `HH:MM:SS.mmm +SSSS.s LEVEL [CAT] message` -- wall clock,
seconds since start, level, category (`PLAY`, `SETTINGS`, `SYSTEM`, `GFX`,
`AUDIO`, `INPUT`, `SAVE`, `PERF`, `CRASH`, or a diagnostic's own tag).

**Two sources, one filter.** New code logs through `log_msg(level, cat,
fmt, ...)` (src/log.c). The ~840 existing `fprintf(stderr, "[TAG] ...")`
lines (game code and toolkit) stay as they are: the log pump (main.c,
which already moves stderr to the file) grades each untagged line by its
`[TAG]` from a table (`[KERNEL]`, `[CS]`, `[PATH]`, `[FILE]` -> TRACE;
`[STATE]`, `[VKR] pipeline`, `[HUD-FLICKER]` -> DEBUG; `[GATHER]`,
`[DRAWDIST] ... full` -> WARN; `[CRASH]` -> CRITICAL; unknown -> DEBUG)
and drops what is below the level.

**Flight recorder.** Lines below the level are not lost: the pump keeps the
last ~2000 in memory and writes them out (marked as such) when an `ERROR`
or `CRITICAL` line arrives, so a crash at `info` still comes with the
detail that led up to it.

## Work items

### A. The logging core
- [x] **A1** `src/log.c/.h`: levels, `log_msg()`, `RECOMP_LOG_LEVEL`, line
      format with timestamps; usable from game code, overrides and src/vk.
- [ ] **A2** Pump filter (main.c): tag -> level table for existing lines,
      level threshold, timestamps added to untagged lines, flight-recorder
      ring flushed on ERROR/CRITICAL. Linux: the same through a pipe (or
      in-process when stderr is not a file).
- [ ] **A3** Noise: `[STATE]` sub-state flips (60% of a session log) and
      the boot-time `[KERNEL]`/`[CS]`/`[HEAP]`/`[PATH]` detail graded to
      DEBUG/TRACE; check a 20-minute session at `info` stays short.
- [ ] **A4** Log files: keep the last 20 sessions in `logs\` (delete
      older, crash dumps too), name stays `ssx3_<date-time>_stderr.txt`;
      a `latest.txt` copy/pointer for "send me your log".
- [ ] **A5** Launcher: "Log detail" dropdown (Errors only / Warnings /
      Normal / Detailed / Everything) saved in launcher.ini, sets
      `RECOMP_LOG_LEVEL`; "Open logs" opens the folder with the newest
      file selected.

### B. The session story (`INFO [PLAY]` unless noted)
- [ ] **B1** Session header (`[SYSTEM]`, `[SETTINGS]`): build version (git
      commit + date), Windows/Linux version, CPU, RAM, GPU name, driver
      and Vulkan version, monitor size and refresh, window/fullscreen,
      game folder and the XBE's title id/version, every launcher setting
      and every `RECOMP_*` in effect, controllers at start.
- [ ] **B2** Top-level flow: boot, intro, title, frontend, loading,
      in game, results, replay -- one line per change with time spent in
      the previous one (sub-states only at DEBUG).
- [ ] **B3** Menu screens by name (main menu, Select Character, Setup
      Character, Select Peak/Mode/Event, My Rules, Options and its pages,
      Lodge and its pages, pause menu, Quit dialog, ...) from the screen
      tracker (sub_00202460), unknown ones as `screen <vt>:<id>`.
- [ ] **B4** Game mode at the start of play: Single Event, Conquer the
      Mountain, Freeride, Multiplayer (and the debug quick-start menu).
- [ ] **B5** Event start: peak, kind (Race, Slopestyle, Big Air, Super
      Pipe, ...), course name, rider, opponents (needs finding where the
      game keeps the selected event; fall back to the world file loaded).
- [ ] **B6** Event end: finishing place / score / medal, time, restarted
      or quit (pause menu -> Restart/Quit).
- [ ] **B7** Saves and loads (`[SAVE]`): game saved / loaded / failed,
      slot and profile name, from UDATA file activity.
- [ ] **B8** Money and purchases: cash changes with the screen they
      happened on (a drop on Buy Attributes / Buy Gear = a purchase, with
      the amount); the money cheat key logged as such.
- [ ] **B9** Lodge and stations: entering a lodge, station prompts
      (lodge / transport), MCOMM Transport destination.
- [ ] **B10** Session end: how it ended (window closed, quit to
      dashboard, crash), duration, events played, summary of warnings.

### C. Things that help when something went wrong
- [ ] **C1** Mark key: a key (F12 / a controller combination) writes
      `INFO [PLAY] *** player mark ***` with the current screen/event and
      saves a snapshot of the shown frame next to the log -- "I saw it
      here".
- [ ] **C2** Performance (`[PERF]`): per event average FPS, 1% low, worst
      frame and GPU time; frames over 100 ms as WARN with what was on
      screen; a once-a-minute summary at DEBUG.
- [ ] **C3** Window and display: resizes, fullscreen toggles, focus lost /
      regained, aspect changes, internal resolution rebuilds.
- [ ] **C4** Input: controller connected / disconnected / battery low,
      keyboard in use.
- [ ] **C5** Audio: output device and channels, underruns and drops as
      WARN (rate-limited).
- [ ] **C6** Graphics: Vulkan device lost / errors as ERROR/CRITICAL,
      pipeline build failures, HD textures found / missing, draw
      distance trimming (DEBUG; a full render list WARN).
- [ ] **C7** Loading: world files loaded and load time per event; missing
      or unreadable game files as ERROR with the path.
- [ ] **C8** Crash report: the CRITICAL block (fault, guest and native
      stacks, minidump path) plus the current screen/event, the last
      `[PLAY]` lines and the flight recorder.
- [ ] **C9** Existing diagnostics graded: `[GATHER]`, `[DRAWDIST]`,
      `[BLOCK-RESCUE]`, `[BLOCK-STUCK]`, `[HUD-FLICKER]`, `[GLITCH]`,
      `[FPS30]`, `[HDTEX]`, `[VKR]` ... each with a sensible level.

### D. Finish
- [ ] **D1** docs: this file's design section kept current; the player
      README explains the "Log detail" option, the mark key and which
      file to send.
- [ ] **D2** Test: scripted runs at each level (a race, a freestyle, the
      lodge via the debug menu), a forced crash (`RECOMP_TEST_CRASH`),
      check the `info` log reads as the story and stays short.

## Progress log
- 2026-10-24: plan written.
- 2026-10-24: A1 -- src/log.c/.h (levels, log_msg, RECOMP_LOG_LEVEL, timestamped lines); main.c's first line uses it.
