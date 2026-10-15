#version 450

/* The NV2A vertex program, interpreted per vertex on the GPU: a port of
 * nv2a_vsh_run (toolkit nv2a_vsh_interp.c), reading the program in
 * nv2a_vsh_export's format, the 192 constants and the vertex's packed inputs
 * from the frame's upload buffer. The output is the same post-program vertex
 * xbox.vert gets from the CPU path, and leaves the same way. */

layout(std430, set = 0, binding = 5) readonly buffer F { vec4 f[]; };
layout(std430, set = 0, binding = 5) readonly buffer U { uvec4 u[]; };

layout(push_constant) uniform PC {
    vec2 inv_size;      /* 1 / render target size in pixels */
    float inv_zmax;     /* 1 / depth range */
    float fog_mode;     /* 0 = fog off, else the NV097 fog mode (0x800..0x804) */
    vec2 fog_param;
    float point_size;   /* pixels (SET_POINT_SIZE / 8) */
    float point_params; /* 1: the size is the program's oPts.x (xemu vsh.c) */
    uint in_base;       /* vec4 index of vertex 0's inputs */
    uint nin;           /* inputs per vertex */
    uint prog_base;     /* uvec4 index of the program (2 per instruction) */
    uint const_base;    /* vec4 index of c[0] */
} pc;

layout(location = 0) out vec4 v_d0;
layout(location = 1) out vec4 v_d1;
layout(location = 2) out vec4 v_fog;
layout(location = 3) out vec4 v_tex0;
layout(location = 4) out vec4 v_tex1;
layout(location = 5) out vec4 v_tex2;
layout(location = 6) out vec4 v_tex3;

float fog_factor(float d)
{
    if (pc.fog_mode == 0.0)
        return 1.0;
    float px = pc.fog_param.x, py = pc.fog_param.y, fo;
    int m = int(pc.fog_mode + 0.5);
    if (m == 0x800 || m == 0x802)
        fo = px + exp2(d * py * 16.0) - 1.5;
    else if (m == 0x801 || m == 0x803)
        fo = px + exp2(-d * d * py * py * 32.0) - 1.5;
    else
        fo = px + d * py - 1.0;
    if (m == 0x802 || m == 0x803 || m == 0x804)
        fo = abs(fo);
    if (isnan(fo))
        fo = 1.0;
    return clamp(fo, 0.0, 1.0);
}

vec4 R[13];             /* R0..R11, R12 = oPos */
vec4 O[13];             /* output registers by address */
int a0;

vec4 src(uint w, uint vbase)
{
    uint mux = w & 3u;
    vec4 s;
    if (mux == 1u)
        s = R[(w >> 2) & 15u];
    else if (mux == 2u)
        s = f[vbase + ((w >> 6) & 15u)];
    else {
        int ci = int((w >> 20) & 255u) + (((w >> 11) & 1u) != 0u ? a0 : 0);
        if (ci < 0 || ci >= 192)
            ci = 0;
        s = f[pc.const_base + uint(ci)];
    }
    s = vec4(s[(w >> 12) & 3u], s[(w >> 14) & 3u], s[(w >> 16) & 3u], s[(w >> 18) & 3u]);
    return ((w >> 10) & 1u) != 0u ? -s : s;
}

void masked(inout vec4 d, vec4 v, uint m)
{
    if ((m & 8u) != 0u) d.x = v.x;
    if ((m & 4u) != 0u) d.y = v.y;
    if ((m & 2u) != 0u) d.z = v.z;
    if ((m & 1u) != 0u) d.w = v.w;
}

vec4 mac(uint op, vec4 a, vec4 b, vec4 c)
{
    switch (op) {
    case 1u:  return a;
    case 2u:  return a * b;
    case 3u:  return a + c;
    case 4u:  return a * b + c;
    case 5u:  return vec4(dot(a.xyz, b.xyz));
    case 6u:  return vec4(dot(a.xyz, b.xyz) + b.w);
    case 7u:  return vec4(dot(a, b));
    case 8u:  return vec4(1.0, a.y * b.y, a.z, b.w);
    case 9u:  return min(a, b);
    case 10u: return vec4(a.x >= b.x ? a.x : b.x, a.y >= b.y ? a.y : b.y,
                          a.z >= b.z ? a.z : b.z, a.w >= b.w ? a.w : b.w);
    case 11u: return vec4(lessThan(a, b));
    case 12u: return vec4(greaterThanEqual(a, b));
    case 13u: a0 = int(floor(a.x + 0.001)); return a;
    }
    return a;
}

vec4 ilu(uint op, vec4 c)
{
    float x = c.x;
    switch (op) {
    case 1u: return c;
    case 2u: return vec4(x == 0.0 ? uintBitsToFloat(0x7F800000u) : 1.0 / x);
    case 3u: {
        float r = 1.0 / x;
        if (abs(r) < 5.42101e-20) r = r < 0.0 ? -5.42101e-20 : 5.42101e-20;
        if (abs(r) > 1.884467e19) r = r < 0.0 ? -1.884467e19 : 1.884467e19;
        return vec4(r);
    }
    case 4u: return vec4(inversesqrt(abs(x)));
    case 5u: {
        float fl = floor(x);
        return vec4(exp2(fl), x - fl, exp2(x), 1.0);
    }
    case 6u: {
        float ax = abs(x);
        if (ax == 0.0) {
            float ninf = uintBitsToFloat(0xFF800000u);
            return vec4(ninf, 1.0, ninf, 1.0);
        }
        float e = floor(log2(ax));
        return vec4(e, ax / exp2(e), log2(ax), 1.0);
    }
    case 7u: {
        float nl = max(c.x, 0.0), nh = max(c.y, 0.0);
        float p = clamp(c.w, -127.9961, 127.9961);
        return vec4(1.0, nl, c.x > 0.0 ? pow(nh, p) : 0.0, 1.0);
    }
    }
    return c;
}

void main()
{
    uint vbase = pc.in_base + uint(gl_VertexIndex) * pc.nin;
    for (int i = 0; i < 13; i++) {
        R[i] = vec4(0.0);
        O[i] = vec4(0.0);
    }
    O[3].w = 1.0; O[4].w = 1.0;
    O[9].w = 1.0; O[10].w = 1.0; O[11].w = 1.0; O[12].w = 1.0;
    a0 = 0;

    for (uint s = 0u; s < 136u; s++) {
        uvec4 i0 = u[pc.prog_base + 2u * s];
        uvec4 i1 = u[pc.prog_base + 2u * s + 1u];
        uint ctl = i0.x;
        uint mop = ctl & 15u, iop = (ctl >> 4) & 7u;
        uint mmask = (ctl >> 8) & 15u, imask = (ctl >> 12) & 15u;
        uint tdst = (ctl >> 16) & 15u, omask = (ctl >> 20) & 15u;
        vec4 a = src(i0.z, vbase), b = src(i0.w, vbase), c = src(i1.x, vbase);
        vec4 mr = vec4(0.0), ir = vec4(0.0);
        if (mop != 0u)
            mr = mac(mop, a, b, c);
        if (iop != 0u)
            ir = ilu(iop, c);
        if (mop != 0u && mop != 13u && mmask != 0u && tdst <= 12u)
            masked(R[tdst], mr, mmask);
        if (iop != 0u && imask != 0u) {
            /* Paired with a MAC op the ILU can only write R1. */
            uint it = mop != 0u ? 1u : tdst;
            if (it <= 12u)
                masked(R[it], ir, imask);
        }
        if (omask != 0u) {
            vec4 v = ((ctl >> 24) & 1u) != 0u ? ir : mr;
            uint oaddr = i0.y;
            if (((ctl >> 25) & 1u) != 0u) {
                if (oaddr == 0u)
                    masked(R[12], v, omask);
                else if (oaddr < 13u)
                    masked(O[oaddr], v, omask);
            }
            /* writes to c[] never reach here: those programs stay on the CPU */
        }
        if (((ctl >> 26) & 1u) != 0u)
            break;
    }

    vec4 pos = R[12];
    float w = pos.w;
    vec2 ndc = pos.xy * pc.inv_size * 2.0 - 1.0;
    gl_Position = vec4(ndc * w, pos.z * pc.inv_zmax * w, w);
    /* Vertex colours are clamped to 0..1 before interpolation (NV2A, xemu). */
    v_d0 = clamp(O[3], 0.0, 1.0); v_d1 = clamp(O[4], 0.0, 1.0);
    v_fog = vec4(fog_factor(O[5].x), 0.0, 0.0, 0.0);
    v_tex0 = O[9]; v_tex1 = O[10]; v_tex2 = O[11]; v_tex3 = O[12];
    gl_PointSize = pc.point_params > 0.5 ? max(O[6].x, 1.0) : pc.point_size;
}
