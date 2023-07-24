#ifndef CUSTOM_DEFERREDLIT_PASS_INCLUDED
#define CUSTOM_DEFERREDLIT_PASS_INCLUDED

#define _RECEIVE_SHADOWS 1

#include "./ShaderLibrary/Surface.hlsl"
#include "./ShaderLibrary/Shadows.hlsl"


#include "./ShaderLibrary/Light.hlsl"
#include "./ShaderLibrary/BRDF.hlsl"
#include "./ShaderLibrary/GI.hlsl" 
#include "./ShaderLibrary/Lighting.hlsl"

//顶点函数输入结构体
struct Attributes {
    float3 positionOS : POSITION;
    float2 baseUV : TEXCOORD0;
};
//片元函数输入结构体
struct Varyings {
    float4 positionCS : SV_POSITION;
    float2 baseUV : VAR_BASE_UV;
};


sampler2D _gdepth;
sampler2D _GBuffer0;
sampler2D _GBuffer1;
sampler2D _GBuffer2;
sampler2D _GBuffer3;


CBUFFER_START(GBuffer)
// float4x4 _vpMatrix;
// float4x4 _vpMatrixInv;
float4 _zBufferParam;
CBUFFER_END


//顶点函数
Varyings DeferredLitVertex(Attributes input){
    Varyings output;
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    //计算缩放和偏移后的UV坐标
    output.baseUV = input.baseUV;
    return output;
}


//片元函数
float4 DeferredLitFragment (Varyings input, out float depthOut : SV_Depth) : SV_TARGET {
    Surface surface;
    //采样GBuffer
    surface.color = tex2D(_GBuffer0, input.baseUV).rgb;
    surface.alpha = 1.0;
    surface.normal = tex2D(_GBuffer1, input.baseUV).rgb * 2 - 1;
    surface.interpolatedNormal = surface.normal;
    float3 GBuffer2 = tex2D(_GBuffer2, input.baseUV).rgb;
    surface.smoothness = 1 - GBuffer2.r;
    surface.metallic = GBuffer2.g;
    surface.occlusion = GBuffer2.b;
    
    float3 emission = tex2D(_GBuffer3, input.baseUV).rgb;
    // surfaceWS.color *= emission;
    surface.fresnelStrength = 1.0;
    float depth = tex2D(_gdepth, input.baseUV).r;
    depthOut = depth;
    
    
    // 反投影重建世界坐标
    float4 ndcPos  = float4(input.baseUV * 2 - 1, depth, 1.0);
    float4 positionWS = mul(_vpMatrixInv, ndcPos);
    positionWS /= positionWS.w;
    // depthOut = positionWS.z / (far - near);
    surface.depth = positionWS.z;
    surface.position = positionWS.xyz;
    
    surface.viewDirection = normalize(_WorldSpaceCameraPos - surface.position);
    surface.fresnelStrength = 0.5;
    //计算抖动值
    surface.dither = InterleavedGradientNoise(input.positionCS.xy, 0);

    //计算对应分块索引
    surface.screenPos = _ScreenParams.xy * input.baseUV;
    
    
    // *no shadow*
    // Light light;
    // light.color = float3(1.0, 1.0, 1.0);
    // light.attenuation = 1.0;
    // light.direction = normalize(float3(1.0, 0.1, 0.1));
    //
    // GI gi;
    // gi.shadowMask.always = false;  
    // gi.shadowMask.distance = false;  
    // gi.shadowMask.shadows = 1.0;
    //
    // float3 color = DirectBRDF(surface, light);
    // gi = IBL(surface, gi);
    // color += (gi.diffuse + gi.specular) * surface.occlusion;
    //
    // // uint2 tileId = uint2(surface.screenPos.x / THREAD_NUM_X, surface.screenPos.y / THREAD_NUM_Y);
    // // int tileIndex = tileId.y * _LitDeferredTileParams.z + tileId.x;
    // uint sum = 0;
    // for(int i = 0;i < 32;i++)
    // {
    //     sum += _TileLightsIndicesBuffer[i];
    //
    // }



    
    BRDF brdf = GetBRDF(surface);
    //获取全局照明
    GI gi = GetGI(GI_FRAGMENT_DATA(input), surface, brdf);
    float3 color = GetLighting(surface, brdf, gi);
    color += emission;
    
    return float4(color, 1.0);

    // return float4(ReflectiveShadowMap(surface), 1.0);

}

#endif