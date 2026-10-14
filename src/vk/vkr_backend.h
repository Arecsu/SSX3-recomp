#ifndef SSX3_VKR_BACKEND_H
#define SSX3_VKR_BACKEND_H

/* Create the Vulkan context and register it with the NV2A executor.
 * Returns 0 (software rasteriser stays) if Vulkan is unavailable. */
int vkr_backend_install(void);

#endif
