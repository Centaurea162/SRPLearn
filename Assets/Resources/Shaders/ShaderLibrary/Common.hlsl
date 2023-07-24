// 公共方法库  
#ifndef CUSTOM_COMMON_INCLUDED  
#define CUSTOM_COMMON_INCLUDED
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
//使用UnityInput里面的转换矩阵前先include进来  
#include "UnityInput.hlsl"

//定义一些宏取代常用的转换矩阵  
#define UNITY_MATRIX_M unity_ObjectToWorld  
#define UNITY_MATRIX_I_M unity_WorldToObject  
#define UNITY_MATRIX_V unity_MatrixV  
#define UNITY_MATRIX_VP unity_MatrixVP  
#define UNITY_MATRIX_P glstate_matrix_projection
#define UNITY_PREV_MATRIX_M unity_PrevObjectToWorld
#define UNITY_PREV_MATRIX_I_M unity_PrevWorldToObject

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"  
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"  
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

#if defined(_SHADOW_MASK_ALWAYS) || defined(_SHADOW_MASK_DISTANCE)  
   #define SHADOWS_SHADOWMASK  
#endif 

#include   "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"


float Square (float v)   
{  
    return v * v;  
}

//计算两点间距离的平方  
float DistanceSquared(float3 pA, float3 pB)   
{  
    return dot(pA - pB, pA - pB);  
}

void ClipLOD (float2 positionCS, float fade)   
{  
    #if defined(LOD_FADE_CROSSFADE)
    //在垂直方向进行渐变
    float dither = InterleavedGradientNoise(positionCS.xy, 0);  
    clip(fade + (fade < 0.0 ? dither : -dither)); 
    #endif  
}

//解码法线数据，得到原来的法线向量  
float3 DecodeNormal (float4 sample, float scale)   
{  
    #if defined(UNITY_NO_DXT5nm)  
    return UnpackNormalRGB(sample, scale);  
    #else  
    return UnpackNormalmapRGorAG(sample, scale);  
    #endif  
}

//将法线从切线空间转换到世界空间  
float3 NormalTangentToWorld (float3 normalTS, float3 normalWS, float4 tangentWS)   
{  
    //构建切线到世界空间的转换矩阵，需要世界空间的法线、世界空间的切线的XYZ和W分量  
    float3x3 tangentToWorld = CreateTangentToWorld(normalWS, tangentWS.xyz, tangentWS.w);  
    return TransformTangentToWorld(normalTS, tangentToWorld);  
}

//随机数 用于泊松圆盘采样
float rand_2to1(float2 uv) { 
    // 0 - 1
    const float a = 12.9898, b = 78.233, c = 43758.5453;
    float dt = dot( uv.xy, float2( a,b ) ), sn = fmod( dt, PI );
    return frac(sin(sn) * c);
}

//旋转向量 用于泊松圆盘采样
float2 RotateVec2(float2 v, float angle)
{
    float s = sin(angle);
    float c = cos(angle);

    return float2(v.x*c+v.y*s, -v.x*s+v.y*c);
}

//或者直接使用现成的权重
static float2 poissonDiskWieghts16[16] = {
	float2( -0.94201624, -0.39906216 ),
	float2( 0.94558609, -0.76890725 ),
	float2( -0.094184101, -0.92938870 ),
	float2( 0.34495938, 0.29387760 ),
	float2( -0.91588581, 0.45771432 ),
	float2( -0.81544232, -0.87912464 ),
	float2( -0.38277543, 0.27676845 ),
	float2( 0.97484398, 0.75648379 ),
	float2( 0.44323325, -0.97511554 ),
	float2( 0.53742981, -0.47373420 ),
	float2( -0.26496911, -0.41893023 ),
	float2( 0.79197514, 0.19090188 ),
	float2( -0.24188840, 0.99706507 ),
	float2( -0.81409955, 0.91437590 ),
	float2( 0.19984126, 0.78641367 ),
	float2( 0.14383161, -0.14100790 )
};

static float2 poissonDiskWieghts64[64] = {
    float2(-0.5119625f, -0.4827938f),
    float2(-0.2171264f, -0.4768726f),
    float2(-0.7552931f, -0.2426507f),
    float2(-0.7136765f, -0.4496614f),
    float2(-0.5938849f, -0.6895654f),
    float2(-0.3148003f, -0.7047654f),
    float2(-0.42215f, -0.2024607f),
    float2(-0.9466816f, -0.2014508f),
    float2(-0.8409063f, -0.03465778f),
    float2(-0.6517572f, -0.07476326f),
    float2(-0.1041822f, -0.02521214f),
    float2(-0.3042712f, -0.02195431f),
    float2(-0.5082307f, 0.1079806f),
    float2(-0.08429877f, -0.2316298f),
    float2(-0.9879128f, 0.1113683f),
    float2(-0.3859636f, 0.3363545f),
    float2(-0.1925334f, 0.1787288f),
    float2(0.003256182f, 0.138135f),
    float2(-0.8706837f, 0.3010679f),
    float2(-0.6982038f, 0.1904326f),
    float2(0.1975043f, 0.2221317f),
    float2(0.1507788f, 0.4204168f),
    float2(0.3514056f, 0.09865579f),
    float2(0.1558783f, -0.08460935f),
    float2(-0.0684978f, 0.4461993f),
    float2(0.3780522f, 0.3478679f),
    float2(0.3956799f, -0.1469177f),
    float2(0.5838975f, 0.1054943f),
    float2(0.6155105f, 0.3245716f),
    float2(0.3928624f, -0.4417621f),
    float2(0.1749884f, -0.4202175f),
    float2(0.6813727f, -0.2424808f),
    float2(-0.6707711f, 0.4912741f),
    float2(0.0005130528f, -0.8058334f),
    float2(0.02703013f, -0.6010728f),
    float2(-0.1658188f, -0.9695674f),
    float2(0.4060591f, -0.7100726f),
    float2(0.7713396f, -0.4713659f),
    float2(0.573212f, -0.51544f),
    float2(-0.3448896f, -0.9046497f),
    float2(0.1268544f, -0.9874692f),
    float2(0.7418533f, -0.6667366f),
    float2(0.3492522f, 0.5924662f),
    float2(0.5679897f, 0.5343465f),
    float2(0.5663417f, 0.7708698f),
    float2(0.7375497f, 0.6691415f),
    float2(0.2271994f, -0.6163502f),
    float2(0.2312844f, 0.8725659f),
    float2(0.4216993f, 0.9002838f),
    float2(0.4262091f, -0.9013284f),
    float2(0.2001408f, -0.808381f),
    float2(0.149394f, 0.6650763f),
    float2(-0.09640376f, 0.9843736f),
    float2(0.7682328f, -0.07273844f),
    float2(0.04146584f, 0.8313184f),
    float2(0.9705266f, -0.1143304f),
    float2(0.9670017f, 0.1293385f),
    float2(0.9015037f, -0.3306949f),
    float2(-0.5085648f, 0.7534177f),
    float2(0.9055501f, 0.3758393f),
    float2(0.7599946f, 0.1809109f),
    float2(-0.2483695f, 0.7942952f),
    float2(-0.4241052f, 0.5581087f),
    float2(-0.1020106f, 0.6724468f)
};

#endif