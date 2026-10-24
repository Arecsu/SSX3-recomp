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
- [x] **A2** Pump filter (main.c): tag -> level table for existing lines,
      level threshold, timestamps added to untagged lines, flight-recorder
      ring flushed on ERROR/CRITICAL. Linux: the same through a pipe (or
      in-process when stderr is not a file).
- [x] **A3** Noise: `[STATE]` sub-state flips (60% of a session log) and
      the boot-time `[KERNEL]`/`[CS]`/`[HEAP]`/`[PATH]` detail graded to
      DEBUG/TRACE; check a 20-minute session at `info` stays short.
- [x] **A4** Log files: keep the last 20 sessions in `logs\` (delete
      older, crash dumps too), name stays `ssx3_<date-time>_stderr.txt`;
      a `latest.txt` copy/pointer for "send me your log".
- [x] **A5** Launcher: "Log detail" dropdown (Errors only / Warnings /
      Normal / Detailed / Everything) saved in launcher.ini, sets
      `RECOMP_LOG_LEVEL`; "Open logs" opens the folder with the newest
      file selected.

### B. The session story (`INFO [PLAY]` unless noted)
- [x] **B1** Session header (`[SYSTEM]`, `[SETTINGS]`): build version (git
      commit + date), Windows/Linux version, CPU, RAM, GPU name, driver
      and Vulkan version, monitor size and refresh, window/fullscreen,
      game folder and the XBE's title id/version, every launcher setting
      and every `RECOMP_*` in effect, controllers at start.
- [x] **B2** Top-level flow: boot, intro, title, frontend, loading,
      in game, results, replay -- one line per change with time spent in
      the previous one (sub-states only at DEBUG).
- [x] **B3** Menu screens by name (main menu, Select Character, Setup
      Character, Select Peak/Mode/Event, My Rules, Options and its pages,
      Lodge and its pages, pause menu, Quit dialog, ...) from the screen
      tracker (sub_00202460), unknown ones as `screen <vt>:<id>`.
- [x] **B4** Game mode at the start of play: Single Event, Conquer the
      Mountain, Freeride, Multiplayer (and the debug quick-start menu).
- [x] **B5** Event start: peak, kind (Race, Slopestyle, Big Air, Super
      Pipe, ...), course name, rider, opponents (needs finding where the
      game keeps the selected event; fall back to the world file loaded).
- [x] **B6** Event end: finishing place / score / medal, time, restarted
      or quit (pause menu -> Restart/Quit).
- [x] **B7** Saves and loads (`[SAVE]`): game saved / loaded / failed,
      slot and profile name, from UDATA file activity.
- [x] **B8** Money and purchases: cash changes with the screen they
      happened on (a drop on Buy Attributes / Buy Gear = a purchase, with
      the amount); the money cheat key logged as such.
- [x] **B9** Lodge and stations: entering a lodge, station prompts
      (lodge / transport), MCOMM Transport destination.
- [x] **B10** Session end: how it ended (window closed, quit to
      dashboard, crash), duration, events played, summary of warnings.

### C. Things that help when something went wrong
- [x] **C1** Mark key: a key (F12 / a controller combination) writes
      `INFO [PLAY] *** player mark ***` with the current screen/event and
      saves a snapshot of the shown frame next to the log -- "I saw it
      here".
- [x] **C2** Performance (`[PERF]`): per event average FPS, 1% low, worst
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
- 2026-10-24: A2 -- the pump moved to src/log.c (Windows and POSIX), grades lines by tag, timestamps them, keeps a 2000-line flight recorder written out before ERROR/CRITICAL, collapses repeats. A scripted race at info: 6 lines plus the flight recorder; RECOMP_TEST_CRASH: the crash block CRITICAL with its lead-up. Found on the way: `[VKR] upload buffer full` ~900 times while a race loads in scripted runs (none in the user's session) -- draws dropped; to look into separately.
- 2026-10-24: A3 -- the user's 20-minute session log (3,482 lines) graded with the table: 0 lines at info (everything was STATE sub-flips, kernel, file and renderer detail). [BLOCK-RESCUE] down to DEBUG, a full [DRAWDIST] list up to WARN.
- 2026-10-24: A4 -- logs\ keeps the last 20 session logs and 10 crash dumps, latest.txt names the current one, crash dumps go to the session's logs folder (they went to build\logs). Found: started from the launcher (no console) the pump never ran -- it checked GetStdHandle, which stays empty when stderr is freopen'ed; now the CRT's stderr handle. Played sessions had synchronous log writes until now.
- 2026-10-24: A5 -- "Log detail" in both launchers (Errors only / Warnings and errors / Normal / Detailed / Everything, default Normal), saved as log_level, sets RECOMP_LOG_LEVEL; "Open logs" opens the folder with this session's file selected (latest.txt). The SDL launcher change is not compiled here (no SDL headers in WSL).
- 2026-10-24: B1 -- src/journal.c: build (commit + date: cmake/build_info.cmake, from git or the BUILD_INFO sync-windows.sh writes), OS, CPU, RAM, monitor, the XBE's name/title id/version, the settings in words (two lines), every RECOMP_* at DEBUG; the GPU line ([VKR] device, now with the driver version) at INFO. Controllers at start: with C4.
- 2026-10-24: B2 -- game_state.c: one INFO [PLAY] line per top-level state (starting up, intro movies, menus, entering an event, loading, in game, debug menu, leaving the event) with the time spent in the one before; [STATE] sub-flips DEBUG. Briefing/race/results/replay: by screen (B3).
- 2026-10-24: B3 -- screen_note (ssx3_overrides.c, before and after each screen state change): INFO [PLAY] "screen: <name>" -- menus by id (title ... Credits, lodge 39), in game by vtable only (ids there are garbage): briefings, pause, quit dialog, lodge/station prompt, run result 002984B0, event results 00298378; unknown ones as "in-game screen <vt> (not named yet)" so sessions collect them.
- 2026-10-24: B4 -- "game mode: Single Event / Conquer the Mountain / Multi Play / Previews" from the main menu's list (+0x95, 4 rows) when the main menu closes (state 6; the next screen reuses its memory). The list is found among those sub_00205D40 has set up, by its parent being a child of the main menu. Checked with menu_test: down,a = Conquer; down,down,a = Previews (Multi Play is skipped without 2 pads); a = Single Event. The debug quick-start menu shows as its own state (B2).
- 2026-10-24: B5 -- game_state.c: on entering in game, "event: Peak N, <kind>, <course>" from the event number at 0x346440 (17 events: 5 races, 3 slopestyle, 3 big air, 3 super pipe, 3 peak runs); 17 = "free ride (no event)". Rider and opponents not logged yet (where the game keeps them is not found).
- 2026-10-24: B7 -- toolkit hook xbox_file_hook (kernel_file.c, every NtCreateFile with its access and status); journal.c logs Data.ssx writes "game saved", reads "save data read", failed writes WARN. The game opens the file relative to the save folder handle, so the path is just the name; it also reads the save just before overwriting it (read + saved = a save). Checked: lodge -> Save Game -> overwrite Yes.
- 2026-10-24: B8 -- player 1's cash (0x3474B4 + (slot*10 + rider) * 0xF88, profile record [0x346400]*32 + 0x345948) checked after each frontend update: "spent 250 (money 200000 -> 199750, on Buy Attributes)"; the money key: "money key: +200000, now 200000". Screens named on the way: Buy Attributes, dialog, name keyboard, message box; the title only by its vtable (id 0 is reused by dialogs).
- 2026-10-24: B6 -- when the event results screen comes up, player 1's result as the screen's setup (sub_000A4620) reads it: "event result: place 6 of 6, time 4:00.17" (race; time in 1/60 s), "place N of 6, score S, gold medal" (freestyle), won/lost for the two-rider challenges, "did not finish", race rounds 1-2 of 3, platinum. Leaving an event without results: "left Snow Jam without a result"; the pause menu's Quit passes a state of its own (0029AD64, "quitting the event"); the same event entered again without the menus in between: "event restarted". Checked: Super Pipe and Snow Jam runs (score/time), cycle_test 2 quits. Restart itself not driven by a script yet. Screen 00298448 = "race end".
- 2026-10-24: B9 -- station gates (sub_000D5A60: +0x10 state 0 at the gate, 1 prompt up, 2 answered, 3 said no; +0x14 kind 0 lodge; +0x18 station id, 0x17 = Green Base Station) and the in-game screen opener (sub_000C4C20 type 0x1F lodge prompt, 0x21 transport): "at the lodge of Green Base Station: enter? (prompt)", "said no to the lodge of ...", Yes shows as leaving the event + "screen: lodge". Checked with a debug start: Yes, Return to Game, No. Only station 0x17 has a name; the transport prompt and its destination are not checked (no scripted route to a transport gate). Also: cash picked up in game is no longer one INFO line per coin -- DEBUG per change, one "picked up N on the mountain" line on leaving the run.
- 2026-10-24: B10 -- main.c session_end (the toolkit's exits through xbox_before_exit, and the crash report): drains the pump, then journal_session_end writes "session ended: window closed / the game ended itself (...) / crash, after H:MM:SS; N events started, M with a result" and "this log has W warnings, E errors, C critical" (WARN when any). The pump counts lines per level and notes the [EXIT] / window closed / [CRASH] line (both now INFO / CRITICAL). A process killed from outside (Task Manager, live.ps1 stop) has no summary. live.ps1 close ends a run as a player does. Checked: window close, RECOMP_TEST_CRASH. log.h/journal.h now included on every platform (they were Windows-only while the pump calls are not).
- 2026-10-24: C1 -- src/mark.c: F12, or both thumbsticks clicked together on any controller, writes "INFO [MARK] *** player mark N (F12) *** <state / event>; <screen>; snapshot logs\mark_<time>_N.bmp" and saves what the window shows (new toolkit xbox_FramebufferSnapshot, split out of the snapshot trigger; SDL and web too). Its own host thread (50 ms), so it works while the game hangs; RECOMP_MARK=0 off. The pump writes the flight recorder before a [MARK] line (the detail of the seconds before). logs\ keeps the newest 30 marks. Checked: F12 on the title (640x480 snapshot in a scripted run). The controller combination is not testable in scripted runs (they ignore the machine's pads).
- 2026-10-24: C2 -- src/perf.c, fed by vkr_backend.c be_flip at every presented frame: per event (game_state.c starts it on entering in game, reports on leaving) "INFO [PERF] Snow Jam: 60.0 FPS average, 1% low 52.6 FPS, worst frame 23 ms (2116 frames, 35 s)"; a frame over 100 ms in game: WARN with the event and screen (one line a second, the rest counted); the last minute at DEBUG. An event's first 2 s are left out (the first frame after a load took 160 ms every time). GPU time is not in it: the timestamps exist only with RECOMP_VKR_GPUPROF (which logs its own [GPUPROF] lines). Software renderer (RECOMP_GPU=sw): no [PERF].
