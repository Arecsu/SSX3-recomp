/* Levelled logging (docs/LOGGING.md).
 *
 *   log_msg(LOG_INFO, "PLAY", "event start: %s", name);
 *
 * Lines go to stderr -- the session log -- as
 *   HH:MM:SS.mmm +SSSS.s LEVEL [CAT] message
 * RECOMP_LOG_LEVEL=trace|debug|info|warn|error|critical (default info) sets
 * what reaches the file. When the log pump runs (main.c, log_pump_attach),
 * lines down to DEBUG go to it anyway: it filters, and keeps what it drops
 * for the flight recorder. */
#ifndef SSX3_LOG_H
#define SSX3_LOG_H

#ifdef __cplusplus
extern "C" {
#endif

enum { LOG_TRACE, LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERROR, LOG_CRITICAL };

void log_msg(int level, const char *cat, const char *fmt, ...)
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((format(printf, 3, 4)))
#endif
    ;

int log_level(void);                 /* the threshold (RECOMP_LOG_LEVEL) */
int log_enabled(int level);          /* would log_msg at this level be kept? */
const char *log_level_name(int level);
int log_parse_level(const char *s, int dflt);
double log_uptime(void);             /* seconds since the log started */
/* "HH:MM:SS.mmm +SSSS.s " for a line written now (out: >= 32 bytes) */
void log_stamp(char *out, unsigned n);
/* main.c, once stderr is the session file: start the pump (1 if running)
 * and drain it before the process ends (crash handler, exits). */
int log_pump_start(void);
void log_drain(void);
/* lines seen at WARN / ERROR / CRITICAL and how the session ended (from the
 * [EXIT] / window closed / [CRASH] lines), for the summary */
void log_session_counts(unsigned *warn, unsigned *err, unsigned *crit, const char **how);
/* the last INFO [PLAY] lines, written as indented lines (a crash report) */
void log_recent_play(void);

#ifdef __cplusplus
}
#endif

#endif
