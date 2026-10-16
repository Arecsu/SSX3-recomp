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

Boots through intro to the menus on aarch64 (Asahi, M2) with a window (SDL2,
`RECOMP_FB_WINDOW`, default in main.c). Not yet checked: playing, audio, input,
speed. Run with `timeout -s KILL` (plain `timeout` leaves the process behind).

What makes it work on POSIX:

- `src/mmio_posix.c`: SIGSEGV handler decodes the host aarch64 load/store for
  APU / OHCI registers (device callbacks, `xbox_OhciMmioAccess`); no x86
  decoding. LDP/STP, SIMD, exclusives are declined and reported.
- AC'97 bus-master reset (RR bit) trap: page made read-only, writes emulated in
  `main.c` (`ac97_arm`).
- Hardware TSO (`PR_SET_MEM_MODEL`, Apple cores) for the guest's x86 ordering.
- Guest memory reserved at 0x100000000000 so the 0xFD000000+ apertures fit.
- Case-insensitive path resolution (`fix_path_case`), Partition0 image.
- `video/fb_present_sdl.c`: framebuffer window, BMP dump, `RECOMP_SNAP_TRIGGER`.
- Thread dump (`RECOMP_THREAD_DUMP_SECS`, SIGUSR2) and `RECOMP_PEEK_EVERY_MS`.

## Not ported

- `RECOMP_WATCH` (hardware watchpoints), Toolhelp-based dumps.
- Audio: SDL2 audio queue behind the `xa2_*` interface (apu_xaudio2.c), not checked by ear. Gamepad/keyboard: untested.
- SEH (`RtlUnwind`, `RaiseException`) is a shim in `win32_compat.c`.
- x86-64 hosts: `mmio_posix_step` only decodes aarch64.
