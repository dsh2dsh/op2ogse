#ifndef HMODEL_H
#define HMODEL_H

#include "common.h"

TextureCube env_s0;
TextureCube env_s1;

uniform float4 env_color; // color.w  = lerp factor
uniform float3x4 m_v2w;

float3 SmallSkyCompute(float3 uv)
{
    float3 color = float3(0.0, 0.0, 0.0);

    static const int3 o[8] = {{-1, 0, 0}, {1, 0, 0}, {0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {1, 1, 1}, {0, 0, 0}};

    static const int num = 8;

    for (int i = 0; i < num; i++)
    {
        float3 tap = normalize(uv + o[i] * SMALLSKY_BLUR_INTENSITY);
        float3 env0 = env_s0.SampleLevel(smp_rtlinear, tap, 0);
        float3 env1 = env_s1.SampleLevel(smp_rtlinear, tap, 0);
        color += lerp(env0, env1, env_color.w) / num;
    }

    float top_to_down_vec = saturate(uv.y);
    top_to_down_vec *= top_to_down_vec;

    static const float factor = SMALLSKY_TOP_VECTOR_POWER;
    color *= saturate(factor + (1.0 - factor) * top_to_down_vec) + (1.0 - factor) / 2;

    return color;

    // float3 s0 = env_s0.SampleLevel(smp_rtlinear, uv, 0);
    // float3 s1 = env_s1.SampleLevel(smp_rtlinear, uv, 0);
    // return lerp(s0, s1, env_color.w);
}

void hmodel(out float3 hdiffuse, out float3 hspecular, float m, float h, float s, float3 Pnt, float3 normal)
{
    // hscale - something like diffuse reflection
    float3 nw = mul(m_v2w, normal);
    float hscale = h;

    // reflection vector
    float3 v2PntL = normalize(Pnt);
    float3 v2Pnt = mul(m_v2w, v2PntL);
    float3 vreflect = reflect(v2Pnt, nw);
    float hspec = .5h + .5h * dot(vreflect, v2Pnt);

    // material	// sample material
    float4 light = s_material.SampleLevel(smp_material, float3(hscale, hspec, m), 0).xxxy;

    // diffuse color
    float3 env_d = SmallSkyCompute(nw) * env_color.rgb;
    env_d *= env_d; // contrast

    hdiffuse = env_d * light.xyz + L_ambient.rgb;

    // specular color
    vreflect.y = vreflect.y * 2 - 1; // fake remapping

    float3 env_s = SmallSkyCompute(vreflect) * env_color.rgb;
    env_s *= env_s; // contrast

    hspecular = env_s * light.w * s;
}

#endif