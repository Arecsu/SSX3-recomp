/**
 * SSX 3 - hand-written replacements for generated functions.
 *
 * Every sub_XXXXXXXX defined here replaces the generated body: the pipeline is
 * run with --exclude-manual src/ssx3_overrides.c, which skips generating any
 * function this file defines, so direct calls link to these.
 *
 * This file includes recomp_types.h rather than declaring the registers itself
 * the way recomp_manual.c does: the registers are thread-local, and a plain
 * `extern uint32_t g_eax` names the TLS template, not the running thread's copy.
 */
#include <windows.h>
#include "recomp/gen/recomp_types.h"

/*
 * sub_00183EBB - XAPI startup media check (XDK 5558 library code).
 *
 * When the certificate asks for it (cert+0x1D8 bit 0, which SSX 3 sets), this
 * reads the disc's security sector with READ DVD STRUCTURE and hands it to
 * sub_00183E04, which checks the title ID, SHA-1s it and verifies Microsoft's
 * RSA signature with XcVerifyPKCS1Signature against XePublicKeyData. Five
 * failures and the caller reboots through HalReturnToFirmware.
 *
 * That sector is pressed onto the physical disc and is not in a file-level
 * rip, and there is no drive here to read it from, so the check cannot pass.
 * Return what the function itself returns when the certificate does not ask
 * for the check (0x00183EFF: xor eax, eax): STATUS_SUCCESS.
 *
 * cdecl, no parameters: pop the return address the caller pushed, nothing else.
 */
void sub_00183EBB(void)
{
    g_eax = 0;
    g_esp += 4;
}

/*
 * Bring-up tracing for the frame-timer object (0x80592400 on a normal boot):
 * the main thread waits on its +0x10 event in sub_001ADF40, the worker thread
 * (sub_001AE0E0) waits on +0x34, and sub_001AE020 is its timeSetEvent
 * callback. All are reached through vtables or the timer thread's callback
 * pointer, so recomp_lookup_manual routes them here without regenerating.
 * Enabled by RECOMP_TRACE_FRAMETIMER=1.
 */
#include <stdio.h>
#include <stdlib.h>

extern void sub_001AE020(void);
extern void sub_001ADF40(void);
extern void sub_001ADF50(void);
extern void sub_001ADF60(void);
extern void sub_001ADF70(void);
extern void sub_001ADF90(void);

static void trace_call(const char *name, void (*fn)(void), volatile long *n)
{
    long k = InterlockedIncrement(n);
    uint32_t ecx = g_ecx;

    if (k <= 8 || (k & 63) == 0)
        fprintf(stderr, "  [FRAMETIMER] %s #%ld tid=%lu ecx=%08X\n",
                name, k, GetCurrentThreadId(), ecx);
    fn();
}

#define TRACED(va)                                                     \
    static volatile long n_##va;                                       \
    static void traced_##va(void) { trace_call(#va, va, &n_##va); }

TRACED(sub_001AE020)
TRACED(sub_001ADF40)
TRACED(sub_001ADF50)
TRACED(sub_001ADF60)
TRACED(sub_001ADF70)
TRACED(sub_001ADF90)

void *ssx3_lookup_trace(uint32_t va)
{
    static int on = -1;

    if (on < 0)
        on = getenv("RECOMP_TRACE_FRAMETIMER") != NULL;
    if (!on)
        return NULL;
    switch (va) {
    case 0x001AE020: return traced_sub_001AE020;
    case 0x001ADF40: return traced_sub_001ADF40;
    case 0x001ADF50: return traced_sub_001ADF50;
    case 0x001ADF60: return traced_sub_001ADF60;
    case 0x001ADF70: return traced_sub_001ADF70;
    case 0x001ADF90: return traced_sub_001ADF90;
    }
    return NULL;
}
