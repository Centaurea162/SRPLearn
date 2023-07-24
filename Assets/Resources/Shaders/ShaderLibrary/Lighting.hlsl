//计算光照相关库  
#ifndef CUSTOM_LIGHTING_INCLUDED  
#define CUSTOM_LIGHTING_INCLUDED

#include "./ShaderLibrary/DeferredParams.hlsl"

StructuredBuffer<uint> _TileLightsArgsBuffer;
StructuredBuffer<uint> _TileLightsIndicesBuffer;

float4 _LitDeferredTileParams;

//计算入射光照
float3 IncomingLight (Surface surface, Light light) {
    return saturate(light.attenuation) * light.color;
}
//入射光乘以光照照射到表面的直接照明颜色,得到最终的照明颜色
float3 GetLighting (Surface surface, BRDF brdf, Light light) {
    return IncomingLight(surface, light) * DirectBRDF(surface, light);
}

//获取最终照明结果  
float3 GetLighting(Surface surfaceWS, BRDF brdf,  GI gi)   
{
    
    //得到表面阴影数据  
    ShadowData shadowData = GetShadowData(surfaceWS);
    shadowData.shadowMask = gi.shadowMask;
    
    float3 color = IndirectBRDF(surfaceWS, brdf, gi.diffuse, gi.specular);
    for (int i = 0; i < GetDirectionalLightCount(); i++)
    {
        Light light = GetDirectionalLight(i, surfaceWS, shadowData);
        color += GetLighting(surfaceWS, brdf, light);
    }


    
    #if defined(_TILE_BASED_LIGHT_CULLING)
    uint2 tileId = floor(surfaceWS.screenPos / _LitDeferredTileParams.xy);
    uint tileIndex = tileId.y * _LitDeferredTileParams.z + tileId.x;
    uint lightCount = _TileLightsArgsBuffer[tileIndex];;
    for (uint j = 0; j < lightCount; j++)   
    {
        uint index = _TileLightsIndicesBuffer[tileIndex * MAX_LIGHT_COUNT_PER_TILE + j];
        if(index != MAX_LIGHT_COUNT + 1)
        {
            Light light = GetOtherLight(index, surfaceWS, shadowData);  
            color += GetLighting(surfaceWS, brdf, light);  
        }
    }  
    #elif defined(_LIGHTS_PER_OBJECT)
    for (int j = 0; j < min(unity_LightData.y, 8); j++)   
    {  
        int lightIndex = unity_LightIndices[(uint)j / 4][(uint)j % 4];  
        Light light = GetOtherLight(lightIndex, surfaceWS, shadowData);  
        color += GetLighting(surfaceWS, brdf, light);  
    }
    #else  
    for (int j = 0; j < GetOtherLightCount(); j++)   
    {  
        Light light = GetOtherLight(j, surfaceWS, shadowData);  
        color += GetLighting(surfaceWS, brdf, light);  
    }  
    #endif  
    return color;  

    
}

#endif