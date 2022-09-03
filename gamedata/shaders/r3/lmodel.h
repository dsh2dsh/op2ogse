#ifndef LMODEL_H
#define LMODEL_H

#include "common.h"

////////////////////////
// Simple subsurface scattering with Half-Lambert

// Author: LVutner
// Do not copy or redistribute without permission.
float SSS(float3 N, float3 V, float3 L)
{
    const float SSS_DIST = 0.5; // Scattering distortion
    const float SSS_AMB = 0.5; // Scattering ambient

    float3 SSS_vector = L + N * SSS_DIST;
    float SSS_light = saturate(dot(V, -SSS_vector)) * 0.5 + 0.5; // Half-Lambert approx.
    return SSS_light + SSS_AMB; // Add some ambient
}

//////////////////////////////////////////////////////////////////////////////////////////
// Lighting formulas			//
//////////////////////////////////////////////////////////////////////////////////////////
// Lighting formulas
float4 compute_lighting(float3 N, float3 V, float3 L, float4 alb_gloss, float mat_id)
{
    // Half vector
    float3 H = normalize(L + V);

    // Combined light
    float4 light = s_material.Sample(smp_material, float3(dot(L, N), dot(H, N), mat_id)).xxxy;

    if (mat_id == 6.0) // Be aware of precision loss/errors
    {
        // Simple subsurface scattering
        float subsurface = SSS(N, V, L);
        light.rgb += subsurface;
    }

    return light;
}

float4 plight_infinity(float m, float3 pnt, float3 normal, float4 c_tex, float3 light_direction)
{
#if 1
    float3 N = normal; // normal
    float3 V = -normalize(pnt); // vector2eye
    float3 L = -light_direction; // vector2light
    float3 H = normalize(L + V); // float-angle-vector
    return s_material.Sample(smp_material, float3(dot(L, N), dot(H, N), m)).xxxy; // sample material
#else
    // gsc vanilla stuff
    float3 N = normalize(normal); // normal
    float3 V = -normalize(pnt); // vector2eye
    float3 L = -normalize(light_direction); // vector2light

    float4 light = compute_lighting(N, V, L, c_tex, m);

    return light; // output (albedo.gloss)
#endif
}

/*
float plight_infinity2( float m, float3 pnt, float3 normal, float3 light_direction )
{
    float3 N		= normal;							// normal
    float3 V 	= -normalize		(pnt);		// vector2eye
    float3 L 	= -light_direction;					// vector2light
    float3 H		= normalize			(L+V);			// float-angle-vector
    float3 R     = reflect         	(-V,N);
    float 	s	= saturate(dot(L,R));
            s	= saturate(dot(H,N));
    float 	f 	= saturate(dot(-V,R));
            s  *= f;
    float4	r	= tex3D 			(s_material,	float3( dot(L,N), s, m ) );	// sample material
            r.w	= pow(saturate(s),4);
    return	r	;
}
*/

float4 plight_local(float m, float3 pnt, float3 normal, float3 light_position, float light_range_rsq, out float rsqr)
{
    float3 N = normal; // normal
    float3 L2P = pnt - light_position; // light2point
    float3 V = -normalize(pnt); // vector2eye
    float3 L = -normalize((float3)L2P); // vector2light
    float3 H = normalize(L + V); // float-angle-vector
    rsqr = dot(L2P, L2P); // distance 2 light (squared)
    float att = saturate(1 - rsqr * light_range_rsq) * 2.0f / 3.0f; // q-linear attenuate
    //	float4 light	= tex3D		(s_material, float3( dot(L,N), dot(H,N), m ) ); 	// sample material
    float4 light = s_material.Sample(smp_material, float3(dot(L, N), dot(H, N), m)).xxxy; // sample material
    return att * light;
}

//	TODO: DX10: Remove path without blending
float4 blendp(float4 value, float4 tcp)
{
    //	#ifndef FP16_BLEND
    //		value 	+= (float4)tex2Dproj 	(s_accumulator, tcp); 	// emulate blend
    //	#endif
    return value;
}

float4 blend(float4 value, float2 tc)
{
    //	#ifndef FP16_BLEND
    //		value 	+= (float4)tex2D 	(s_accumulator, tc); 	// emulate blend
    //	#endif
    return value;
}

#endif