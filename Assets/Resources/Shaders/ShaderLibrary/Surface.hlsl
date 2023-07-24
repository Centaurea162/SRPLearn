#ifndef CUSTOM_SURFACE_INCLUDED  
#define CUSTOM_SURFACE_INCLUDED

struct Surface
{
    float3 normal;
    float3 color;
    float alpha;
    float metallic;  
    float smoothness;
    float2 screenPos;

    
    float3 viewDirection;
    //表面位置  
    float3 position;
    //表面深度  
    float depth;
    float dither;
    //菲涅尔反射强度  
    float fresnelStrength;

    float3 interpolatedNormal;
    //遮挡数据  
    float occlusion;  
};

#endif