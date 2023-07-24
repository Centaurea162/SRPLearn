//受光着色器公用属性和方法库
#ifndef CUSTOM_LIT_INPUT_INCLUDED
#define CUSTOM_LIT_INPUT_INCLUDED

TEXTURE2D(_EmissionMap);
TEXTURE2D(_BaseMap);
TEXTURE2D(_OcclusionMap);
TEXTURE2D(_MetallicMap);
TEXTURE2D(_RoughnessMap);
SAMPLER(sampler_BaseMap);

TEXTURE2D(_NormalMap);
SAMPLER(sampler_NormalMap);



UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
UNITY_DEFINE_INSTANCED_PROP(float4, _EmissionColor)
UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)
UNITY_DEFINE_INSTANCED_PROP(float, _ZWrite)
UNITY_DEFINE_INSTANCED_PROP(float, _Metallic)
UNITY_DEFINE_INSTANCED_PROP(float, _Smoothness)
UNITY_DEFINE_INSTANCED_PROP(float, _Fresnel)  


UNITY_DEFINE_INSTANCED_PROP(float, _NormalScale)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

#define INPUT_PROP(name) UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, name)
//输入配置
struct InputConfig {
	float2 baseUV;
	bool useOcclusion;
};
//获取输入配置
InputConfig GetInputConfig(float2 baseUV) {
	InputConfig c;
	c.baseUV = baseUV;
	c.useOcclusion = false;
	return c;
}
//基础纹理UV转换
float2 TransformBaseUV(float2 baseUV) {
	float4 baseST = INPUT_PROP(_BaseMap_ST);
	return baseUV * baseST.xy + baseST.zw;
}



//获取遮罩纹理的采样数据
float GetOcclusion (InputConfig c) {
	if (c.useOcclusion) {
		return SAMPLE_TEXTURE2D(_OcclusionMap, sampler_BaseMap, c.baseUV).r;
	}
	return 1.0;
}
//采样法线并解码法线向量得到原法线方向
float3 GetNormalTS (InputConfig c) {
	float4 map = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, c.baseUV);
	float scale = INPUT_PROP(_NormalScale);
	float3 normal = DecodeNormal(map, scale);

	return normal;
}
//获取基础纹理的采样数据
float4 GetBase(InputConfig c) {
	float4 map = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, c.baseUV);
	float4 color = INPUT_PROP( _BaseColor);

	return map * color;
}


float GetCutoff(InputConfig c) {
	return INPUT_PROP(_Cutoff);
}


float GetMetallic(InputConfig c) {
	float metallic = INPUT_PROP(_Metallic);
	#if defined(_METALLIC_MAP)
	metallic *= SAMPLE_TEXTURE2D(_MetallicMap, sampler_BaseMap, c.baseUV).r;
	#endif
	return metallic;
}

float GetSmoothness(InputConfig c) {
	float smoothness = INPUT_PROP(_Smoothness);
	#if defined(_ROUGHNESS_MAP)
	smoothness *= (1 - SAMPLE_TEXTURE2D(_RoughnessMap, sampler_BaseMap, c.baseUV).r);
	#elif defined(_SMOOTHNESS_MAP)
	smoothness *= SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_BaseMap, c.baseUV).r;
	#endif
	
	return smoothness;
}

float GetFresnel (InputConfig c)   
{  
	float fresnelStrength = INPUT_PROP(_Fresnel);
	return fresnelStrength;
}

//获取自发光纹理的采样数据
float3 GetEmission (InputConfig c) {
	float4 map = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, c.baseUV);
	float4 color = INPUT_PROP(_EmissionColor);
	return map.rgb * color.rgb;
}

float GetFinalAlpha(float alpha) {
	
	return INPUT_PROP(_ZWrite) ? 1.0 : alpha;
}


#endif
