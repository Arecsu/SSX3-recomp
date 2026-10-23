/* Levelled logging: see log.h and docs/LOGGING.md. */
#include "log.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#include <sys/time.h>
#endif

static int s_level = -1;
static int s_pump;                   /* a pump filters: send down to DEBUG */

static const char *const k_names[] = {"TRACE", "DEBUG", "INFO", "WARN", "ERROR", "CRIT"};

const char *log_level_name(int level)
{
    return level >= LOG_TRACE && level <= LOG_CRITICAL ? k_names[level] : "?";
}

int log_parse_level(const char *s, int dflt)
{
    static const struct { const char *name; int level; } k[] = {
        {"trace", LOG_TRACE}, {"everything", LOG_TRACE}, {"debug", LOG_DEBUG},
        {"detailed", LOG_DEBUG}, {"info", LOG_INFO}, {"normal", LOG_INFO},
        {"warn", LOG_WARN}, {"warning", LOG_WARN}, {"warnings", LOG_WARN},
        {"error", LOG_ERROR}, {"errors", LOG_ERROR}, {"critical", LOG_CRITICAL},
        {"crit", LOG_CRITICAL},
    };
    char low[16];
    unsigned i;
    if (!s || !*s)
        return dflt;
    if (s[0] >= '0' && s[0] <= '5' && !s[1])
        return s[0] - '0';
    for (i = 0; i + 1 < sizeof low && s[i]; i++)
        low[i] = (char)tolower((unsigned char)s[i]);
    low[i] = 0;
    for (i = 0; i < sizeof k / sizeof k[0]; i++)
        if (!strcmp(low, k[i].name))
            return k[i].level;
    return dflt;
}

int log_level(void)
{
    if (s_level < 0)
        s_level = log_parse_level(getenv("RECOMP_LOG_LEVEL"), LOG_INFO);
    return s_level;
}

int log_enabled(int level)
{
    return level >= log_level();
}

void log_pump_attach(void)
{
    s_pump = 1;
}

static double now_s(void)
{
#ifdef _WIN32
    static LARGE_INTEGER f;
    LARGE_INTEGER c;
    if (!f.QuadPart)
        QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)f.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec * 1e-9;
#endif
}

double log_uptime(void)
{
    static double t0 = -1.0;
    double t = now_s();
    if (t0 < 0.0)
        t0 = t;
    return t - t0;
}

void log_stamp(char *out, unsigned n)
{
    int h, m, s, ms;
#ifdef _WIN32
    SYSTEMTIME st;
    GetLocalTime(&st);
    h = st.wHour; m = st.wMinute; s = st.wSecond; ms = st.wMilliseconds;
#else
    struct timeval tv;
    struct tm tmv;
    gettimeofday(&tv, NULL);
    localtime_r(&tv.tv_sec, &tmv);
    h = tmv.tm_hour; m = tmv.tm_min; s = tmv.tm_sec; ms = (int)(tv.tv_usec / 1000);
#endif
    snprintf(out, n, "%02d:%02d:%02d.%03d +%6.1f ", h, m, s, ms, log_uptime());
}

void log_msg(int level, const char *cat, const char *fmt, ...)
{
    char line[2048], stamp[40];
    va_list ap;
    int n;
    if (level < log_level() && !(s_pump && level >= LOG_DEBUG))
        return;
    log_stamp(stamp, sizeof stamp);
    n = snprintf(line, sizeof line, "%s%-5s [%s] ", stamp, log_level_name(level), cat ? cat : "-");
    if (n < 0 || n >= (int)sizeof line)
        return;
    va_start(ap, fmt);
    vsnprintf(line + n, sizeof line - (size_t)n, fmt, ap);
    va_end(ap);
    n = (int)strlen(line);
    if (n && line[n - 1] != '\n' && n + 1 < (int)sizeof line) {
        line[n++] = '\n';
        line[n] = 0;
    }
    fputs(line, stderr);             /* one call: lines from threads stay whole */
    if (level >= LOG_ERROR)
        fflush(stderr);
}
