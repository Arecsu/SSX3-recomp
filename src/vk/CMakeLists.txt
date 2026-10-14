# Vulkan renderer. Standalone: `cmake -S src/vk -B build-vk && ninja -C build-vk`
# builds vkr_selftest. The game links the vkr library target.
cmake_minimum_required(VERSION 3.20)
if(NOT PROJECT_NAME)
    project(vkr C)
endif()

find_package(Vulkan REQUIRED)
find_program(GLSLC glslc REQUIRED)

set(VKR_GEN "${CMAKE_CURRENT_BINARY_DIR}/vkr_gen")
file(MAKE_DIRECTORY "${VKR_GEN}")

function(vkr_shader stage)
    set(src "${CMAKE_CURRENT_SOURCE_DIR}/shaders/xbox.${stage}")
    set(spv "${VKR_GEN}/xbox_${stage}.spv")
    set(hdr "${VKR_GEN}/xbox_${stage}_spv.h")
    add_custom_command(
        OUTPUT "${hdr}"
        COMMAND ${GLSLC} --target-env=vulkan1.3 -O -o "${spv}" "${src}"
        COMMAND ${CMAKE_COMMAND} -DIN=${spv} -DOUT=${hdr} -DNAME=xbox_${stage}_spv
                -P "${CMAKE_CURRENT_SOURCE_DIR}/embed_spv.cmake"
        DEPENDS "${src}" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spv.cmake"
        VERBATIM)
    set(VKR_HEADERS ${VKR_HEADERS} "${hdr}" PARENT_SCOPE)
endfunction()
vkr_shader(vert)
vkr_shader(frag)

add_library(vkr STATIC vkr.c ${VKR_HEADERS})
target_include_directories(vkr PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}" PRIVATE "${VKR_GEN}")
target_link_libraries(vkr PUBLIC Vulkan::Vulkan)

add_executable(vkr_selftest vkr_selftest.c)
target_link_libraries(vkr_selftest PRIVATE vkr)
