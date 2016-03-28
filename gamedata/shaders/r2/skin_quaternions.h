#ifndef	SKIN_H
#define SKIN_H

#include "common.h"

/*
	K.D.: шейдер переделан для работы с кватернионами вместо матриц.
	При скиннинге на матрицах в 214 регистров влезает 71 матрица, соответственно, 71 кость.
	При скиннинге на кватернионах - 107.
	Различие в размере шейдера: было 52 инструкции, стало 86 (моделька с бампом, вблизи). Впрочем, все инструкции - математические, карта проглотит, не заметив.
*/

struct 	v_model_skinned_0
{
	float4 	P	: POSITION;	// (float,float,float,1) - quantized	// short4
	float3	N	: NORMAL;	// normal				// DWORD
	float3	T	: TANGENT;	// tangent				// DWORD
	float3	B	: BINORMAL;	// binormal				// DWORD
	float2	tc	: TEXCOORD0;	// (u,v)				// short2
};
struct 	v_model_skinned_1   		// 24 bytes
{
	float4 	P	: POSITION;	// (float,float,float,1) - quantized	// short4
	int4	N	: NORMAL;	// (nx,ny,nz,index)			// DWORD
	float3	T	: TANGENT;	// tangent				// DWORD
	float3	B	: BINORMAL;	// binormal				// DWORD
	float2	tc	: TEXCOORD0;	// (u,v)				// short2
};
struct 	v_model_skinned_2		// 28 bytes
{
	float4 	P	: POSITION;	// (float,float,float,1) - quantized	// short4
	float4 	N	: NORMAL;	// (nx,ny,nz,weight)			// DWORD
	float3	T	: TANGENT;	// tangent				// DWORD
	float3	B	: BINORMAL;	// binormal				// DWORD
	int4 	tc	: TEXCOORD0;	// (u,v, w=m-index0, z=m-index1)  	// short4
};

//////////////////////////////////////////////////////////////////////////////////////////
uniform float4 	sbones_array	[224-10] : register(vs,c11); // массив зачем-то биндился к 22 регистру. Однако больше 10 константных регистров не используется ни в одном шейдере моделек. Аналогично почему-то кол-во константных регистров стояло 256. На PS 3.0 их 224, см. MSDN.
float3 quat_rot(float3 v, float4 q)
{
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}
float3 	skinning_dir 	(float3 dir, float4 q)
{
	return 	quat_rot(unpack_normal	(dir), q);
}
float4 	skinning_pos 	(float4 pos, float4 p, float4 q)
{
	float3 	P	= pos.xyz*(12.f / 32768.f);		// -12..+12
	float3 o = p + quat_rot(P, q);
	return float4(o.xyz, 1);
}

v_model skinning_0	(v_model_skinned_0	v)
{
	// skinning
	v_model 	o;
	o.P 		= float4(v.P.xyz*(12.f / 32768.f), 1.f);	// -12..+12
	o.N 		= unpack_normal(v.N);
	o.T 		= unpack_normal(v.T);
	o.B 		= unpack_normal(v.B);
	o.tc 		= v.tc		*(16.f / 32768.f);		// -16..+16
	return o;
}
v_model skinning_1 	(v_model_skinned_1	v)
{
	// matrices
	int 	mid 	= (int)round(v.N.w * 170);
	float4  rot 	= sbones_array[mid+0];
	float4  pos 	= sbones_array[mid+1];

	// skinning
	v_model 	o;
	o.P 		= skinning_pos(v.P, pos, rot );
	o.N 		= skinning_dir(v.N, rot );
	o.T 		= skinning_dir(v.T, rot );
	o.B 		= skinning_dir(v.B, rot );
	o.tc 		= v.tc		*(16.f / 32768.f);		// -16..+16
	return o;
}
v_model skinning_2 	(v_model_skinned_2	v)
{
	// matrices
	int 	id_0 	= (int)round(v.tc.z * 0.666666666);
	float4  rot_0 	= sbones_array[id_0+0];
	float4  pos_0 	= sbones_array[id_0+1];

	int 	id_1 	= (int)round(v.tc.w * 0.666666666);
	float4 rot_1 	= sbones_array[id_1+0];
	float4 pos_1 	= sbones_array[id_1+1];
	
	// lerp
	float 	w 	= v.N.w;

	// skinning
	v_model 	o;
	o.P 		= lerp(skinning_pos(v.P, pos_0, rot_0 ), skinning_pos(v.P, pos_1, rot_1 ), w);
	o.N 		= lerp(skinning_dir(v.N, rot_0 ), skinning_dir(v.N, rot_1 ), w);
	o.T 		= lerp(skinning_dir(v.T, rot_0 ), skinning_dir(v.T, rot_1 ), w);
	o.B 		= lerp(skinning_dir(v.B, rot_0 ), skinning_dir(v.B, rot_1 ), w);
	o.tc 		= v.tc		*(16.f / 32768.f);	// -16..+16
	return o;
}

#endif
