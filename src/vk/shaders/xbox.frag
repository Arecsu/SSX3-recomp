#version 450

layout(location = 0) in vec4 v_d0;
layout(location = 1) in vec4 v_d1;
layout(location = 2) in vec4 v_fog;
layout(location = 3) in vec4 v_tex0;
layout(location = 4) in vec4 v_tex1;
layout(location = 5) in vec4 v_tex2;
layout(location = 6) in vec4 v_tex3;

layout(location = 0) out vec4 out_color;

/* Placeholder until the register combiners are ported: diffuse colour. */
void main()
{
    out_color = v_d0;
}
