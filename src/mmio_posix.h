#ifndef MMIO_POSIX_H
#define MMIO_POSIX_H
#include <stdint.h>
#include <stddef.h>

/* Device accessors, keyed by host fault address. */
typedef uint64_t (*mmio_read_fn)(uintptr_t addr, int size);
typedef void     (*mmio_write_fn)(uintptr_t addr, uint64_t val, int size);

/* Decode the faulting host load/store in `uc` (a ucontext_t), service it and
 * advance pc. Returns 0 if the instruction is not understood; *insn_out then
 * (and always) holds the instruction word. */
int mmio_posix_step(void *uc, uintptr_t fault, mmio_read_fn rd, mmio_write_fn wr,
                    uint32_t *insn_out);
#endif
