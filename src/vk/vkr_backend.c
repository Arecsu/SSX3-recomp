/* Glue: the executor's Nv2aBackend on top of the Vulkan renderer.
 *
 * Milestone-2 scope: one "main" colour target (the largest non-swizzled
 * 32-bit surface drawn to). Draws and clears on any other target are declined
 * so the software rasteriser still handles them in guest memory. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "nv2a_backend.h"
#include "vkr.h"
#include "vkr_backend.h"

extern ptrdiff_t xbox_GetMemoryOffset(void);

_Static_assert(sizeof(VkrVertex) == sizeof(Nv2aVshOutput),
               "VkrVertex must mirror Nv2aVshOutput");

#define PRIM_TRIANGLES      5
#define PRIM_TRIANGLE_STRIP 6
#define PRIM_TRIANGLE_FAN   7
#define PRIM_QUADS          8
#define PRIM_QUAD_STRIP     9
#define PRIM_POLYGON        10

static VkrContext *s_vk;
static uint32_t s_w, s_h, s_zmax;
static int s_dirty;                     /* drawn since the last flip */
static uint8_t *s_px;

/* Is t the surface the Vulkan target stands for? Adopts the first one that
 * looks like a frame buffer (>= 320x240, linear, 32-bit); a size change
 * replaces the target. */
static int is_main(const Nv2aTarget *t)
{
    if (t->swizzled || t->bpp != 4)
        return 0;
    if (t->width < 320 || t->height < 240)
        return 0;
    if (t->x + t->width > t->pitch / 4)
        return 0;
    if (t->width != s_w || t->height != s_h || t->zmax != s_zmax) {
        if (!vkr_set_target(s_vk, t->width, t->height, (float)t->zmax))
            return 0;
        free(s_px);
        s_px = (uint8_t *)malloc((size_t)t->width * t->height * 4);
        s_w = t->width; s_h = t->height; s_zmax = t->zmax;
        fprintf(stderr, "[VKR] target %ux%u zmax %X\n", s_w, s_h, s_zmax);
    }
    return s_px != NULL;
}

static int be_draw(const Nv2aTarget *t, uint32_t prim, const Nv2aVshOutput *v, uint32_t n)
{
    static uint32_t *idx;
    static uint32_t cap;
    uint32_t i, k = 0, need = n * 6;

    if (!is_main(t))
        return 0;
    if (cap < need) {
        free(idx);
        cap = need;
        idx = (uint32_t *)malloc(cap * sizeof *idx);
        if (!idx) { cap = 0; return 0; }
    }
    switch (prim) {
    case PRIM_TRIANGLES:
        for (i = 0; i + 2 < n; i += 3) {
            idx[k++] = i; idx[k++] = i + 1; idx[k++] = i + 2;
        }
        break;
    case PRIM_TRIANGLE_STRIP:
        for (i = 0; i + 2 < n; i++) {
            /* keep the winding consistent; culling is off, order is free */
            idx[k++] = i; idx[k++] = i + 1; idx[k++] = i + 2;
        }
        break;
    case PRIM_TRIANGLE_FAN:
    case PRIM_POLYGON:
        for (i = 1; i + 1 < n; i++) {
            idx[k++] = 0; idx[k++] = i; idx[k++] = i + 1;
        }
        break;
    case PRIM_QUADS:
        for (i = 0; i + 3 < n; i += 4) {
            idx[k++] = i; idx[k++] = i + 1; idx[k++] = i + 2;
            idx[k++] = i; idx[k++] = i + 2; idx[k++] = i + 3;
        }
        break;
    case PRIM_QUAD_STRIP:
        for (i = 0; i + 3 < n; i += 2) {
            idx[k++] = i; idx[k++] = i + 1; idx[k++] = i + 3;
            idx[k++] = i; idx[k++] = i + 3; idx[k++] = i + 2;
        }
        break;
    default:
        return 0;                       /* points and lines: not yet */
    }
    if (!k)
        return 1;
    /* The vertex program output is relative to the surface origin, and the
     * target is the clip rectangle, which on a frame buffer is the surface. */
    vkr_draw(s_vk, (const VkrVertex *)v, n, idx, k, t->depth_test, t->depth_write,
             t->depth_func);
    s_dirty = 1;
    return 1;
}

static int be_clear(const Nv2aTarget *t, uint32_t flags, uint32_t argb, float depth)
{
    float c[4];
    if (!is_main(t))
        return 0;
    c[0] = (float)((argb >> 16) & 0xFF) / 255.0f;
    c[1] = (float)((argb >> 8) & 0xFF) / 255.0f;
    c[2] = (float)(argb & 0xFF) / 255.0f;
    c[3] = (float)(argb >> 24) / 255.0f;
    if (!(flags & NV2A_CLEAR_COLOR) && !(flags & NV2A_CLEAR_Z))
        return 1;
    if (flags & NV2A_CLEAR_COLOR)
        vkr_clear(s_vk, c, (flags & NV2A_CLEAR_Z) != 0, depth);
    else {
        /* depth-only clear: colour untouched */
        vkr_clear_depth(s_vk, depth);
    }
    s_dirty = 1;
    return 1;
}

static void be_flip(const Nv2aTarget *t)
{
    uint8_t *mem = (uint8_t *)xbox_GetMemoryOffset();
    uint32_t y;
    if (!s_dirty || t->bpp != 4 || t->width != s_w || t->height != s_h)
        return;
    if (!vkr_read_back(s_vk, s_px))
        return;
    for (y = 0; y < s_h; y++)
        memcpy(mem + t->color_offset + (size_t)(t->y + y) * t->pitch + (size_t)t->x * 4,
               s_px + (size_t)y * s_w * 4, (size_t)s_w * 4);
    s_dirty = 0;
}

static const Nv2aBackend s_backend = {be_draw, be_clear, be_flip};

int vkr_backend_install(void)
{
    s_vk = vkr_create();
    if (!s_vk)
        return 0;
    nv2a_exec_set_backend(&s_backend);
    fprintf(stderr, "[VKR] backend installed\n");
    return 1;
}
