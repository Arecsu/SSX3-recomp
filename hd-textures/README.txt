HD textures
===========

The DDS files here are Bl4ckH4nd's HD texture pack for SSX 3 on the PS2
(made for PCSX2's texture replacement), used with permission:
  https://gbatemp.net/threads/my-ps2-packs.621422/

The pack is named after the PS2's texture memory, so the Xbox game cannot
look its files up by name. ssx3_map.txt pairs the Xbox game's textures
(a hash of their pixels) with the pack's files; it was made by comparing
the images (tools/hdtex_match.py), so a texture that looks wrong can be
taken out by deleting its line. Anything not listed keeps the original
Xbox texture. "a2" after a file: its alpha is on the PS2's 0..128 scale
and is doubled when drawn.

The game uses this folder when it sits next to ssx3_recomp.exe (the
working directory); RECOMP_HDTEX=<folder> points elsewhere and
RECOMP_HDTEX=0 (or the launcher's "HD textures" box) turns it off.
