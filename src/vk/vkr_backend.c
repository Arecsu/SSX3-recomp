/* Glue: the executor's Nv2aBackend on top of the Vulkan renderer.
 *
 * Milestone-2 scope: one "main" colour target (the largest non-swizzled
 * 32-bit surface drawn to). Draws and clears on any other target are declined
 * so the software rasteriser still handles them in guest memory. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

/* RECOMP_VKR_STATS=1: where the backend's time goes, once a second. */
static double s_t[6];            /* draw total, lookup+hash, decode+upload, vkr_draw, flip */
static unsigned s_n[3];          /* draws, texture creates, flips */
static int s_stats = -1;

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static void stats_tick(void)
{
    static double last;
    double t = now_ms();
    if (!last) last = t;
    if (t - last < 1000.0)
        return;
    fprintf(stderr, "[VKRSTAT] draws %u tex-creates %u flips %u | ms/s: draw-total %.0f lookup+hash %.0f"
            " decode+upload %.0f vkr_draw %.0f flip %.0f\n", s_n[0], s_n[1], s_n[2],
            s_t[0], s_t[1], s_t[2], s_t[3], s_t[4]);
    memset(s_t, 0, sizeof s_t); memset(s_n, 0, sizeof s_n);
    last = t;
}

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

static void fill_state(const Nv2aTarget *t, VkrDrawState *st)
{
    VkrUniforms *u = &st->u;
    int k;
    st->depth_test = t->depth_test; st->depth_write = t->depth_write;
    st->depth_func = t->depth_func;
    st->blend_enable = t->blend_enable;
    st->blend_src = t->blend_sfactor; st->blend_dst = t->blend_dfactor;
    st->blend_eq = t->blend_equation;
    st->blend_color[0] = (float)((t->blend_color >> 16) & 0xFF) / 255.0f;
    st->blend_color[1] = (float)((t->blend_color >> 8) & 0xFF) / 255.0f;
    st->blend_color[2] = (float)(t->blend_color & 0xFF) / 255.0f;
    st->blend_color[3] = (float)(t->blend_color >> 24) / 255.0f;
    st->write_mask = ((t->color_mask >> 16) & 0xFF ? 1u : 0u) | ((t->color_mask >> 8) & 0xFF ? 2u : 0u)
                   | (t->color_mask & 0xFF ? 4u : 0u) | (t->color_mask >> 24 ? 8u : 0u);
    st->alpha_func = t->alpha_test ? t->alpha_func : 0;
    st->alpha_ref = t->alpha_ref & 0xFF;

    memcpy(u->color_icw, t->rc.color_icw, sizeof u->color_icw);
    memcpy(u->alpha_icw, t->rc.alpha_icw, sizeof u->alpha_icw);
    memcpy(u->color_ocw, t->rc.color_ocw, sizeof u->color_ocw);
    memcpy(u->alpha_ocw, t->rc.alpha_ocw, sizeof u->alpha_ocw);
    memcpy(u->factor0, t->rc.factor0, sizeof u->factor0);
    memcpy(u->factor1, t->rc.factor1, sizeof u->factor1);
    u->final0 = t->rc.final0; u->final1 = t->rc.final1;
    u->final_c0 = t->rc.final_c0; u->final_c1 = t->rc.final_c1;
    u->control = t->rc.control; u->stage_program = t->rc.stage_program;
    u->rc_seen = (uint32_t)t->rc_seen;
    u->fog_enable = t->fog_enable;
    /* FOG_COLOR is R in bits 0-7, the reverse of a D3DCOLOR. */
    u->fog_color[0] = (float)(t->fog_color & 0xFF) / 255.0f;
    u->fog_color[1] = (float)((t->fog_color >> 8) & 0xFF) / 255.0f;
    u->fog_color[2] = (float)((t->fog_color >> 16) & 0xFF) / 255.0f;
    u->fog_color[3] = (float)(t->fog_color >> 24) / 255.0f;
    u->fog_param[0] = t->fog_param[0]; u->fog_param[1] = t->fog_param[1];
    u->fog_param[2] = (float)t->fog_mode;
    for (k = 0; k < 4; k++) {
        u->tex_scale[k][0] = u->tex_scale[k][1] = 1.0f;
        st->addr_u[k] = st->addr_v[k] = 3;
    }
}

/* Bind the texture stages the combiners use. */
static void bind_textures(VkrDrawState *st)
{
    int k;
    for (k = 0; k < 4; k++) {
        Nv2aTexInfo ti;
        VkrTex *tex;
        double t0 = s_stats ? now_ms() : 0;
        if (!((st->u.stage_program >> (k * 5)) & 0x1F))
            continue;
        if (!nv2a_exec_tex_info(k, &ti))
            continue;
        tex = vkr_tex_find(s_vk, ti.hash);
        if (s_stats) s_t[1] += now_ms() - t0;
        if (!tex) {
            double t1 = s_stats ? now_ms() : 0;
            uint32_t *px = (uint32_t *)malloc((size_t)ti.width * ti.height * 4);
            if (px && nv2a_exec_tex_decode(k, px))
                tex = vkr_tex_create(s_vk, ti.hash, ti.width, ti.height, px);
            free(px);
            if (s_stats) { s_t[2] += now_ms() - t1; s_n[1]++; }
        }
        st->tex[k] = tex;
        st->addr_u[k] = ti.addr_u; st->addr_v[k] = ti.addr_v;
        st->linear[k] = ti.linear_filter;
        st->u.tex_scale[k][0] = ti.normalised ? 1.0f : 1.0f / (float)ti.width;
        st->u.tex_scale[k][1] = ti.normalised ? 1.0f : 1.0f / (float)ti.height;
    }
}

static int be_draw(const Nv2aTarget *t, uint32_t prim, const Nv2aVshOutput *v, uint32_t n)
{
    static uint32_t *idx;
    static uint32_t cap;
    uint32_t i, k = 0, need = n * 6;

    double td = 0;
    if (s_stats < 0) s_stats = getenv("RECOMP_VKR_STATS") != NULL;
    if (s_stats) { td = now_ms(); stats_tick(); }
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
    {
        VkrDrawState st;
        memset(&st, 0, sizeof st);
        fill_state(t, &st);
        double t2;
        bind_textures(&st);
        t2 = s_stats ? now_ms() : 0;
        vkr_draw(s_vk, (const VkrVertex *)v, n, idx, k, &st);
        if (s_stats) { s_t[3] += now_ms() - t2; s_n[0]++; }
    }
    s_dirty = 1;
    if (s_stats) s_t[0] += now_ms() - td;
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
    {
        double tf = s_stats ? now_ms() : 0;
        int ok = vkr_read_back(s_vk, s_px);
        if (s_stats) { s_t[4] += now_ms() - tf; s_n[2]++; }
        if (!ok)
            return;
    }
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
