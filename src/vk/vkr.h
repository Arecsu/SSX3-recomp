/* Vulkan renderer for the NV2A executor: context, render targets, draws. */
#ifndef SSX3_VKR_H
#define SSX3_VKR_H

#include <stdint.h>

/* One vertex after the vertex program (mirrors Nv2aVshOutput). */
typedef struct {
    float pos[4];           /* x, y pixels; z depth-buffer units; w clip w */
    float d0[4], d1[4];
    float fog[4];
    float tex[4][4];
} VkrVertex;

typedef struct VkrContext VkrContext;
typedef struct VkrTex VkrTex;

/* Per-draw fixed-function state. GL enums as the NV2A takes them. */
typedef struct {
    int      depth_test, depth_write;
    uint32_t depth_func;            /* 0x200 NEVER .. 0x207 ALWAYS */
    int      blend_enable;
    uint32_t blend_src, blend_dst;  /* GL blend factors */
    uint32_t blend_eq;              /* 0x8006 ADD, 0x800A SUB, 0x800B RSUB, 0x8007 MIN, 0x8008 MAX */
    float    blend_color[4];
    uint32_t write_mask;            /* bit0 R, bit1 G, bit2 B, bit3 A */
    uint32_t alpha_func;            /* 0 = alpha test off, else 0x200..0x207 */
    uint32_t alpha_ref;             /* 0..255 */
    /* stage 0 sampler */
    uint32_t addr_u, addr_v;        /* 1 wrap 2 mirror 3 clamp 4 border 5 clamp-to-edge */
    int      linear;
    float    tex_scale[2];          /* multiplies tex0.xy to normalised coords */
} VkrDrawState;

/* Headless device (no window). Returns NULL and prints why on failure. */
VkrContext *vkr_create(void);
void vkr_destroy(VkrContext *c);

/* Colour (BGRA8) + depth target; replaces any previous one. */
int vkr_set_target(VkrContext *c, uint32_t w, uint32_t h, float zmax);
void vkr_clear(VkrContext *c, const float rgba[4], int clear_depth, float depth);
void vkr_clear_depth(VkrContext *c, float depth);

/* Textures, keyed by a content hash. pixels: w*h dwords, A8R8G8B8. */
VkrTex *vkr_tex_find(VkrContext *c, uint64_t key);
VkrTex *vkr_tex_create(VkrContext *c, uint64_t key, uint32_t w, uint32_t h,
                       const uint32_t *pixels);

/* Draw an indexed triangle list; tex may be NULL (untextured). */
int vkr_draw(VkrContext *c, const VkrVertex *v, uint32_t nverts,
             const uint32_t *idx, uint32_t nidx, const VkrDrawState *st,
             VkrTex *tex);

uint32_t vkr_width(const VkrContext *c);
uint32_t vkr_height(const VkrContext *c);

/* Submit, wait, and copy the colour target to out (w*h*4 bytes, B8G8R8A8,
 * i.e. the Xbox's little-endian A8R8G8B8). */
int vkr_read_back(VkrContext *c, uint8_t *out);

#endif
