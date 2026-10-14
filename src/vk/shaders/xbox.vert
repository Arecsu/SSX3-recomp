#version 450

/* Post-vertex-program vertex: the Xbox runtime appends the viewport transform
 * to every program, so pos is already in pixels (x, y), depth-buffer units
 * (z) and clip-space w. Re-expand it to clip space so the GPU clips and
 * interpolates perspective-correctly. */
layout(location = 0) in vec4 in_pos;
layout(location = 1) in vec4 in_d0;
layout(location = 2) in vec4 in_d1;
layout(location = 3) in vec4 in_fog;
layout(location = 4) in vec4 in_tex0;
layout(location = 5) in vec4 in_tex1;
layout(location = 6) in vec4 in_tex2;
layout(location = 7) in vec4 in_tex3;

layout(push_constant) uniform PC {
    vec2 inv_size;      /* 1 / render target size in pixels */
    float inv_zmax;     /* 1 / depth range: 0xFFFFFF (Z24) or 0xFFFF (Z16) */
    float pad;
} pc;

layout(location = 0) out vec4 v_d0;
layout(location = 1) out vec4 v_d1;
layout(location = 2) out vec4 v_fog;
layout(location = 3) out vec4 v_tex0;
layout(location = 4) out vec4 v_tex1;
layout(location = 5) out vec4 v_tex2;
layout(location = 6) out vec4 v_tex3;

void main()
{
    float w = in_pos.w;
    vec2 ndc = in_pos.xy * pc.inv_size * 2.0 - 1.0;
    gl_Position = vec4(ndc * w, in_pos.z * pc.inv_zmax * w, w);
    v_d0 = in_d0; v_d1 = in_d1; v_fog = in_fog;
    v_tex0 = in_tex0; v_tex1 = in_tex1; v_tex2 = in_tex2; v_tex3 = in_tex3;
}
