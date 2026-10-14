/*
 * MMIO trap for the POSIX host: the counterpart of the Windows VEH path.
 *
 * Device registers (APU, OHCI) are unmapped guest pages. A guest load/store
 * faults; the SIGSEGV handler decodes the *host* instruction, runs the device
 * model, writes the result back and steps over it. Unknown encodings are
 * declined (never guessed at) so the crash reporter names the opcode.
 *
 * Only aarch64 is decoded: the GPR load/store forms a compiler emits for a
 * single volatile-ish access. LDP/STP, SIMD, exclusives are not.
 */
#if !defined(_WIN32)
#define _GNU_SOURCE
#include <signal.h>
#include <ucontext.h>
#include <stdint.h>
#include <stdio.h>

#include "mmio_posix.h"

#if defined(__aarch64__)

typedef struct {
    int      is_write;
    int      size;       /* bytes */
    int      rt;         /* 0..31 (31 = zero register) */
    int      sign_ext;   /* 0 none, 32 -> W destination, 64 -> X destination */
    int      rn;         /* base register, for writeback */
    int      wb_mode;    /* 0 none, 1 pre-index, 2 post-index */
    int64_t  wb_imm;
} a64_access;

static int a64_decode(uint32_t insn, a64_access *a)
{
    uint32_t size = insn >> 30, opc = (insn >> 22) & 3;

    /* Load/store register: bits 29:27 = 111, V (26) = 0. */
    if (((insn >> 27) & 7) != 7 || ((insn >> 26) & 1))
        return 0;

    switch ((insn >> 24) & 3) {
    case 1:                                  /* unsigned offset */
        break;
    case 0:
        if ((insn >> 21) & 1) {
            if (((insn >> 10) & 3) != 2)     /* register offset only */
                return 0;
        } else {
            switch ((insn >> 10) & 3) {      /* imm9 forms */
            case 0: break;                   /* LDUR/STUR */
            case 1: a->wb_mode = 2; break;   /* post-index */
            case 3: a->wb_mode = 1; break;   /* pre-index */
            default: return 0;               /* unprivileged */
            }
            a->wb_imm = ((int64_t)((insn >> 12) & 0x1FF) << 55) >> 55;
        }
        break;
    default:
        return 0;
    }

    a->size = 1 << size;
    a->rt = insn & 31;
    a->rn = (insn >> 5) & 31;
    if (a->rn == 31)
        return 0;                            /* SP-based: not device access */

    switch (opc) {
    case 0: a->is_write = 1; break;
    case 1: a->is_write = 0; break;
    case 2:                                  /* LDRSx -> X */
        if (size == 3) return 0;             /* PRFM */
        a->sign_ext = 64; break;
    case 3:                                  /* LDRSx -> W */
        if (size >= 2) return 0;
        a->sign_ext = 32; break;
    }
    return 1;
}

int mmio_posix_step(void *uc_, uintptr_t fault, mmio_read_fn rd, mmio_write_fn wr,
                    uint32_t *insn_out)
{
    ucontext_t *uc = (ucontext_t *)uc_;
    uint32_t insn = *(const uint32_t *)uc->uc_mcontext.pc;
    a64_access a = {0};

    if (insn_out)
        *insn_out = insn;
    if (!a64_decode(insn, &a))
        return 0;

    if (a.is_write) {
        uint64_t v = a.rt == 31 ? 0 : uc->uc_mcontext.regs[a.rt];
        if (a.size < 8)
            v &= (1ULL << (a.size * 8)) - 1;
        wr(fault, v, a.size);
    } else {
        uint64_t v = rd(fault, a.size);
        if (a.size < 8)
            v &= (1ULL << (a.size * 8)) - 1;
        if (a.sign_ext) {
            int sh = 64 - a.size * 8;
            v = (uint64_t)(((int64_t)(v << sh)) >> sh);
            if (a.sign_ext == 32)
                v &= 0xFFFFFFFFULL;
        }
        if (a.rt != 31)
            uc->uc_mcontext.regs[a.rt] = v;
    }

    if (a.wb_mode == 1)
        uc->uc_mcontext.regs[a.rn] = fault;
    else if (a.wb_mode == 2)
        uc->uc_mcontext.regs[a.rn] = fault + a.wb_imm;

    uc->uc_mcontext.pc += 4;
    return 1;
}

#else  /* !__aarch64__ */

int mmio_posix_step(void *uc, uintptr_t fault, mmio_read_fn rd, mmio_write_fn wr,
                    uint32_t *insn_out)
{
    (void)uc; (void)fault; (void)rd; (void)wr; (void)insn_out;
    return 0;                                /* x86-64 host: not done */
}

#endif
#endif /* !_WIN32 */
