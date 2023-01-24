#ifndef LMODEL_H
#define LMODEL_H

#include "common.h"

//////////////////////////////////////////////////////////////////////////////////////////
// Lighting formulas
float4 compute_lighting(float3 N, float3 V, float3 L, float4 alb_gloss, float mat_id)
{
	//Half vector
  	float3 H = normalize(L+V);
	
	//Combined light
	float4 light = s_material.Sample(smp_material, float3( dot(L,N), dot(H,N), mat_id)).xxxy;
	
	if(mat_id == MAT_FLORA) //Be aware of precision loss/errors
	{
		//Simple subsurface scattering
		float subsurface = SSS(N,V,L);
		light.rgb += subsurface;
	}	

	return light;
}

float4 plight_infinity( float m, float3 pnt, float3 normal, float4 c_tex, float3 light_direction )
{
	//gsc vanilla stuff
	float3 N = normalize(normal);							// normal 
  	float3 V = -normalize(pnt);					// vector2eye
  	float3 L = -normalize(light_direction);						// vector2light

	float4 light = compute_lighting(N,V,L,c_tex,m);
	
	return light; // output (albedo.gloss)
}

float4 plight_local( float m, float3 pnt, float3 normal, float4 c_tex, float3 light_position, float light_range_rsq, out float rsqr )
{
	float3 N		= normalize(normal);							// normal 
	float3 L2P 	= pnt - light_position;                         		// light2point 
	float3 V 		= -normalize	(pnt);					// vector2eye
	float3 L 		= -normalize	((float3)L2P);					// vector2light
	float3 H		= normalize	(L+V);						// half-angle-vector
		rsqr	= dot		(L2P,L2P);					// distance 2 light (squared)
	float  att 	= saturate	(1 - rsqr*light_range_rsq);			// q-linear attenuate

	float4 light = compute_lighting(N,V,L,c_tex,m);
	
	return att*light;		// output (albedo.gloss)
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
