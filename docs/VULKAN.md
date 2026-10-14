# Vulkan renderer

Replaces the software rasteriser (`nv2a_pb_exec.c`) on Linux; Windows keeps
the D3D11 plan in ROADMAP.md Phase 2. Code: `src/vk/`. Target: Honeykrisp
(Asahi M2), Vulkan 1.3 dynamic rendering. Build/test standalone:

```
cmake -S src/vk -B build-vk -G Ninja && ninja -C build-vk && build-vk/vkr_selftest out.bmp
```

## Approach

The executor keeps parsing the pushbuffer, tracking state and running vertex
programs on the CPU (`nv2a_vsh_run`). Its post-program vertices
(`Nv2aVshOutput`: pixel-space pos, w, d0/d1, fog, 4x tex) go to `vkr_draw`
instead of the per-pixel rasteriser. The vertex shader re-expands pos to clip
space (`xy/size*2-1, z/zmax, w`) so the GPU clips and interpolates
perspective-correctly. Raster was ~65-70% of executor time; VSH ~15%.

## Milestones

1. [x] Context, offscreen colour+depth, indexed draws, readback (selftest).
2. [ ] Backend hook in the toolkit patch: `Nv2aGpuBackend` callbacks (clear,
   draw batch, flip/readback); exe registers it. `RECOMP_GPU=vk`.
3. [ ] Surfaces keyed by guest address; colour/depth, swizzled RTs; present
   by writing the front surface to guest memory (existing SDL present), then
   direct swapchain.
4. [ ] Textures: upload from guest memory (swizzle, DXT, palette), cache.
5. [ ] Register combiners -> GLSL (port of `nv2a_combiner.c`), keyed pipeline
   cache; blend, alpha test, fog, stencil, colour mask.
6. [ ] Vertex programs -> SPIR-V (removes the CPU interpreter).
7. [ ] Differential test vs software output.
