/*
 * Performance in the session log (docs/LOGGING.md C2), [PERF]:
 *   - per event (in game, from the event start until it is left): average
 *     FPS, 1% low, worst frame -- INFO when the event is left;
 *   - a frame over 100 ms in game: WARN with where it happened (at most one
 *     line a second; the rest counted into the next);
 *   - once a minute: the last minute at DEBUG.
 * Fed by the renderer at every presented frame (ssx3_PerfFlip, vkr_backend.c
 * be_flip); the state thread (game_state.c) asks for the event's numbers
 * (ssx3_PerfEvent), handled at the next frame on the renderer's thread.
 */
#include "log.h"
#ifdef _WIN32
#include <windows.h>
#else
#include "platform/win32_compat.h"
#endif
#include <stdio.h>
#include <string.h>
#include <stdint.h>

extern uint32_t xbox_TickCountMs(void);
extern void ssx3_WhereNow(char *out, size_t n);       /* game_state.c */
extern const char *ssx3_ScreenNow(void);              /* ssx3_overrides.c */
extern int ssx3_InGameNow(void);                      /* game_state.c */

#define BUCKETS 1000                    /* 0.25 ms each: up to 250 ms */
#define HITCH_MS 100.0
#define SETTLE_MS 2000.0                /* an event's first frames still load */

typedef struct {
    unsigned frames, hist[BUCKETS + 1];
    double total_ms, worst_ms;
} Span;

static Span s_event, s_minute;
static char s_event_name[64];
static double s_event_t0;
static volatile int s_req_start, s_req_report;   /* handled at the next frame */
static char s_req_name[64];

static double now_ms(void)
{
#ifdef _WIN32
    static LARGE_INTEGER f;
    LARGE_INTEGER c;
    if (!f.QuadPart)
        QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
#else
    return (double)xbox_TickCountMs();
#endif
}

static void span_add(Span *s, double dt)
{
    int b = (int)(dt * 4.0);
    s->frames++;
    s->total_ms += dt;
    if (dt > s->worst_ms)
        s->worst_ms = dt;
    s->hist[b < 0 ? 0 : b > BUCKETS ? BUCKETS : b]++;
}

/* the frame time 99% of the frames stay under */
static double span_p99(const Span *s)
{
    unsigned want = s->frames - s->frames / 100, have = 0;
    int b;
    for (b = 0; b <= BUCKETS; b++)
        if ((have += s->hist[b]) >= want)
            return b < BUCKETS ? (b + 1) / 4.0 : s->worst_ms;
    return s->worst_ms;
}

static void span_say(int level, const char *what, const Span *s)
{
    if (!s->frames || s->total_ms <= 0)
        return;
    log_msg(level, "PERF", "%s: %.1f FPS average, 1%% low %.1f FPS, worst frame %.0f ms (%u frames, %.0f s)",
            what, s->frames * 1000.0 / s->total_ms, 1000.0 / span_p99(s), s->worst_ms, s->frames,
            s->total_ms / 1000.0);
}

void ssx3_PerfEvent(const char *name)
{
    if (name) {
        snprintf(s_req_name, sizeof s_req_name, "%s", name);
        s_req_start = 1;
    } else {
        s_req_report = 1;
    }
}

void ssx3_PerfFlip(void)
{
    static double last, minute_t, hitch_t;
    static unsigned hitches_unsaid;
    double t = now_ms(), dt = last ? t - last : 0;
    last = t;
    if (s_req_report || s_req_start) {
        if (s_req_report) {
            s_req_report = 0;
            if (s_event_name[0])
                span_say(LOG_INFO, s_event_name, &s_event);
            memset(&s_event, 0, sizeof s_event);
            s_event_name[0] = 0;
        }
        if (s_req_start) {
            s_req_start = 0;
            memset(&s_event, 0, sizeof s_event);
            snprintf(s_event_name, sizeof s_event_name, "%s", s_req_name);
            s_event_t0 = t;
        }
        return;                         /* the frame across the change does not count */
    }
    if (dt <= 0)
        return;
    span_add(&s_minute, dt);
    if (s_event_name[0] && t - s_event_t0 < SETTLE_MS)
        return;
    if (s_event_name[0])
        span_add(&s_event, dt);
    if (dt >= HITCH_MS && ssx3_InGameNow()) {
        if (t - hitch_t >= 1000.0) {
            char where[160];
            const char *scr = ssx3_ScreenNow();
            ssx3_WhereNow(where, sizeof where);
            if (strcmp(scr, "in game"))
                snprintf(where + strlen(where), sizeof where - strlen(where), ", %s", scr);
            if (hitches_unsaid)
                log_msg(LOG_WARN, "PERF", "frame took %.0f ms (%s); %u more since the last such line",
                        dt, where, hitches_unsaid);
            else
                log_msg(LOG_WARN, "PERF", "frame took %.0f ms (%s)", dt, where);
            hitch_t = t;
            hitches_unsaid = 0;
        } else {
            hitches_unsaid++;
        }
    }
    if (!minute_t)
        minute_t = t;
    if (t - minute_t >= 60000.0) {
        span_say(LOG_DEBUG, "last minute", &s_minute);
        memset(&s_minute, 0, sizeof s_minute);
        minute_t = t;
    }
}

/* the session ends (journal_session_end) in an event: its numbers so far */
void ssx3_PerfSessionEnd(void)
{
    if (s_event_name[0] && s_event.frames) {
        char what[96];
        snprintf(what, sizeof what, "%s (until the session ended)", s_event_name);
        span_say(LOG_INFO, what, &s_event);
    }
}
