#version 450

layout(location = 0) in vec4 v_d0;
layout(location = 1) in vec4 v_d1;
layout(location = 2) in vec4 v_fog;
layout(location = 3) in vec4 v_tex0;
layout(location = 4) in vec4 v_tex1;
layout(location = 5) in vec4 v_tex2;
layout(location = 6) in vec4 v_tex3;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D tex0;

layout(push_constant) uniform PC {
    layout(offset = 16) vec2 tex_scale;   /* (1,1) normalised, 1/size for texel coords */
    uint alpha_func;                      /* 0 = test off, else GL func 0x200..0x207 */
    uint alpha_ref;                       /* 0..255 */
    uint textured;
} pc;

/* Placeholder for the register combiners (milestone 5): stage 0 texture
 * modulated by the diffuse colour. */
void main()
{
    vec4 c = v_d0;
    if (pc.textured != 0u)
        c *= texture(tex0, v_tex0.xy * pc.tex_scale);

    if (pc.alpha_func != 0u) {
        float a = round(c.a * 255.0), r = float(pc.alpha_ref);
        bool pass;
        switch (pc.alpha_func) {
        case 0x200u: pass = false; break;
        case 0x201u: pass = a < r; break;
        case 0x202u: pass = a == r; break;
        case 0x203u: pass = a <= r; break;
        case 0x204u: pass = a > r; break;
        case 0x205u: pass = a != r; break;
        case 0x206u: pass = a >= r; break;
        default:     pass = true; break;
        }
        if (!pass)
            discard;
    }
    out_color = c;
}
