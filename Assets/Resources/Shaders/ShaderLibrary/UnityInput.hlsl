//unity标准输入库  
#ifndef CUSTOM_UNITY_INPUT_INCLUDED  
#define CUSTOM_UNITY_INPUT_INCLUDED

CBUFFER_START(UnityPerDraw)  
//定义一个从模型空间转换到世界空间的转换矩阵  
float4x4 unity_ObjectToWorld;
//定义一个从世界空间转换到裁剪空间的矩阵  
float4x4 unity_WorldToObject; 
float4 unity_LODFade; 
//这个矩阵包含一些在这里我们不需要的转换信息  
real4 unity_WorldTransformParams;
float4 unity_ProbesOcclusion;
float4 unity_SpecCube0_HDR;  
float4 unity_LightmapST;  
float4 unity_DynamicLightmapST;

float4 unity_SHAr;  
float4 unity_SHAg;  
float4 unity_SHAb;  
float4 unity_SHBr;  
float4 unity_SHBg;  
float4 unity_SHBb;  
float4 unity_SHC;

float4 unity_ProbeVolumeParams;  
float4x4 unity_ProbeVolumeWorldToObject;  
float4 unity_ProbeVolumeSizeInv;  
float4 unity_ProbeVolumeMin;

real4 unity_LightData;  
real4 unity_LightIndices[2]; 
CBUFFER_END


float4x4 unity_MatrixVP;  
float4x4 unity_MatrixV;  
float4x4 glstate_matrix_projection;
float4x4 unity_PrevObjectToWorld;
float4x4 unity_PrevWorldToObject;

//相机位置  
float3 _WorldSpaceCameraPos;
float3 _WorldSpaceLightPos;

float4 _ScreenParams;
float4 _ZBufferParams;
float4 _ProjectionParams;

#endif