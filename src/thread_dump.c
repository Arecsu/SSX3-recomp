/**
 * All-thread native stack dump, for hangs.
 *
 * The toolkit watchdog (RECOMP_WATCHDOG_SECS) samples the guest stack of the
 * thread that called xbox_WatchdogStart only, so a hang where the main thread
 * waits on a worker shows the wait and nothing about the worker. This samples
 * every thread instead. Generated functions are native functions named after
 * their guest address, so each thread's native stack, run through
 *
 *     xboxrecomp/tools/symbolize.py build/ssx3_recomp.map < stderr.txt
 *
 * reads as that thread's guest call chain (sub_XXXXXXXX + offset).
 *
 * Off unless RECOMP_THREAD_DUMP_SECS is set. Addresses inside the exe are
 * printed rebased to 0x140000000, the base the map file is written for.
 */
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "recomp/gen/recomp_types.h"   /* the thread-local guest registers */

extern ULONG _tls_index;

#define TD_MAX_THREADS 64
#define TD_MAX_FRAMES  40
#define TD_MAP_BASE    0x140000000ULL

typedef LONG (NTAPI *NtQueryInformationThread_t)(HANDLE, ULONG, PVOID, ULONG, PULONG);

typedef struct {
    DWORD   tid;
    DWORD64 start;
    int     n;
    DWORD64 rip[TD_MAX_FRAMES];
    int     has_regs;
    uint32_t regs[8];   /* eax ecx edx ebx esp ebp esi edi */
} ThreadStack;

/* The guest registers are __declspec(thread), so another thread's copies live
 * in its own TLS block: TEB+0x58 is ThreadLocalStoragePointer, indexed by the
 * module's _tls_index, and each variable sits at the same offset into every
 * thread's block. Offsets are taken from this thread's own block. */
static uint32_t *td_reg_addr[8];
static ptrdiff_t td_reg_off[8];

static BYTE *td_tls_block(BYTE *teb)
{
    BYTE **slots = *(BYTE ***)(teb + 0x58);
    return slots ? slots[_tls_index] : NULL;
}

static void td_reg_offsets(void)
{
    BYTE *mine = td_tls_block((BYTE *)NtCurrentTeb());
    int i;

    td_reg_addr[0] = &g_eax; td_reg_addr[1] = &g_ecx; td_reg_addr[2] = &g_edx;
    td_reg_addr[3] = &g_ebx; td_reg_addr[4] = &g_esp; td_reg_addr[5] = &g_ebp;
    td_reg_addr[6] = &g_esi; td_reg_addr[7] = &g_edi;
    for (i = 0; i < 8; i++)
        td_reg_off[i] = mine ? (BYTE *)td_reg_addr[i] - mine : -1;
}

static int td_read_regs(HANDLE h, NtQueryInformationThread_t query, uint32_t *out)
{
    struct { LONG status; BYTE *teb; ULONG_PTR rest[4]; } tbi;  /* THREAD_BASIC_INFORMATION */
    int i;

    if (!query || query(h, 0, &tbi, sizeof(tbi), NULL) < 0 || !tbi.teb)
        return 0;
    __try {
        BYTE *block = td_tls_block(tbi.teb);
        if (!block)
            return 0;
        for (i = 0; i < 8; i++) {
            if (td_reg_off[i] < 0)
                return 0;
            out[i] = *(uint32_t *)(block + td_reg_off[i]);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 0;
    }
    return 1;
}

static DWORD64 s_exe_base, s_exe_end;

static DWORD64 td_rebase(DWORD64 a)
{
    return (a >= s_exe_base && a < s_exe_end) ? a - s_exe_base + TD_MAP_BASE : a;
}

/* Unwind with the exe's own .pdata, so no PDB or dbghelp is needed. Runs while
 * the thread is suspended; a fault on a torn stack ends the walk early. */
static int td_walk(CONTEXT *ctx, DWORD64 *out)
{
    int n = 0;

    __try {
        while (n < TD_MAX_FRAMES && ctx->Rip) {
            DWORD64 base;
            PRUNTIME_FUNCTION f;

            out[n++] = ctx->Rip;
            f = RtlLookupFunctionEntry(ctx->Rip, &base, NULL);
            if (f) {
                PVOID handler_data;
                DWORD64 frame;
                RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, ctx->Rip, f, ctx,
                                 &handler_data, &frame, NULL);
            } else {                    /* leaf: return address on top */
                ctx->Rip = *(DWORD64 *)ctx->Rsp;
                ctx->Rsp += 8;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    return n;
}

static DWORD WINAPI td_thread(LPVOID arg)
{
    static ThreadStack stacks[TD_MAX_THREADS];
    NtQueryInformationThread_t query = (NtQueryInformationThread_t)
        GetProcAddress(GetModuleHandleA("ntdll.dll"), "NtQueryInformationThread");
    DWORD self = GetCurrentThreadId(), pid = GetCurrentProcessId();
    THREADENTRY32 te = { sizeof(te) };
    HANDLE snap;
    int count = 0, i, j;

    Sleep((DWORD)(uintptr_t)arg * 1000u);
    td_reg_offsets();

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    /* Collect everything first and print afterwards: printing while another
     * thread is suspended can deadlock on a CRT lock it holds. */
    for (BOOL ok = Thread32First(snap, &te); ok && count < TD_MAX_THREADS;
         ok = Thread32Next(snap, &te)) {
        HANDLE h;
        CONTEXT ctx;

        if (te.th32OwnerProcessID != pid || te.th32ThreadID == self)
            continue;
        h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
                       THREAD_QUERY_INFORMATION, FALSE, te.th32ThreadID);
        if (!h)
            continue;
        stacks[count].tid = te.th32ThreadID;
        stacks[count].start = 0;
        if (query)              /* 9 = ThreadQuerySetWin32StartAddress */
            query(h, 9, &stacks[count].start, sizeof(DWORD64), NULL);
        stacks[count].n = 0;
        stacks[count].has_regs = 0;
        if (SuspendThread(h) != (DWORD)-1) {
            stacks[count].has_regs = td_read_regs(h, query, stacks[count].regs);
            ZeroMemory(&ctx, sizeof(ctx));
            ctx.ContextFlags = CONTEXT_FULL;
            if (GetThreadContext(h, &ctx))
                stacks[count].n = td_walk(&ctx, stacks[count].rip);
            ResumeThread(h);
        }
        CloseHandle(h);
        count++;
    }
    CloseHandle(snap);

    fprintf(stderr, "[THREADS] %d threads after %us\n", count,
            (unsigned)(uintptr_t)arg);
    for (i = 0; i < count; i++) {
        fprintf(stderr, "[THREAD] tid=%lu start=0x%llX\n", stacks[i].tid,
                (unsigned long long)td_rebase(stacks[i].start));
        if (stacks[i].has_regs)
            fprintf(stderr, "    guest eax=%08X ecx=%08X edx=%08X ebx=%08X"
                    " esp=%08X ebp=%08X esi=%08X edi=%08X\n",
                    stacks[i].regs[0], stacks[i].regs[1], stacks[i].regs[2],
                    stacks[i].regs[3], stacks[i].regs[4], stacks[i].regs[5],
                    stacks[i].regs[6], stacks[i].regs[7]);
        for (j = 0; j < stacks[i].n; j++)
            fprintf(stderr, "    #%-2d 0x%llX\n", j,
                    (unsigned long long)td_rebase(stacks[i].rip[j]));
    }
    fflush(stderr);
    return 0;
}

void ssx3_ThreadDumpStart(void)
{
    const char *e = getenv("RECOMP_THREAD_DUMP_SECS");
    unsigned secs = e ? (unsigned)atoi(e) : 0;
    HMODULE exe = GetModuleHandleA(NULL);
    PIMAGE_NT_HEADERS nt;

    if (!secs)
        return;
    nt = (PIMAGE_NT_HEADERS)((BYTE *)exe + ((PIMAGE_DOS_HEADER)exe)->e_lfanew);
    s_exe_base = (DWORD64)exe;
    s_exe_end  = s_exe_base + nt->OptionalHeader.SizeOfImage;
    CloseHandle(CreateThread(NULL, 0, td_thread, (LPVOID)(uintptr_t)secs, 0, NULL));
}
