//阴影采样相关库
#ifndef CUSTOM_SHADOWS_INCLUDED
#define CUSTOM_SHADOWS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"
//如果使用的是PCF 3X3
#if defined(_DIRECTIONAL_PCF3)
//需要4个过滤器样本
#define DIRECTIONAL_FILTER_SAMPLES 4
#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
#define DIRECTIONAL_FILTER_SAMPLES 9
#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
#define DIRECTIONAL_FILTER_SAMPLES 16
#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif



#if defined(_OTHER_PCF3)
	#define OTHER_FILTER_SAMPLES 4
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_OTHER_PCF5)
	#define OTHER_FILTER_SAMPLES 9
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_OTHER_PCF7)
	#define OTHER_FILTER_SAMPLES 16
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#define MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_SHADOWED_OTHER_LIGHT_COUNT 16
#define MAX_CASCADE_COUNT 4

#define PI2 6.283185307179586

// Shadow map related variables
#define NUM_SAMPLES 16
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

//阴影图集
TEXTURE2D_SHADOW(_DirectionalShadowAtlas);
Texture2D _OtherShadowAtlas;
SamplerState sampler_OtherShadowAtlas;


#define SHADOW_SAMPLER sampler_linear_clamp_compare
SAMPLER_CMP(SHADOW_SAMPLER);

CBUFFER_START(_CustomShadows)
//级联数量和包围球数据
int _CascadeCount;
float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
//级联数据
float4 _CascadeData[MAX_CASCADE_COUNT];
//阴影转换矩阵
float4x4 _DirectionalShadowMatrices[MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];

float4x4 _OtherShadowMatrices[MAX_SHADOWED_OTHER_LIGHT_COUNT];
float4x4 _OtherShadowViewProjectionMatrices[MAX_SHADOWED_OTHER_LIGHT_COUNT];
float4 _OtherShadowTiles[MAX_SHADOWED_OTHER_LIGHT_COUNT];
//阴影过渡距离
float4 _ShadowDistanceFade;
//图集大小
float4 _ShadowAtlasSize; //x:atlasSize, y:1f / atlasSize,
//PCSS半径
float _PcssSearchRadius;
float _PcssFilterRadius;
CBUFFER_END

float2 otherAtlasSize;
float2 directionalAtlasSize;


//定向光阴影的数据信息
struct DirectionalShadowData {
	float strength;
	int tileIndex;
	//法线偏差
	float normalBias;
	int shadowMaskChannel;
};
//非定向光阴影的数据信息
struct OtherShadowData {
	float strength;
	int tileIndex;
	bool isPoint;
	int shadowMaskChannel;
	float zNear;
	float zFar;
	float right;
	float top;
	float3 positionWS;
	float3 lightPositionWS;
	float3 lightDirectionWS;
	float3 spotDirectionWS;
};
//阴影遮罩数据信息
struct ShadowMask{
	bool always;
	bool distance;
	float4 shadows;
};

//阴影数据
struct ShadowData {
	//级联索引
	int cascadeIndex;
	//是否采样阴影的标识
	float strength;
	//混合级联
	float cascadeBlend;
	//阴影遮罩
	ShadowMask shadowMask;
};

//采样阴影图集
float SampleDirectionalShadowAtlas(float3 positionSTS) {
	return SAMPLE_TEXTURE2D_SHADOW(_DirectionalShadowAtlas, SHADOW_SAMPLER, positionSTS);
}

float SampleOtherShadowAtlas (float3 positionSTS,float3 bounds) {
	positionSTS.xy = clamp(positionSTS.xy, bounds.xy, bounds.xy + bounds.z);
	return SAMPLE_TEXTURE2D_SHADOW(_OtherShadowAtlas, SHADOW_SAMPLER, positionSTS);
}



float2 poissonDisk[NUM_SAMPLES];

//泊松圆盘采样 用于PCSS
void poissonDiskSamples(const float2 randomSeed) {

	float ANGLE_STEP = PI2 * float( NUM_RINGS ) / float( NUM_SAMPLES );
	float INV_NUM_SAMPLES = 1.0 / float( NUM_SAMPLES );

	float angle = rand_2to1( randomSeed ) * PI2;
	float radius = INV_NUM_SAMPLES;
	float radiusStep = radius;

	for( int i = 0; i < NUM_SAMPLES; i ++ ) {
		poissonDisk[i] = float2( cos( angle ), sin( angle ) ) * pow( radius, 0.75 );
		radius += radiusStep;
		angle += ANGLE_STEP;
	}
}




//PCF滤波采样定向光阴影
float FilterDirectionalShadow(float3 positionSTS) {
#if defined(DIRECTIONAL_FILTER_SETUP)
	//样本权重
	float weights[DIRECTIONAL_FILTER_SAMPLES];
	//样本位置
	float2 positions[DIRECTIONAL_FILTER_SAMPLES];
	directionalAtlasSize = float2(_ShadowAtlasSize.x, 1.0 / _ShadowAtlasSize.x);
	
	float4 size = directionalAtlasSize.yyxx;
	DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
	float shadow = 0;
	for (int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++) {
		//遍历所有样本滤波得到权重和
		shadow += weights[i] * SampleDirectionalShadowAtlas(
			float3(positions[i].xy, positionSTS.z)
		);
	}
	return shadow;
#else
	return SampleDirectionalShadowAtlas(positionSTS);
#endif
}

//PCF滤波采样非定向光阴影 若开启PCSS 则根据深度选择滤波半径
float FilterOtherShadow (float3 positionSTS, float3 bounds) {
	//positionSTS 即为当前图集的UV坐标
#if defined(OTHER_FILTER_SETUP)
    //样本权重
    real weights[OTHER_FILTER_SAMPLES];
	//样本位置
	real2 positions[OTHER_FILTER_SAMPLES];
	otherAtlasSize = float2(_ShadowAtlasSize.z, 1.0 / _ShadowAtlasSize.z);
	float4 size = otherAtlasSize.yyxx;
	OTHER_FILTER_SETUP(size, positionSTS.xy, weights, positions);
	float shadow = 0;
	for (int i = 0; i < OTHER_FILTER_SAMPLES; i++) {
		//遍历所有样本滤波得到权重和
		shadow += weights[i] * SampleOtherShadowAtlas(float3(positions[i].xy, positionSTS.z), bounds);
	}
	return shadow;
#else
	return SampleOtherShadowAtlas(positionSTS, bounds);
#endif
}

float2 AverageBlockerDepth(float3 positionSTS, float curDepth, float searchWidth)
{
	float range = 3.0;
	float d_average = 0.0;
	float count = 0.0005;   // 防止 ÷ 0
	float2 uv = positionSTS.xy;
	for(int i=-range; i<=range; i++)
	{
		for(int j=-range; j<=range; j++)
		{
			float2 unitOffset = float2(i, j) / range;  // map to [-1, 1]
			float2 offset = unitOffset * searchWidth;
			float2 uvo = uv + offset;

			float d_sample = SAMPLE_TEXTURE2D(_OtherShadowAtlas, sampler_OtherShadowAtlas ,uvo).r;
			#if UNITY_REVERSED_Z
			d_sample = 1 - d_sample;
			#endif
			d_average += step(d_sample, curDepth) * d_sample;
			count += step(d_sample, curDepth);
		}
	}

	return float2(d_average / count, count);
}

float PCFWithRadius(float3 positionSTS, float curDepth, float searchWidth)
{
	float range = 3.0;
	float visibility = 0.0;
	float count = 0.0005;   // 防止 ÷ 0
	float2 uv = positionSTS.xy;
	float bias = 0.005;
	for(int i=-range; i<=range; i++)
	{
		for(int j=-range; j<=range; j++)
		{
			count += 1.0;
			float2 unitOffset = float2(i, j) / range;  // map to [-1, 1]
			float2 offset = unitOffset * searchWidth;
			float2 uvo = uv + offset;

			float d_sample = SAMPLE_TEXTURE2D(_OtherShadowAtlas, sampler_OtherShadowAtlas ,uvo).r;
			#if UNITY_REVERSED_Z
			d_sample = 1 - d_sample;
			#endif
			visibility += 1.0 - step(d_sample + bias, curDepth);
		}
	}

	return visibility / count;
}



float PCSSFilterOtherShadow (OtherShadowData other,float3 positionSTS, float3 bounds, float3 curDepth)
{
	
	//先获取平均遮挡物深度
	
	// 浮点数比较偏差
	//NDC从[-1,1]归约到[0,1]
	curDepth = curDepth * 0.5 + 0.5;
	float searchWidth = _PcssSearchRadius / abs(other.right);
	float2 blocker  = AverageBlockerDepth(positionSTS, curDepth, searchWidth);
	float avgBlockerDepth = blocker.x;
	float blockCnt = blocker.y;
	if(blockCnt<1) return 1.0;    // 没有遮挡则直接返回


	avgBlockerDepth = avgBlockerDepth * abs(other.zFar - other.zNear);
	float zReceiver = curDepth * abs(other.zFar - other.zNear);
	
	float wPenumbra  =  (zReceiver - avgBlockerDepth) * _PcssFilterRadius / avgBlockerDepth;    
	// 深度图上的 filter 半径
	float radius = wPenumbra;
	
	
	 //泊松采样 uv
	 // poissonDiskSamples(positionSTS.xy);
	 // float texStride = radius / _ShadowAtlasSize.w;   //像素在[0,1]归一化纹理上的步长
	 float texStride = radius;
	 //阴影强度
	 float shadow = 0.0;
	 float count = 0.005;
	 float mapDepth = 0.0;
	 float rotateAngle = rand_2to1(positionSTS.xy);
	 for(int i = 0; i < 64; i++) {
	 	count += 1.0;
	 	// float2 shadowMapUV = float2(poissonDisk[i].x * texStride + positionSTS.x, poissonDisk[i].y * texStride + positionSTS.y);
	 	float2 unitOffset = RotateVec2(poissonDiskWieghts64[i], rotateAngle);
	 	float2 shadowMapUV = float2(unitOffset.x * texStride + positionSTS.x, unitOffset.y * texStride + positionSTS.y);
	 	#if UNITY_REVERSED_Z 
	 	mapDepth = 1 - SAMPLE_TEXTURE2D(_OtherShadowAtlas, sampler_OtherShadowAtlas ,shadowMapUV).x;
	 	#else
	 	mapDepth = SAMPLE_TEXTURE2D(_OtherShadowAtlas, sampler_OtherShadowAtlas ,shadowMapUV).x;
	 	#endif
	 	//看的见返回 1 怎样看的见 mapDepth = curDepth
	 	shadow += step(curDepth, mapDepth);
	 	
	 }

	return shadow / count;
	
	// return PCFWithRadius(positionSTS, curDepth, radius);
	
}


static const float3 pointShadowPlanes[6] = {
	float3(-1.0, 0.0, 0.0),
	float3(1.0, 0.0, 0.0),
	float3(0.0, -1.0, 0.0),
	float3(0.0, 1.0, 0.0),
	float3(0.0, 0.0, -1.0),
	float3(0.0, 0.0, 1.0)
};


//得到非定向光的阴影强度
float GetOtherShadow (OtherShadowData other, ShadowData global, Surface surfaceWS){
	float tileIndex = other.tileIndex;
	float3 lightPlane = other.spotDirectionWS;
	if (other.isPoint) {
		float faceOffset = CubeMapFaceID(-other.lightDirectionWS);
		tileIndex += faceOffset;
		lightPlane = pointShadowPlanes[faceOffset];
	}
	float4 tileData = _OtherShadowTiles[tileIndex];
	float3 surfaceToLight = other.lightPositionWS - surfaceWS.position;
	float distanceToLightPlane = dot(surfaceToLight, lightPlane);
	float3 normalBias = surfaceWS.interpolatedNormal * (distanceToLightPlane * tileData.w);
	// float4 positionSTS = mul(_OtherShadowMatrices[tileIndex],float4(surfaceWS.position, 1.0));
	float4 positionSTS = mul(_OtherShadowMatrices[tileIndex],float4(surfaceWS.position + normalBias, 1.0));
	//透视投影，变换位置的XYZ除以Z
	float4 positionFromLight;
	#if defined(_PCSS_ON)
	//positionFromLight 我们只用了z 这一个分量 采样用的是positionSTS 是用的_OtherShadowMatrices 直接映射到对应图集的块上 且使用深度 不需要偏移
	positionFromLight = mul(_OtherShadowViewProjectionMatrices[tileIndex], float4(surfaceWS.position + normalBias, 1.0));
	return PCSSFilterOtherShadow(other, positionSTS.xyz / positionSTS.w, tileData.xyz, positionFromLight.z / positionFromLight.w);
	#else
	return FilterOtherShadow(positionSTS.xyz / positionSTS.w,tileData.xyz);
	#endif
	
}

//得到级联阴影强度
float GetCascadedShadow(DirectionalShadowData directional, ShadowData global, Surface surfaceWS) {
	//计算法线偏移
	float3 normalBias = surfaceWS.interpolatedNormal * (directional.normalBias * _CascadeData[global.cascadeIndex].y);
	//通过阴影转换矩阵和表面位置得到在阴影纹理(图块)空间的位置，然后对图集进行采样 
	float3 positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex], float4(surfaceWS.position + normalBias, 1.0)).xyz;
	float shadow = FilterDirectionalShadow(positionSTS);
	//如果级联混合小于1代表在级联层级过渡区域中，必须从下一个级联中采样并在两个值之间进行插值
	if (global.cascadeBlend < 1.0) {
		normalBias = surfaceWS.interpolatedNormal *(directional.normalBias * _CascadeData[global.cascadeIndex + 1].y);
		positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex + 1], float4(surfaceWS.position + normalBias, 1.0)).xyz;
		shadow = lerp(FilterDirectionalShadow(positionSTS), shadow, global.cascadeBlend);
	}
	return shadow;
}



//得到烘焙阴影的衰减值
float GetBakedShadow(ShadowMask mask, int channel) {
	float shadow = 1.0;
	if (mask.always || mask.distance) {
		if (channel >= 0) {
			shadow = mask.shadows[channel];
		}
	}
	return shadow;
}
float GetBakedShadow(ShadowMask mask, int channel, float strength) {
	if (mask.always || mask.distance) {
		return lerp(1.0, GetBakedShadow(mask,channel), strength);
	}
	return 1.0;
}
//混合烘焙和实时阴影
float MixBakedAndRealtimeShadows(ShadowData global, float shadow, int shadowMaskChannel, float strength)
{
	float baked = GetBakedShadow(global.shadowMask, shadowMaskChannel);
	if (global.shadowMask.always) {
		shadow = lerp(1.0, shadow, global.strength);
		shadow = min(baked, shadow);
		return lerp(1.0, shadow, strength);
	}
	if (global.shadowMask.distance) {
		shadow = lerp(baked, shadow, global.strength);
		return lerp(1.0, shadow, strength);
	}
	//最终衰减结果是阴影强度和采样衰减的线性差值
	return lerp(1.0, shadow, strength * global.strength);
}
//得到阴影衰减
float GetDirectionalShadowAttenuation(DirectionalShadowData directional, ShadowData global, Surface surfaceWS) {
	//如果材质没有定义接受阴影的宏
#if !defined(_RECEIVE_SHADOWS)
	return 1.0;
#endif
	float shadow;
	if (directional.strength * global.strength <= 0.0) {
		shadow = GetBakedShadow(global.shadowMask, directional.shadowMaskChannel, abs(directional.strength));
	}
	else 
	{
		shadow = GetCascadedShadow(directional, global, surfaceWS);
		//混合烘焙和实时阴影
		shadow = MixBakedAndRealtimeShadows(global, shadow, directional.shadowMaskChannel, directional.strength);
	}	
	
	return shadow;
}
//得到非定向光源的阴影衰减
float GetOtherShadowAttenuation(OtherShadowData other, ShadowData global, Surface surfaceWS) 
{
#if !defined(_RECEIVE_SHADOWS)
	return 1.0;
#endif

	float shadow;
	if (other.strength * global.strength <= 0.0) {
		shadow = GetBakedShadow(global.shadowMask, other.shadowMaskChannel, abs(other.strength));
	}
	else {
		shadow = GetOtherShadow(other, global, surfaceWS);
		shadow = MixBakedAndRealtimeShadows(global, shadow, other.shadowMaskChannel, other.strength);
	}
	return shadow;
}
//公式计算阴影过渡时的强度
float FadedShadowStrength (float distance, float scale, float fade) {
	return saturate((1.0 - distance * scale) * fade);
}

//得到世界空间的表面阴影数据
ShadowData GetShadowData (Surface surfaceWS) {
	ShadowData data;
	data.shadowMask.always = false;
	data.shadowMask.distance = false;
	data.shadowMask.shadows = 1.0;
	data.cascadeBlend = 1.0;
	data.strength = FadedShadowStrength(surfaceWS.depth, _ShadowDistanceFade.x, _ShadowDistanceFade.y);
	int i;
	//如果物体表面到球心的平方距离小于球体半径的平方，就说明该物体在这层级联包围球中，得到合适的级联层级索引
	for (i = 0; i < _CascadeCount; i++) {
		float4 sphere = _CascadeCullingSpheres[i];
		float distanceSqr = DistanceSquared(surfaceWS.position, sphere.xyz);
		if (distanceSqr < sphere.w) {
			//计算级联阴影的过渡强度，叠加到阴影强度上作为最终阴影强度
			float fade = FadedShadowStrength(distanceSqr, _CascadeData[i].x, _ShadowDistanceFade.z);
			//如果物体在最后一层级联中
			if (i == _CascadeCount - 1) {
				data.strength *= fade;
			}
			else {
				data.cascadeBlend = fade;
			}
			break;
		
		}
	}
	//如果超出级联层数且级联层数大于0，不进行阴影采样
	if (i == _CascadeCount && _CascadeCount > 0) {
		data.strength = 0.0;
	}
#if defined(_CASCADE_BLEND_DITHER)
	else if (data.cascadeBlend < surfaceWS.dither) {
		i += 1;
	}
#endif
#if !defined(_CASCADE_BLEND_SOFT)
	data.cascadeBlend = 1.0;
#endif
	data.cascadeIndex = i;
	return data;
}


#endif