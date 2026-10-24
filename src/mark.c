/*
 * The player's mark (docs/LOGGING.md C1): "I saw it here".
 *
 * F12, or both thumbsticks clicked together on a controller, writes
 *   INFO [MARK] *** player mark N (F12) *** in game, Snow Jam; in game; snapshot logs\mark_...bmp
 * to the session log -- the log pump writes its flight recorder (the detail
 * lines below the log level) just before it -- and saves what the window
 * shows next to the log. A host thread polls every 50 ms, so a mark works
 * while the game itself hangs.
 */
#include "log.h"
#ifdef _WIN32
#include <windows.h>
#include <xinput.h>
#else
#include "platform/win32_compat.h"
#endif
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#ifndef _WIN32
#include <sys/stat.h>
#endif

#ifndef VK_F12
#define VK_F12 0x7B
#endif

extern int xbox_FramebufferKeyPresses(int vk);
extern void xbox_FramebufferSnapshot(const char *path);
extern const char *ssx3_LogsDir(void);                /* main.c */
extern void ssx3_WhereNow(char *out, size_t n);       /* game_state.c */
extern const char *ssx3_ScreenNow(void);              /* ssx3_overrides.c */

static void mark(const char *how)
{
    static int n;
    char where[128], path[512];
    time_t now = time(NULL);
    struct tm tm;
#ifdef _WIN32
    localtime_s(&tm, &now);
    CreateDirectoryA(ssx3_LogsDir(), NULL);
#else
    localtime_r(&now, &tm);
    mkdir(ssx3_LogsDir(), 0755);
#endif
    n++;
    snprintf(path, sizeof path, "%s%cmark_%04d%02d%02d-%02d%02d%02d_%d.bmp", ssx3_LogsDir(),
#ifdef _WIN32
             '\\',
#else
             '/',
#endif
             tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, n);
    ssx3_WhereNow(where, sizeof where);
    xbox_FramebufferSnapshot(path);
    log_msg(LOG_INFO, "MARK", "*** player mark %d (%s) *** %s; %s; snapshot %s", n, how, where,
            ssx3_ScreenNow(), path);
}

static DWORD WINAPI mark_thread(LPVOID unused)
{
    int pads_held = 0;
#ifdef _WIN32
    int pads = !getenv("RECOMP_NO_HOST_PAD");
#endif
    (void)unused;
    for (;;) {
        int k = xbox_FramebufferKeyPresses(VK_F12), held = 0;
        while (k-- > 0)
            mark("F12");
#ifdef _WIN32
        if (pads) {
            DWORD i;
            for (i = 0; i < 4; i++) {
                XINPUT_STATE st;
                if (XInputGetState(i, &st) == ERROR_SUCCESS
                        && (st.Gamepad.wButtons & (XINPUT_GAMEPAD_LEFT_THUMB | XINPUT_GAMEPAD_RIGHT_THUMB))
                               == (XINPUT_GAMEPAD_LEFT_THUMB | XINPUT_GAMEPAD_RIGHT_THUMB))
                    held = 1;
            }
        }
#endif
        if (held && !pads_held)
            mark("both sticks clicked");
        pads_held = held;
        Sleep(50);
    }
    return 0;
}

void ssx3_MarkStart(void)
{
    const char *e = getenv("RECOMP_MARK");
    if (e && e[0] == '0')
        return;
    CloseHandle(CreateThread(NULL, 0, mark_thread, NULL, 0, NULL));
}
