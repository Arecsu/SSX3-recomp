#include "vkr.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

#include "xbox_vert_spv.h"
#include "xbox_frag_spv.h"

#define VKR_BUF_BYTES (32u << 20)       /* vertex+index staging per frame */

struct VkrContext {
    VkInstance inst;
    VkPhysicalDevice phys;
    VkDevice dev;
    VkQueue queue;
    uint32_t qfam;
    VkCommandPool pool;
    VkCommandBuffer cmd;
    VkFence fence;
    VkPhysicalDeviceMemoryProperties mem;

    VkPipelineLayout layout;
    VkPipeline pipe;

    /* target */
    uint32_t w, h;
    float zmax;
    VkImage color, depth;
    VkDeviceMemory color_mem, depth_mem;
    VkImageView color_view, depth_view;
    int recording, in_pass;
    int color_valid;

    /* per-frame upload buffer */
    VkBuffer buf;
    VkDeviceMemory buf_mem;
    uint8_t *buf_map;
    uint32_t buf_used;

    /* readback */
    VkBuffer rb;
    VkDeviceMemory rb_mem;
    uint8_t *rb_map;
};

#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
    fprintf(stderr, "[VKR] %s failed: %d (%s:%d)\n", #x, (int)r_, __FILE__, __LINE__); \
    return 0; } } while (0)

static int find_mem(VkrContext *c, uint32_t bits, VkMemoryPropertyFlags want)
{
    uint32_t i;
    for (i = 0; i < c->mem.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (c->mem.memoryTypes[i].propertyFlags & want) == want)
            return (int)i;
    return -1;
}

static int make_buffer(VkrContext *c, VkDeviceSize size, VkBufferUsageFlags usage,
                       VkBuffer *b, VkDeviceMemory *m, void **map)
{
    VkBufferCreateInfo bi = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    VkMemoryRequirements mr;
    VkMemoryAllocateInfo ai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    int t;
    bi.size = size; bi.usage = usage; bi.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    CK(vkCreateBuffer(c->dev, &bi, NULL, b));
    vkGetBufferMemoryRequirements(c->dev, *b, &mr);
    t = find_mem(c, mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                                       | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (t < 0) { fprintf(stderr, "[VKR] no host-visible memory\n"); return 0; }
    ai.allocationSize = mr.size; ai.memoryTypeIndex = (uint32_t)t;
    CK(vkAllocateMemory(c->dev, &ai, NULL, m));
    CK(vkBindBufferMemory(c->dev, *b, *m, 0));
    CK(vkMapMemory(c->dev, *m, 0, VK_WHOLE_SIZE, 0, map));
    return 1;
}

static int make_image(VkrContext *c, VkFormat fmt, VkImageUsageFlags usage,
                      VkImageAspectFlags aspect, VkImage *img, VkDeviceMemory *mem,
                      VkImageView *view)
{
    VkImageCreateInfo ii = {VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    VkMemoryRequirements mr;
    VkMemoryAllocateInfo ai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    VkImageViewCreateInfo vi = {VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    int t;
    ii.imageType = VK_IMAGE_TYPE_2D; ii.format = fmt;
    ii.extent.width = c->w; ii.extent.height = c->h; ii.extent.depth = 1;
    ii.mipLevels = 1; ii.arrayLayers = 1; ii.samples = VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = VK_IMAGE_TILING_OPTIMAL; ii.usage = usage;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    CK(vkCreateImage(c->dev, &ii, NULL, img));
    vkGetImageMemoryRequirements(c->dev, *img, &mr);
    t = find_mem(c, mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (t < 0) return 0;
    ai.allocationSize = mr.size; ai.memoryTypeIndex = (uint32_t)t;
    CK(vkAllocateMemory(c->dev, &ai, NULL, mem));
    CK(vkBindImageMemory(c->dev, *img, *mem, 0));
    vi.image = *img; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = fmt;
    vi.subresourceRange.aspectMask = aspect;
    vi.subresourceRange.levelCount = 1; vi.subresourceRange.layerCount = 1;
    CK(vkCreateImageView(c->dev, &vi, NULL, view));
    return 1;
}

static void barrier(VkrContext *c, VkImage img, VkImageAspectFlags aspect,
                    VkImageLayout from, VkImageLayout to,
                    VkPipelineStageFlags2 ss, VkAccessFlags2 sa,
                    VkPipelineStageFlags2 ds, VkAccessFlags2 da)
{
    VkImageMemoryBarrier2 b = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    VkDependencyInfo d = {VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    b.srcStageMask = ss; b.srcAccessMask = sa; b.dstStageMask = ds; b.dstAccessMask = da;
    b.oldLayout = from; b.newLayout = to;
    b.srcQueueFamilyIndex = b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = img;
    b.subresourceRange.aspectMask = aspect;
    b.subresourceRange.levelCount = 1; b.subresourceRange.layerCount = 1;
    d.imageMemoryBarrierCount = 1; d.pImageMemoryBarriers = &b;
    vkCmdPipelineBarrier2(c->cmd, &d);
}

static VkShaderModule shader(VkrContext *c, const unsigned char *code, size_t n)
{
    VkShaderModuleCreateInfo si = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    VkShaderModule m = VK_NULL_HANDLE;
    si.codeSize = n; si.pCode = (const uint32_t *)code;
    if (vkCreateShaderModule(c->dev, &si, NULL, &m) != VK_SUCCESS)
        return VK_NULL_HANDLE;
    return m;
}

static int make_pipeline(VkrContext *c)
{
    VkPushConstantRange pcr = {VK_SHADER_STAGE_VERTEX_BIT, 0, 16};
    VkPipelineLayoutCreateInfo li = {VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    VkShaderModule vs = shader(c, xbox_vert_spv, xbox_vert_spv_len);
    VkShaderModule fs = shader(c, xbox_frag_spv, xbox_frag_spv_len);
    VkPipelineShaderStageCreateInfo st[2] = {
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, 0, 0, VK_SHADER_STAGE_VERTEX_BIT, 0, "main", 0},
        {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, 0, 0, VK_SHADER_STAGE_FRAGMENT_BIT, 0, "main", 0},
    };
    VkVertexInputBindingDescription bind = {0, sizeof(VkrVertex), VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription at[8];
    VkPipelineVertexInputStateCreateInfo vin = {VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    VkPipelineInputAssemblyStateCreateInfo ia = {VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    VkPipelineViewportStateCreateInfo vp = {VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    VkPipelineRasterizationStateCreateInfo rs = {VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    VkPipelineMultisampleStateCreateInfo ms = {VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    VkPipelineDepthStencilStateCreateInfo ds = {VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    VkPipelineColorBlendAttachmentState cba = {0};
    VkPipelineColorBlendStateCreateInfo cb = {VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    VkDynamicState dyn[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR,
                            VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE, VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE,
                            VK_DYNAMIC_STATE_DEPTH_COMPARE_OP};
    VkPipelineDynamicStateCreateInfo dy = {VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    VkFormat cf = VK_FORMAT_B8G8R8A8_UNORM;
    VkPipelineRenderingCreateInfo ri = {VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    VkGraphicsPipelineCreateInfo pi = {VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    uint32_t i;

    if (!vs || !fs) { fprintf(stderr, "[VKR] shader module failed\n"); return 0; }
    st[0].module = vs; st[1].module = fs;
    li.pushConstantRangeCount = 1; li.pPushConstantRanges = &pcr;
    CK(vkCreatePipelineLayout(c->dev, &li, NULL, &c->layout));
    for (i = 0; i < 8; i++) {
        at[i].location = i; at[i].binding = 0;
        at[i].format = VK_FORMAT_R32G32B32A32_SFLOAT;
        at[i].offset = i * 16;
    }
    vin.vertexBindingDescriptionCount = 1; vin.pVertexBindingDescriptions = &bind;
    vin.vertexAttributeDescriptionCount = 8; vin.pVertexAttributeDescriptions = at;
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    vp.viewportCount = 1; vp.scissorCount = 1;
    rs.polygonMode = VK_POLYGON_MODE_FILL; rs.cullMode = VK_CULL_MODE_NONE;
    rs.frontFace = VK_FRONT_FACE_CLOCKWISE; rs.lineWidth = 1.0f;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    ds.depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL;
    cba.colorWriteMask = 0xF;
    cb.attachmentCount = 1; cb.pAttachments = &cba;
    dy.dynamicStateCount = 5; dy.pDynamicStates = dyn;
    ri.colorAttachmentCount = 1; ri.pColorAttachmentFormats = &cf;
    ri.depthAttachmentFormat = VK_FORMAT_D32_SFLOAT;
    pi.pNext = &ri; pi.stageCount = 2; pi.pStages = st;
    pi.pVertexInputState = &vin; pi.pInputAssemblyState = &ia; pi.pViewportState = &vp;
    pi.pRasterizationState = &rs; pi.pMultisampleState = &ms; pi.pDepthStencilState = &ds;
    pi.pColorBlendState = &cb; pi.pDynamicState = &dy; pi.layout = c->layout;
    CK(vkCreateGraphicsPipelines(c->dev, VK_NULL_HANDLE, 1, &pi, NULL, &c->pipe));
    vkDestroyShaderModule(c->dev, vs, NULL);
    vkDestroyShaderModule(c->dev, fs, NULL);
    return 1;
}

VkrContext *vkr_create(void)
{
    VkrContext *c = (VkrContext *)calloc(1, sizeof *c);
    VkApplicationInfo app = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    VkInstanceCreateInfo ii = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    VkPhysicalDevice devs[8];
    uint32_t n = 8, i, nq = 0;
    VkQueueFamilyProperties qp[16];
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qi = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    VkPhysicalDeviceVulkan13Features f13 = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    VkDeviceCreateInfo di = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    VkCommandPoolCreateInfo pci = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    VkCommandBufferAllocateInfo cai = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    VkFenceCreateInfo fi = {VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    void *map;

    if (!c) return NULL;
    app.pApplicationName = "ssx3"; app.apiVersion = VK_API_VERSION_1_3;
    ii.pApplicationInfo = &app;
    if (vkCreateInstance(&ii, NULL, &c->inst) != VK_SUCCESS) goto fail;
    if (vkEnumeratePhysicalDevices(c->inst, &n, devs) < 0 || !n) goto fail;
    /* Prefer a real GPU over llvmpipe. */
    c->phys = devs[0];
    for (i = 0; i < n; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devs[i], &p);
        if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
            || p.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            c->phys = devs[i];
            break;
        }
    }
    {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(c->phys, &p);
        fprintf(stderr, "[VKR] device: %s (Vulkan %u.%u)\n", p.deviceName,
                VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion));
    }
    vkGetPhysicalDeviceMemoryProperties(c->phys, &c->mem);
    vkGetPhysicalDeviceQueueFamilyProperties(c->phys, &nq, NULL);
    if (nq > 16) nq = 16;
    vkGetPhysicalDeviceQueueFamilyProperties(c->phys, &nq, qp);
    for (i = 0; i < nq && !(qp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT); i++)
        ;
    if (i == nq) goto fail;
    c->qfam = i;
    qi.queueFamilyIndex = i; qi.queueCount = 1; qi.pQueuePriorities = &prio;
    f13.dynamicRendering = VK_TRUE; f13.synchronization2 = VK_TRUE;
    di.pNext = &f13; di.queueCreateInfoCount = 1; di.pQueueCreateInfos = &qi;
    if (vkCreateDevice(c->phys, &di, NULL, &c->dev) != VK_SUCCESS) goto fail;
    vkGetDeviceQueue(c->dev, c->qfam, 0, &c->queue);
    pci.queueFamilyIndex = c->qfam;
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    if (vkCreateCommandPool(c->dev, &pci, NULL, &c->pool) != VK_SUCCESS) goto fail;
    cai.commandPool = c->pool; cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cai.commandBufferCount = 1;
    if (vkAllocateCommandBuffers(c->dev, &cai, &c->cmd) != VK_SUCCESS) goto fail;
    if (vkCreateFence(c->dev, &fi, NULL, &c->fence) != VK_SUCCESS) goto fail;
    if (!make_buffer(c, VKR_BUF_BYTES, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
                     | VK_BUFFER_USAGE_INDEX_BUFFER_BIT, &c->buf, &c->buf_mem, &map))
        goto fail;
    c->buf_map = (uint8_t *)map;
    if (!make_pipeline(c)) goto fail;
    return c;
fail:
    fprintf(stderr, "[VKR] init failed\n");
    free(c);
    return NULL;
}

static void free_target(VkrContext *c)
{
    if (!c->color) return;
    vkDeviceWaitIdle(c->dev);
    vkDestroyImageView(c->dev, c->color_view, NULL);
    vkDestroyImageView(c->dev, c->depth_view, NULL);
    vkDestroyImage(c->dev, c->color, NULL);
    vkDestroyImage(c->dev, c->depth, NULL);
    vkFreeMemory(c->dev, c->color_mem, NULL);
    vkFreeMemory(c->dev, c->depth_mem, NULL);
    vkDestroyBuffer(c->dev, c->rb, NULL);
    vkFreeMemory(c->dev, c->rb_mem, NULL);
    c->color = c->depth = VK_NULL_HANDLE;
}

void vkr_destroy(VkrContext *c)
{
    if (!c) return;
    free_target(c);
    vkDestroyPipeline(c->dev, c->pipe, NULL);
    vkDestroyPipelineLayout(c->dev, c->layout, NULL);
    vkDestroyBuffer(c->dev, c->buf, NULL);
    vkFreeMemory(c->dev, c->buf_mem, NULL);
    vkDestroyFence(c->dev, c->fence, NULL);
    vkDestroyCommandPool(c->dev, c->pool, NULL);
    vkDestroyDevice(c->dev, NULL);
    vkDestroyInstance(c->inst, NULL);
    free(c);
}

int vkr_set_target(VkrContext *c, uint32_t w, uint32_t h, float zmax)
{
    void *map;
    free_target(c);
    c->w = w; c->h = h; c->zmax = zmax;
    if (!make_image(c, VK_FORMAT_B8G8R8A8_UNORM,
                    VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                    VK_IMAGE_ASPECT_COLOR_BIT, &c->color, &c->color_mem, &c->color_view))
        return 0;
    if (!make_image(c, VK_FORMAT_D32_SFLOAT, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                    VK_IMAGE_ASPECT_DEPTH_BIT, &c->depth, &c->depth_mem, &c->depth_view))
        return 0;
    if (!make_buffer(c, (VkDeviceSize)w * h * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                     &c->rb, &c->rb_mem, &map))
        return 0;
    c->rb_map = (uint8_t *)map;
    c->recording = c->in_pass = c->color_valid = 0;
    return 1;
}

static int begin_cmd(VkrContext *c)
{
    VkCommandBufferBeginInfo bi = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    if (c->recording) return 1;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    CK(vkBeginCommandBuffer(c->cmd, &bi));
    c->recording = 1;
    barrier(c, c->color, VK_IMAGE_ASPECT_COLOR_BIT,
            c->color_valid ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_UNDEFINED,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, VK_ACCESS_2_MEMORY_WRITE_BIT,
            VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    barrier(c, c->depth, VK_IMAGE_ASPECT_DEPTH_BIT,
            c->color_valid ? VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_UNDEFINED,
            VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, VK_ACCESS_2_MEMORY_WRITE_BIT,
            VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
            VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT);
    return 1;
}

static void begin_pass(VkrContext *c)
{
    VkRenderingAttachmentInfo ca = {VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    VkRenderingAttachmentInfo da = {VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    VkRenderingInfo ri = {VK_STRUCTURE_TYPE_RENDERING_INFO};
    VkViewport vp = {0, 0, (float)c->w, (float)c->h, 0.0f, 1.0f};
    VkRect2D sc = {{0, 0}, {c->w, c->h}};
    if (c->in_pass) return;
    ca.imageView = c->color_view; ca.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    ca.loadOp = c->color_valid ? VK_ATTACHMENT_LOAD_OP_LOAD : VK_ATTACHMENT_LOAD_OP_CLEAR;
    ca.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    da.imageView = c->depth_view; da.imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL;
    da.loadOp = c->color_valid ? VK_ATTACHMENT_LOAD_OP_LOAD : VK_ATTACHMENT_LOAD_OP_CLEAR;
    da.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    da.clearValue.depthStencil.depth = 1.0f;
    ri.renderArea = sc; ri.layerCount = 1;
    ri.colorAttachmentCount = 1; ri.pColorAttachments = &ca; ri.pDepthAttachment = &da;
    vkCmdBeginRendering(c->cmd, &ri);
    vkCmdBindPipeline(c->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, c->pipe);
    vkCmdSetViewport(c->cmd, 0, 1, &vp);
    vkCmdSetScissor(c->cmd, 0, 1, &sc);
    c->in_pass = 1;
    c->color_valid = 1;
}

static void end_pass(VkrContext *c)
{
    if (c->in_pass) { vkCmdEndRendering(c->cmd); c->in_pass = 0; }
}

void vkr_clear(VkrContext *c, const float rgba[4], int clear_depth, float depth)
{
    VkClearAttachment ca[2];
    VkClearRect cr = {{{0, 0}, {c->w, c->h}}, 0, 1};
    uint32_t n = 1;
    if (!begin_cmd(c)) return;
    begin_pass(c);
    ca[0].aspectMask = VK_IMAGE_ASPECT_COLOR_BIT; ca[0].colorAttachment = 0;
    memcpy(ca[0].clearValue.color.float32, rgba, 16);
    if (clear_depth) {
        ca[1].aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT; ca[1].colorAttachment = 0;
        ca[1].clearValue.depthStencil.depth = depth; ca[1].clearValue.depthStencil.stencil = 0;
        n = 2;
    }
    vkCmdClearAttachments(c->cmd, n, ca, 1, &cr);
}

void vkr_clear_depth(VkrContext *c, float depth)
{
    VkClearAttachment ca = {VK_IMAGE_ASPECT_DEPTH_BIT};
    VkClearRect cr = {{{0, 0}, {c->w, c->h}}, 0, 1};
    if (!begin_cmd(c)) return;
    begin_pass(c);
    ca.clearValue.depthStencil.depth = depth;
    vkCmdClearAttachments(c->cmd, 1, &ca, 1, &cr);
}

int vkr_draw(VkrContext *c, const VkrVertex *v, uint32_t nverts,
             const uint32_t *idx, uint32_t nidx, int depth_test, int depth_write,
             uint32_t gl_depth_func)
{
    uint32_t vb = (c->buf_used + 15) & ~15u;
    uint32_t ib = vb + nverts * (uint32_t)sizeof *v;
    uint32_t end = ib + nidx * 4;
    VkDeviceSize off = vb;
    float pc[4];
    if (end > VKR_BUF_BYTES) {
        fprintf(stderr, "[VKR] upload buffer full\n");
        return 0;
    }
    if (!begin_cmd(c)) return 0;
    begin_pass(c);
    memcpy(c->buf_map + vb, v, nverts * sizeof *v);
    memcpy(c->buf_map + ib, idx, nidx * 4);
    c->buf_used = end;
    pc[0] = 1.0f / (float)c->w; pc[1] = 1.0f / (float)c->h;
    pc[2] = 1.0f / c->zmax; pc[3] = 0.0f;
    vkCmdPushConstants(c->cmd, c->layout, VK_SHADER_STAGE_VERTEX_BIT, 0, 16, pc);
    vkCmdSetDepthTestEnable(c->cmd, depth_test ? VK_TRUE : VK_FALSE);
    vkCmdSetDepthWriteEnable(c->cmd, depth_write ? VK_TRUE : VK_FALSE);
    vkCmdSetDepthCompareOp(c->cmd, gl_depth_func >= 0x200 && gl_depth_func <= 0x207
                                       ? (VkCompareOp)(gl_depth_func - 0x200)
                                       : VK_COMPARE_OP_LESS_OR_EQUAL);
    vkCmdBindVertexBuffers(c->cmd, 0, 1, &c->buf, &off);
    vkCmdBindIndexBuffer(c->cmd, c->buf, ib, VK_INDEX_TYPE_UINT32);
    vkCmdDrawIndexed(c->cmd, nidx, 1, 0, 0, 0);
    return 1;
}

uint32_t vkr_width(const VkrContext *c) { return c->w; }
uint32_t vkr_height(const VkrContext *c) { return c->h; }

int vkr_read_back(VkrContext *c, uint8_t *out)
{
    VkBufferImageCopy cp = {0};
    VkSubmitInfo si = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
    if (!begin_cmd(c)) return 0;
    end_pass(c);
    barrier(c, c->color, VK_IMAGE_ASPECT_COLOR_BIT,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            VK_PIPELINE_STAGE_2_TRANSFER_BIT, VK_ACCESS_2_TRANSFER_READ_BIT);
    cp.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    cp.imageSubresource.layerCount = 1;
    cp.imageExtent.width = c->w; cp.imageExtent.height = c->h; cp.imageExtent.depth = 1;
    vkCmdCopyImageToBuffer(c->cmd, c->color, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, c->rb, 1, &cp);
    barrier(c, c->color, VK_IMAGE_ASPECT_COLOR_BIT,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            VK_PIPELINE_STAGE_2_TRANSFER_BIT, VK_ACCESS_2_TRANSFER_READ_BIT,
            VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    CK(vkEndCommandBuffer(c->cmd));
    c->recording = 0;
    si.commandBufferCount = 1; si.pCommandBuffers = &c->cmd;
    CK(vkQueueSubmit(c->queue, 1, &si, c->fence));
    CK(vkWaitForFences(c->dev, 1, &c->fence, VK_TRUE, UINT64_MAX));
    CK(vkResetFences(c->dev, 1, &c->fence));
    CK(vkResetCommandBuffer(c->cmd, 0));
    memcpy(out, c->rb_map, (size_t)c->w * c->h * 4);
    c->buf_used = 0;
    return 1;
}
