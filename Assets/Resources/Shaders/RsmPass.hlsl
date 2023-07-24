#ifndef CUSTOM_RSM_PASS_INCLUDED  
#define CUSTOM_RSM_PASS_INCLUDED

#include "./ShaderLibrary/Common.hlsl"

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


float4 _RSMBlurSource_TexelSize;

TEXTURE2D(_LightPassTexture);
SAMPLER(sampler_LightPassTexture);
TEXTURE2D(_SSRBlurSource);
TEXTURE2D(_RSMBlurSource);
SAMPLER(sampler_linear_clamp);

TEXTURE2D(_rsmDepth);
SAMPLER(sampler_rsmDepth);

TEXTURE2D(_rsmBuffer0);
SAMPLER(sampler_rsmBuffer0);
TEXTURE2D(_rsmBuffer1);
SAMPLER(sampler_rsmBuffer1);

float _rsmIntensity;
float4x4 _rsmVpMatrix;
float4x4 _rsmVpMatrixInv;

sampler2D _gdepth;
sampler2D _GBuffer0;
sampler2D _GBuffer1;
sampler2D _GBuffer2;
sampler2D _GBuffer3;

CBUFFER_START(GBuffer)
float4x4 _vpMatrix;
float4x4 _vpMatrixInv;
float4x4 _vMatrix;
float4x4 _pMatrix;
float4x4 _pMatrixInv;
float4x4 _ViewToScreenMatrix;
CBUFFER_END


float3 ReflectiveShadowMap(float3 normal, float3 position)
{
    // xy[-1,1]
    float4 camPosNdc = mul(_vpMatrix, float4(position, 1.0));
    camPosNdc /= camPosNdc.w;
    
    float3 indirect = float3(0, 0, 0);
    float sampleRange = 0.50;
    float rotateAngle = rand_2to1(camPosNdc.xy);


    
    for (uint i = 0; i < 16; ++i)
    {
        //使用已定义的泊松圆盘权重进行采样
        float2 rnd = RotateVec2(poissonDiskWieghts16[i].xy, rotateAngle);
        //coords = uv
        float2 coords = (camPosNdc.xy + sampleRange * rnd) * 0.5 + 0.5;

        float vplPosDepth = SAMPLE_TEXTURE2D(_rsmDepth, sampler_rsmDepth, coords).r;
        // vp最后的z是[-1,1]
        float4 vplNdcPos  = float4(coords * 2 - 1, vplPosDepth, 1.0);
        float4 vplPosWS = mul(_vpMatrixInv, vplNdcPos);
        vplPosWS /= vplPosWS.w;

        float3 flux = SAMPLE_TEXTURE2D(_rsmBuffer0, sampler_rsmBuffer0, coords).xyz;
        float3 vplNormalWS = SAMPLE_TEXTURE2D(_rsmBuffer1, sampler_rsmBuffer1, coords).xyz * 2 - 1;
        
        float3 vplDirWS = position - vplPosWS.xyz;
        float attenuationVpl = max(0, dot(normalize(vplNormalWS), normalize(vplDirWS)));
        float attenuationCamPos = max(0, dot(normalize(normal) , normalize(-vplDirWS)));
        
        float3 result = flux * attenuationVpl * attenuationCamPos / pow(length(position - vplPosWS.xyz), 4);
        
        result *= rnd.x * rnd.x;
        indirect += result;
    }
    return saturate(indirect / 2);
}

//顶点函数
Varyings RSMVertex(Attributes input){
    Varyings output;
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    output.baseUV = input.baseUV;
    
    return output;
}

//片元函数
float4 RSMFragment (Varyings input, out float depthOut : SV_Depth) : SV_TARGET {
    float depth = tex2D(_gdepth, input.baseUV).r;
    depthOut = depth;
    
    float3 normal = tex2D(_GBuffer1, input.baseUV).rgb * 2 - 1;
    // 反投影重建世界坐标
    float4 ndcPos  = float4(input.baseUV * 2 - 1, depth, 1.0);
    float4 positionWS = mul(_vpMatrixInv, ndcPos);
    positionWS /= positionWS.w;

    float3 indirect = ReflectiveShadowMap(normal, positionWS.xyz);
    
	
    
    return float4(indirect, 0.0);

}

//顶点函数
Varyings DefaultPassVertex(Attributes input){
    Varyings output;
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    output.baseUV = input.baseUV;
    
    return output;
}

float4 GetSource(float2 screenUV)   
{  
    return SAMPLE_TEXTURE2D_LOD(_RSMBlurSource, sampler_linear_clamp, screenUV, 0); 
}

float4 GetSourceTexelSize ()   
{  
    return _RSMBlurSource_TexelSize;  
}

//在水平方向的进行滤波
float4 BlurHorizontalFragment(Varyings input, out float depthOut : SV_Depth) : SV_TARGET{
    float depth = tex2D(_gdepth, input.baseUV).r;
    depthOut = depth;
    
    float3 color = 0.0;  
    float offsets[] = {-4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0};  
    float weights[] =    
    {  
        0.01621622, 0.05405405, 0.12162162, 0.19459459, 0.22702703,  
        0.19459459, 0.12162162, 0.05405405, 0.01621622  
    };  
    for (int i = 0; i < 9; i++)    
    {  
        float offset = offsets[i] * 2.0 * GetSourceTexelSize().x;  
        color += GetSource(input.baseUV + float2(offset, 0.0)).rgb * weights[i];  
    }   
    return float4(color, 1.0);  
}

//在竖直方向的进行滤波
float4 BlurVerticalFragment(Varyings input, out float depthOut : SV_Depth) : SV_TARGET{
    float depth = tex2D(_gdepth, input.baseUV).r;
    depthOut = depth;
    
    float3 color = 0.0;  
    float offsets[] = {-3.23076923, -1.38461538, 0.0, 1.38461538, 3.23076923};  
    float weights[] =    
    {  
        0.07027027, 0.31621622, 0.22702703, 0.31621622, 0.07027027  
    };  
    for (int i = 0; i < 5; i++)    
    {  
        float offset = offsets[i] * 2.0 * GetSourceTexelSize().x;  
        color += GetSource(input.baseUV + float2(0.0, offset)).rgb * weights[i];  
    }   
    return float4(color, 1.0);  
}

//叠加
float4 BlurFinalFragment(Varyings input, out float depthOut : SV_Depth) : SV_TARGET{
    float depth = tex2D(_gdepth, input.baseUV).r;
    depthOut = depth;
    
    float4 final = SAMPLE_TEXTURE2D(_LightPassTexture, sampler_LightPassTexture, input.baseUV);
    #if defined(_REFLECTIVE_SHADOW_MAP)
    final += SAMPLE_TEXTURE2D_LOD(_RSMBlurSource, sampler_linear_clamp, input.baseUV, 0);
    #endif
    #if defined(_SCREEN_SPACE_REFLECTION)
    final += SAMPLE_TEXTURE2D_LOD(_SSRBlurSource, sampler_linear_clamp, input.baseUV, 0); 
    #endif
    return float4(final.xyz, 1.0);
}


#endif