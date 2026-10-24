/* The session story in the log (docs/LOGGING.md, section B): INFO lines a
 * person can read after a play session -- the build and machine, the
 * settings, and what the player did. */
#ifndef SSX3_JOURNAL_H
#define SSX3_JOURNAL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* B1: build, system, game files and settings; once default.xbe is loaded
 * and the RECOMP_* defaults are in place. */
void journal_session_header(const uint8_t *xbe, size_t xbe_size, const char *game_dir);
/* B10: how the session ended, how long it ran, events played, warnings
 * and errors seen; from the exits (xbox_before_exit) and the crash report. */
void journal_session_end(void);
/* C8: for a crash report -- where the game was and the last [PLAY] lines,
 * as indented lines of the report. */
void journal_crash_context(void);

#ifdef __cplusplus
}
#endif

#endif
