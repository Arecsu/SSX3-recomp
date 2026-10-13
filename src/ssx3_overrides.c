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
#include <math.h>
#include <stdio.h>

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
 * CRT math through the x87 transcendental dispatcher, replaced natively.
 *
 * sub_00213850 is exp(double) and sub_00212C18 is fmod(double, double): cdecl,
 * arguments on the stack, result pushed on the x87 stack. Both reach the CRT's
 * hand-written dispatcher (ctrandisp1/ctrandisp2 -> trandisp*, a computed
 * `jmp [ebx]` into shared tails), and the lifted path returns with the
 * caller's ebx replaced by stale stack data (0x000D1284) -- most likely
 * ctrandisp1's `pop ebx` reads one slot off because a tail leaves the guest
 * esp 4 high (not yet verified). RECOMP_ABI_CHECK names it:
 * "[ABI] sub_00213850: ebx 00000000->000D1284". The caller that broke is the
 * state machine sub_001AD880, which keeps 0 in ebx across its loop: through
 * the loading screen's sub_001AD7B0 -> exp(), its render test
 * `cmp [esi+0x38], bl` stopped matching, the per-state update counter never
 * reset, and the "Loading..." fade never finished.
 *
 * These are the only two stubs that reach those dispatchers.
 */
static double arg_double(uint32_t va)
{
    union { uint32_t u[2]; double d; } v;
    v.u[0] = MEM32(va);
    v.u[1] = MEM32(va + 4);
    return v.d;
}

static void fp_push_result(double v)
{
    g_fp_top = (g_fp_top + 7) & 7;
    g_fp_stack[g_fp_top] = v;
}

/* double exp(double) */
void sub_00213850(void)
{
    fp_push_result(exp(arg_double(g_esp + 4)));
    g_esp += 4;
}

/* double fmod(double, double) */
void sub_00212C18(void)
{
    fp_push_result(fmod(arg_double(g_esp + 4), arg_double(g_esp + 12)));
    g_esp += 4;
}

/*
 * DirectSound effects-image download (sub_0025BD81, XDK DSOUND): after
 * copying the image it posts command 3 to the GP DSP at
 * *(*(*(this+8)+0x10)) + 0x810 and spins until the DSP clears it (guest
 * 0x0025BEE6). The DSP is a stub, so the toolkit's DSP ack clears it -- this
 * registers the word from the object itself instead of a fixed address
 * (RECOMP_DSP_ACK=0x83818810 depended on allocation order).
 */
extern void sub_0025BD81_gen(void);
extern int xbox_DspAckAdd(uint32_t va);

void sub_0025BD81(void)
{
    uint32_t p = g_ecx;
    if (p) p = MEM32(p + 8);
    if (p) p = MEM32(p + 0x10);
    if (p) p = MEM32(p);
    if (p)
        xbox_DspAckAdd(p + 0x810);
    sub_0025BD81_gen();
}

/*
 * EA's allocator (sub_001A9BD0, ~300 direct callers), wrapped to report
 * failures. The race load (Snow Jam) ends up using a NULL script register
 * array allocated in sub_0016B4F0; this says whether the heap -- a fixed
 * 0x2C80000-byte XPhysicalAlloc block at [0x3A9334], size [0x3A9338], heap
 * object 0x3A9368 -- is really exhausted or a single request is bad.
 * cdecl: [esp+4] size, [esp+8] name/tag, [esp+12] flags.
 */
extern void sub_001A9BD0_gen(void);

void sub_001A9BD0(void)
{
    static volatile long failures, calls;
    static volatile long long requested;
    uint32_t ret_va = MEM32(g_esp);
    uint32_t size = MEM32(g_esp + 4);
    uint32_t tag = MEM32(g_esp + 8);
    uint32_t flags = MEM32(g_esp + 12);

    InterlockedIncrement(&calls);
    InterlockedExchangeAdd64(&requested, size);
    sub_001A9BD0_gen();
    if (g_eax == 0 && InterlockedIncrement(&failures) <= 24)
        fprintf(stderr, "  [ALLOC] FAILED size=0x%X (%u) tag=0x%08X flags=0x%08X "
                        "caller=0x%08X  (call #%ld, %lld bytes requested so far)\n",
                size, size, tag, flags, ret_va, calls, requested);
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
extern void sub_000E1AE0(void);   /* app vtbl[6]: sample input into the ring */
extern void sub_000E1A80(void);   /* app vtbl[5]: is an input frame (update) due */
extern void sub_000D7460(void);   /* loading state vtbl[6]: render */

static void trace_call(const char *name, void (*fn)(void), volatile long *n)
{
    long k = InterlockedIncrement(n);
    uint32_t ecx = g_ecx;

    if (k <= 8 || (k & 63) == 0)
        fprintf(stderr, "  [FRAMETIMER] %s #%ld tid=%lu ecx=%08X t=%lu\n",
                name, k, GetCurrentThreadId(), ecx, GetTickCount());
    fn();
}

/* Same, but logs the return value (al) whenever it changes, with the input
 * ring indices: guest 0x0036952C is the input manager, +0x2EE0 read and
 * +0x2EE4 write. */
static void trace_ret(const char *name, void (*fn)(void), volatile long *n,
                      volatile long *last)
{
    long k = InterlockedIncrement(n);
    long ret;
    uint32_t im, edi_in = g_edi, esi_in = g_esi, ebx_in = g_ebx;

    fn();
    ret = (long)(g_eax & 0xFF);
    if (ret != *last || (k & 63) == 0) {
        im = MEM32(0x0036952C);
        fprintf(stderr, "  [GATE] %s #%ld -> %ld  t=%lu  ring r=%u w=%u"
                "  edi_in=%08X esi_in=%08X ebx_in=%08X\n",
                name, k, ret, GetTickCount(),
                im ? MEM32(im + 0x2EE0) : 0, im ? MEM32(im + 0x2EE4) : 0,
                edi_in, esi_in, ebx_in);
        *last = ret;
    }
}

#define TRACED_RET(va)                                                 \
    static volatile long n_##va, last_##va = -1;                       \
    static void traced_##va(void) { trace_ret(#va, va, &n_##va, &last_##va); }

#define TRACED(va)                                                     \
    static volatile long n_##va;                                       \
    static void traced_##va(void) { trace_call(#va, va, &n_##va); }

TRACED(sub_001AE020)
TRACED(sub_001ADF40)
TRACED(sub_001ADF50)
TRACED(sub_001ADF60)
TRACED(sub_001ADF70)
TRACED(sub_001ADF90)
TRACED(sub_000E1AE0)
TRACED_RET(sub_000E1A80)
TRACED_RET(sub_000D7460)

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
    case 0x000E1AE0: return traced_sub_000E1AE0;
    case 0x000E1A80: return traced_sub_000E1A80;
    case 0x000D7460: return traced_sub_000D7460;
    }
    return NULL;
}
