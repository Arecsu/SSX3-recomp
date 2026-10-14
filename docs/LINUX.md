# Linux build

```bash
scripts/setup.sh && scripts/regen.sh      # as on Windows (XBE in disk/SSX3 or ../SSX3)
ln -s disk/SSX3 game                      # exe opens game/default.xbe from the cwd
cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build-linux && build-linux/ssx3_recomp
```

Deps: `tools/linux/install_deps.sh` in the toolkit (SDL2, libepoxy, OpenSSL).
Tested on aarch64 (Asahi) with GCC 16.

## Status (2026-10-14)

Builds, links, boots through XAPI init and D3D init, reads game data. Dies at
the first APU register access (guest 0x00263DDE, `test byte [0xFE801100]`).

## Blocker: no MMIO trap on POSIX

NV2A / APU / OHCI registers are unmapped guest pages; the Windows build catches
the fault in a VEH, decodes the **x86** instruction (`mmio_decode.h`, the
device hooks) and steps over it. `AddVectoredExceptionHandler` is a no-op in
`win32_compat.c`, and on an aarch64 host the faulting instruction is aarch64
anyway. `main.c` only installs a crash reporter (`segv_handler`).

Needed: SIGSEGV handler that decodes the host load/store (size, direction,
register), calls device read/write callbacks, writes the result back and
advances pc. The device hooks (`apu_hook_handle_mmio`, `xbox_OhciHandleMmio`,
NV2A in `xbox_memory_layout.c`) take a Windows `PCONTEXT` and decode x86
themselves; they need to move to the callback form `mmio_decode.h` already uses.

## Not ported

- `src/thread_dump.c` (Toolhelp/CONTEXT/debug registers): stubs.
- Video/audio/input backends: not looked at (SDL2/GL in the toolkit).
- SEH (`RtlUnwind`, `RaiseException`) is a shim in `win32_compat.c`.
