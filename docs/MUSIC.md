# SSX 3's interactive music

How the soundtrack moves between segments, what the `music.inf` settings
do, and what the loop files are. Findings from the game's code (this
recompilation), run-time traces (`RECOMP_MUSIC_TRACE=1`) and the PAL
game's data; `tools/ssx3_music.py` dumps any song. Each claim says where
it comes from: **code** (read in the disassembly), **trace** (seen in a
run), **data** (true of all shipped files) or **inferred**.

## The files

| File | What it is |
|---|---|
| `data/config/music.inf` | per song: titles, file names, tempo, levels (below) |
| `data/config/playlist.inf` | the playlist (`SONG = "<section name>"`) |
| `data/audio/music.big`, `music2.big` | BIGF archives with the songs (`SONGBIG` = 1 or 2) |
| `<song>.mpf` | the Pathfinder map: segments, branches, events (`PATHDATA`) |
| `<song>.mus` | the song audio as EA `SCHl` stream blocks, 32 kHz stereo EA-XA (`MUSDATA`) |
| `<song>loops0.mus` | an EA sound bank (`BNKl`, v5), 22.05 kHz mono EA-XA (`LOOPDATA`) |

EA's Pathfinder engine (version 4 maps, `PFDx`, little-endian on Xbox)
plays the map; it is statically linked into the game (load
`sub_00189490`, interpreter `sub_0018C340`).

## The map: segments, branches, a control value

**Segments are one measure each (data).** Every licensed song is cut into
slices of exactly `BeatsPerMeasure` (4) beats at its `BPM`; the sample table
gives each slice's length in ms (e.g. Emerge: 4.00 beats at 135 BPM,
421 times). Deep End is cut the same way, its `BPM` is written at half
tempo (92 for 184). Menu and ambient tracks (`charsel`, `Peak1`,
`Peak1Amb`, ...) are not on a beat grid.

**Nodes and branches (data + trace).** The map is a list of nodes. An audio
node plays one slice; a junction node plays nothing. When a node ends, the
engine takes the first branch whose range contains the current **control
value** (0-127):

```
  24 junction                -> 26 [0..100], 58 [100..127]
  26 track 1 sample 132      -> 27 [0..100], 59 [100..127]
```

Ranges in the shipped songs: 0-127 (always), 0-50 / 50-100 / 100-127,
0-100 / 100-127, and "exactly 0" / 1-127. So one section of a song is a
chain of slices with side exits; the value decides where a chain leaves.

**The control value (code + trace).** The game sets it with
`sub_0018A8C0(0x11000001, value)` from its music director. In a race it is
a ramp: `value = 127 * t / T`, `t` counting game updates since the last
reset, `T` = 800, 1000 or 1200 updates (about 13, 17 or 20 s; which one
depends on a per-player count, `sub_0010A590`: up to 3, 4-7, 8 or more). It
resets to 0 when the race loads and on certain rider events (seen several
times a minute; from `sub_00111F40` with a 0-1 strength classed at 0.25 /
0.65, and from `sub_00113320`; **inferred**: landings / impacts). So a
song drifts from its "0-50" material to its "100-127" material over ~13-20 s
and drops back after such an event.

## Events: how the game steers a song

**Firing (code + trace).** The game sends numbered events
(`sub_0018A6E0`, via the music director's `sub_0010D8A0`); one equal to the
last one sent is ignored. Seen in races and freestyle events:

| Event | When (trace) |
|---|---|
| 0 | the game starts (title), and an event's start after the briefing |
| 1 | the main menu; in a race also "entered music zone 1" (below) |
| 36 | an event loads |
| 1, 2, 9, ... | course music zones (below) |
| 10 | the run ends (race finish, freestyle run over) |

**Course music zones (code + trace).** Courses carry music triggers. On
entering one the game fires event *N* (the zone's number), on leaving it
*N+1* (`sub_0010F370`: messages 2 and 1; other messages pass their number
straight through, a few (0x0B, 0x0D, 0x0E-0x12, 0x2A) with extra
conditions). Snow Jam fired 1 (~90 s), 2 (~140 s), 9 (~220 s) and 10 at the
finish.

**What an event does (data, decoded).** Each event is a list of actions;
`tools/ssx3_music.py song <name> --events` prints them:

| Action | Meaning |
|---|---|
| go to node *n* | jump (track 1 = the song, track 2 = the loop bank) |
| store position in register *r* | remember where the song is (`0x0a`, value `000r ffdf`) |
| return to register *r* | jump back there (goto `0xFFF0 - r`: 0xFFEF = register 1) |
| wait *ms* | delay the next action |
| fade over *ms* to *v* | volume fade (value: ms in the high 16 bits, level 0-127 low) |
| stop | goto `0x01000000` |

Deep End, typical of the race songs:

```
   0: go to node 0; store position in registers 1..5     (start: reset)
   1: store position in register 1; go to node 374       (enter zone 1)
   2: return to register 1                               (leave zone 1)
   5: store position in register 2; go to node 392       (enter zone 5)
   6: return to register 2
  10: go to node 370                                     (finish)
  19: fade over 3000 ms to 0; wait 3100 ms; stop
```

So a zone is a **call and return**: entering stores the song's position
and jumps into the zone's section; leaving returns to where the song was.

## Why a modded song gets stuck or transitions badly

From the above, the usual causes:

1. **No event, no change.** An event that has no actions in the map does
   nothing; the song keeps walking its branches. Every event number the
   courses fire (enter *N*, leave *N+1*, start 0, finish 10, load 36, ...)
   needs actions in a modded map, or the music ignores that moment.
2. **A zone section that loops on itself** keeps playing until the *leave*
   event. If the leave event has no "return to register", or the section
   was entered without "store position", the song never comes back to its
   main part.
3. **Branch ranges that do not cover 0-127.** A node whose ranges leave a
   gap (e.g. only 45-127) has no way on when the value is in the gap: the
   chain ends there.
4. **Slices off the beat grid.** Transitions happen at slice ends, so every
   slice should be a whole measure (`BeatsPerMeasure` beats at `BPM`); a
   slice cut short or long throws every following transition off the beat.
   `check` flags songs whose slices do not match their `BPM` (shipped
   example: Freeze, 3.33 beats at BPM 85 = really ~102 BPM).
5. **The control value is a ramp**: material reachable only at 100-127
   shows up ~13-20 s after a reset, and a rider event sends the song back
   to its 0-50 material. Ranges that need a high value for a long time will
   rarely be reached.

## music.inf settings

Defaults from the constructor (`sub_00102F40`), use from the code:

| Setting | Default | What it does in SSX 3 |
|---|---|---|
| `PATHDATA`, `MUSDATA` | | the map and the song audio |
| `LOOPDATA` | | the loop bank(s); several lines allowed, one is picked at random (`sub_00103120`) |
| `SONGBIG` | 1 | 1 = `music.big`, 2 = `music2.big` |
| `BPM` | 120 | beat length = 60000 / BPM ms (`sub_00103210`). Used live to time things to the next beat (`sub_00104630`); must match the audio |
| `BeatsPerMeasure` | 4 | beats per slice; bar length = beat x `BeatsPerMeasure` x `MeasuresPerBar` (`sub_00103240`) |
| `MeasuresPerBar` | 2 | (bar length, above) |
| `PhrasesPerBank` | 4 | only read by a beat-aligned random loop-phrase picker (`sub_00103140`: phrase start = `rand % (PhrasesPerBank - 1) x PhraseAlign`) whose only entry (`sub_00104E50`) nothing calls: **no effect in retail SSX 3** (code) |
| `PhraseAlign` | 16 | same picker: no effect in retail |
| `BeatsPerPhrase` | 8 | **not read anywhere** (only parsed) |
| `Pathlevel`, `Asynclevel` | 100 | song / loop volume in % |
| `DUCKTOLOOPS` | 1 | whether the song ducks for the loops (below) |
| `DelayCount`, `DelayTime`, `DelayFeedback`, `DelayLevel` | 0, 100, 90, 50 | echo effect on the song (`sub_001032E0`) |
| `LOWPASS` | 65535 | low-pass filter on the stream |
| `CATEGORY` | 0 | preferred event kinds (Race 0, SlopeStyle 1, BigAir 2, HalfPipe 3, BackCountry 4) |
| `SEDVALUE`, `PREVIEW`, `ADDTOFE`, `TITLE`, `ARTIST`, `ALBUM` | | DJ id, preview, front-end listing, credits |

Practical values for a new song: `BPM` = the audio's real tempo,
`BeatsPerMeasure` = 4, every map slice exactly one measure, the rest as
the shipped songs (`MeasuresPerBar 2, PhrasesPerBank 4, BeatsPerPhrase 16`).

## The loop file ("airloop")

**What it is (data).** `LOOPDATA` is an EA sound bank of one-beat sounds
plus two longer ones: 16, 32, 48, 56 or 64 sounds of exactly 1 beat (Deep
End: 0.5 beat at its half-tempo BPM), then two stingers of 4-9 beats. The
map's **track 2** uses them: each track-2 sample is 4 bank sounds (one
measure), and the map strings them into loops:

```
 490 junction            -> 492 [0..45], 500 [45..93], 508 [93..127]   (loop entry)
 492..499  loop A: 4 measures, twice   -> 491 (end)
 500..507  loop B                       (ranges 45..127)
 508..515  loop C                       (ranges 93..127)
 516 junction            -> 518 [0..71], 519 [71..127]               (stinger)
```

**When it plays (trace + code).** Not in the air: the loop player is a
second Pathfinder player ("overlay", `0x11000002`) switched on while the
song is ducked. Seen: opening the pause menu turns it on
(`sub_00104850`: song stream down, overlay on) and resuming turns it off;
the same switch is used by the movie player and a few other in-game
states. Its own control value (`sub_0018B720(0x11000002, v)`, seen 59-90
in a race) picks loop A, B or C. Events like Deep End's 33 / 34 / 38
("stop; track 2 go to node 516; wait 1200 ms; go to node X") play a
stinger between the song stopping and restarting.

**Importing one.** A new loop bank needs: `BNKl` version 5, sounds of
exactly one beat at the song's BPM (22.05 kHz mono EA-XA in the shipped
files), a multiple of 16 of them plus the two stingers, and a map whose
track 2 points at them in groups of four (sample-table entries
`bank << 16 | first sound`, plus the length in ms). The map and the bank
change together: a bank with more or fewer sounds needs the track-2 nodes
and sample entries to match.

## Tools

```
python3 tools/ssx3_music.py <SSX3 folder> list
python3 tools/ssx3_music.py <SSX3 folder> song "Deep" --events --nodes
python3 tools/ssx3_music.py <SSX3 folder> check
```

Run-time tracing: `RECOMP_MUSIC_TRACE=1` logs every Pathfinder call the
game makes (`[MUSIC]` lines at debug level: events with their call
chains, the control values, the loop overlay switching).

Formats: [vgmstream](https://github.com/vgmstream/vgmstream)'s
`ea_schl_map_mpf_mus.c` (MPF v4 layout), [MPFmaster](https://github.com/xan1242/MPFmaster)
(Pathfinder v5 tooling).
