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
    float fog_mode;     /* 0 = fog off, else the NV097 fog mode (0x800..0x804) */
    vec2 fog_param;
} pc;

layout(location = 0) out vec4 v_d0;
layout(location = 1) out vec4 v_d1;
layout(location = 2) out vec4 v_fog;
layout(location = 3) out vec4 v_tex0;
layout(location = 4) out vec4 v_tex1;
layout(location = 5) out vec4 v_tex2;
layout(location = 6) out vec4 v_tex3;

/* The fixed-function fog unit from the program's oFog.x (xemu vsh.c);
 * fog off reads as factor 1. */
float fog_factor(float d)
{
    if (pc.fog_mode == 0.0)
        return 1.0;
    float px = pc.fog_param.x, py = pc.fog_param.y, f;
    int m = int(pc.fog_mode + 0.5);
    if (m == 0x800 || m == 0x802)
        f = px + exp2(d * py * 16.0) - 1.5;
    else if (m == 0x801 || m == 0x803)
        f = px + exp2(-d * d * py * py * 32.0) - 1.5;
    else
        f = px + d * py - 1.0;
    if (m == 0x802 || m == 0x803 || m == 0x804)
        f = abs(f);
    if (isnan(f))
        f = 1.0;
    return clamp(f, 0.0, 1.0);
}

void main()
{
    float w = in_pos.w;
    vec2 ndc = in_pos.xy * pc.inv_size * 2.0 - 1.0;
    gl_Position = vec4(ndc * w, in_pos.z * pc.inv_zmax * w, w);
    v_d0 = in_d0; v_d1 = in_d1;
    v_fog = vec4(fog_factor(in_fog.x), 0.0, 0.0, 0.0);
    v_tex0 = in_tex0; v_tex1 = in_tex1; v_tex2 = in_tex2; v_tex3 = in_tex3;
}
