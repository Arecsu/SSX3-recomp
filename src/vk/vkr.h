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

/* Headless device (no window). Returns NULL and prints why on failure. */
VkrContext *vkr_create(void);
void vkr_destroy(VkrContext *c);

/* Colour (RGBA8) + depth target; replaces any previous one. */
int vkr_set_target(VkrContext *c, uint32_t w, uint32_t h, float zmax);
void vkr_clear(VkrContext *c, const float rgba[4], int clear_depth, float depth);

/* Draw an indexed triangle list. */
/* gl_depth_func: GL enum (0x200 NEVER .. 0x207 ALWAYS), as the NV2A takes it. */
void vkr_clear_depth(VkrContext *c, float depth);

int vkr_draw(VkrContext *c, const VkrVertex *v, uint32_t nverts,
             const uint32_t *idx, uint32_t nidx, int depth_test, int depth_write,
             uint32_t gl_depth_func);

uint32_t vkr_width(const VkrContext *c);
uint32_t vkr_height(const VkrContext *c);

/* Submit, wait, and copy the colour target to out (w*h*4 bytes, B8G8R8A8,
 * i.e. the Xbox's little-endian A8R8G8B8). */
int vkr_read_back(VkrContext *c, uint8_t *out);

#endif
