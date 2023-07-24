//全局照明相关库  
#ifndef CUSTOM_GI_INCLUDED  
#define CUSTOM_GI_INCLUDED  

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"  
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"  


TEXTURE2D(unity_Lightmap);  
SAMPLER(samplerunity_Lightmap);

TEXTURE3D_FLOAT(unity_ProbeVolumeSH);  
SAMPLER(samplerunity_ProbeVolumeSH);

TEXTURE2D(unity_ShadowMask);  
SAMPLER(samplerunity_ShadowMask);

TEXTURECUBE(unity_SpecCube0);  
SAMPLER(samplerunity_SpecCube0);

//当需要渲染光照贴图对象时  
#if defined(LIGHTMAP_ON)  
#define GI_ATTRIBUTE_DATA float2 lightMapUV : TEXCOORD1;  
#define GI_VARYINGS_DATA float2 lightMapUV : VAR_LIGHT_MAP_UV;  
#define TRANSFER_GI_DATA(input, output) output.lightMapUV = input.lightMapUV * unity_LightmapST.xy + unity_LightmapST.zw;
#define GI_FRAGMENT_DATA(input) input.lightMapUV  
#else  
//否则这些宏都应为空  
#define GI_ATTRIBUTE_DATA  
#define GI_VARYINGS_DATA  
#define TRANSFER_GI_DATA(input, output)  
#define GI_FRAGMENT_DATA(input) 0.0  
#endif


TEXTURECUBE(_diffuseIBL);
SAMPLER( sampler_diffuseIBL);  
TEXTURECUBE(_specularIBL);
SAMPLER(sampler_specularIBL);  

TEXTURE2D(_brdfLut);
SAMPLER(sampler_brdfLut);


TEXTURE2D(_rsmDepth);
SAMPLER(sampler_rsmDepth);

TEXTURE2D(_rsmBuffer0);
TEXTURE2D(_rsmBuffer1);
SAMPLER(sampler_rsmBuffer0);

float _rsmIntensity;
float4x4 _rsmVpMatrix;
float4x4 _rsmVpMatrixInv;

struct GI   
{  
    //漫反射颜色  
    float3 diffuse;
    //镜面反射颜色  
    float3 specular;
    
    ShadowMask shadowMask;
};

//采样环境立方体纹理  
float3 SampleEnvironment (Surface surfaceWS, BRDF brdf)   
{  
    float3 uvw = reflect(-surfaceWS.viewDirection, surfaceWS.normal);
    float mip = PerceptualRoughnessToMipmapLevel(brdf.perceptualRoughness);
    float4 environment = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, uvw, mip);  
    return DecodeHDREnvironment(environment, unity_SpecCube0_HDR);
}


//光照探针采样  
float3 SampleLightProbe (Surface surfaceWS)   
{  
    #if defined(LIGHTMAP_ON)  
        return 0.0;  
    #else
        //判断是否使用LPPV或插值光照探针  
        if (unity_ProbeVolumeParams.x)   
        {  
            return SampleProbeVolumeSH4(TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH),surfaceWS.position, surfaceWS.normal,  
                unity_ProbeVolumeWorldToObject,unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z,
                unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz);  
        }else{
            float4 coefficients[7];  
            coefficients[0] = unity_SHAr;  
            coefficients[1] = unity_SHAg;  
            coefficients[2] = unity_SHAb;  
            coefficients[3] = unity_SHBr;  
            coefficients[4] = unity_SHBg;  
            coefficients[5] = unity_SHBb;  
            coefficients[6] = unity_SHC;  
            return max(0.0, SampleSH9(coefficients, surfaceWS.normal)); 
        }
 
    #endif  
}

//采样光照贴图  
float3 SampleLightMap(float2 lightMapUV)   
{  
    #if defined(LIGHTMAP_ON)  
    return SampleSingleLightmap(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap), lightMapUV,float4(1.0, 1.0, 0.0, 0.0),  
        #if defined(UNITY_LIGHTMAP_FULL_HDR)  
           false,  
        #else  
           true,  
        #endif  
           float4(LIGHTMAP_HDR_MULTIPLIER, LIGHTMAP_HDR_EXPONENT, 0.0, 0.0)); 
    #else  
    return 0.0;  
    #endif  
}

//采样shadowMask得到烘焙阴影数据  
float4 SampleBakedShadows (float2 lightMapUV, Surface surfaceWS)   
{  
    #if defined(LIGHTMAP_ON)  
        return SAMPLE_TEXTURE2D(unity_ShadowMask, samplerunity_ShadowMask, lightMapUV);  
    #else  
        if (unity_ProbeVolumeParams.x)   
        {  
            //采样LPPV遮挡数据  
            return SampleProbeOcclusion(TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH), surfaceWS.position,   
                                        unity_ProbeVolumeWorldToObject,unity_ProbeVolumeParams.y,
                                        unity_ProbeVolumeParams.z,unity_ProbeVolumeMin.xyz,
                                        unity_ProbeVolumeSizeInv.xyz);  
        }  
        else   
        {  
            return unity_ProbesOcclusion;  
        }   
    #endif  
}


float3 FresnelSchlickRoughness(float NdotV, float3 f0, float roughness)
{
    float r1 = 1.0f - roughness;
    return f0 + (max(float3(r1, r1, r1), f0) - f0) * pow(1 - NdotV, 5.0f);
}


// 间接光照
GI IBL(Surface surface,GI gi)
{
    float3 albedo = surface.color;
    float roughness = 1 - surface.smoothness;
    float metallic = surface.metallic;
    float3 N = surface.normal;
    float3 V = surface.viewDirection;
    
    roughness = min(roughness, 0.99);

    float3 H = normalize(N);    // 用法向作为半角向量
    float NdotV = max(dot(N, V), 0);
    float HdotV = max(dot(H, V), 0);
    float3 R = normalize(reflect(-V, N));   // 反射向量

    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    // float3 F = SchlickFresnel(HdotV, F0);
    float3 F = FresnelSchlickRoughness(HdotV, F0, roughness);
    float3 k_s = F;
    float3 k_d = (1.0 - k_s) * (1.0 - metallic);

    // 漫反射
    float3 IBLdiffuse = SAMPLE_TEXTURECUBE(_diffuseIBL, sampler_diffuseIBL, R).rgb;
    gi.diffuse = k_d * albedo * IBLdiffuse;

    // 镜面反射
    float rgh = roughness * (1.7 - 0.7 * roughness);
    float lod = 6.0 * rgh;  // Unity 默认 6 级 mipmap
    float3 IBLspecular = SAMPLE_TEXTURECUBE_LOD(_specularIBL, sampler_specularIBL, R, lod).rgb;
    float2 brdf = SAMPLE_TEXTURE2D(_brdfLut, sampler_brdfLut, float2(NdotV, roughness)).rg;
    gi.specular = IBLspecular * (F0 * brdf.x + brdf.y);

    return gi;
}



float4x4 _vpMatrix;
float4x4 _vpMatrixInv;


float3 ReflectiveShadowMap(Surface surface)
{
    // xy[-1,1]
    float4 camPosNdc = mul(_vpMatrix, float4(surface.position, 1.0));
    camPosNdc /= camPosNdc.w;
    
    float3 indirect = float3(0, 0, 0);
    float sampleRange = 100;
    float rotateAngle = rand_2to1(camPosNdc.xy);
    
    
    for (uint i = 0; i < 16; ++i)
    {
        //使用已定义的泊松圆盘权重进行采样
        float2 rnd = RotateVec2(poissonDiskWieghts16[i].xy, rotateAngle);
        float2 coords = camPosNdc.xy * 0.5 + 0.5 + sampleRange * rnd;

        float vplPosDepth = SAMPLE_TEXTURE2D(_rsmDepth, sampler_rsmDepth, coords).r;
        // 未知vp最后的z是[-1,1]还是[0,1]还是[1,0]
        float4 vplNdcPos  = float4(coords * 2 - 1, vplPosDepth, 1.0);
        float4 vplPosWS = mul(_vpMatrixInv, vplNdcPos);
        vplPosWS /= vplPosWS.w;
        
        float3 vplNormalWS = SAMPLE_TEXTURE2D(_rsmBuffer1, sampler_rsmBuffer0, coords).xyz * 2 - 1;
        float3 flux = SAMPLE_TEXTURE2D(_rsmBuffer0, sampler_rsmBuffer0, coords).xyz;
        
        float3 vplDirWS = surface.position - vplPosWS.xyz;
        float attenuationVpl = max(0, dot(normalize(vplNormalWS), normalize(vplDirWS)));
        float attenuationCamPos = max(0, dot(normalize(surface.normal) , normalize(-vplDirWS)));
        float3 result = flux * attenuationVpl * attenuationCamPos / pow(length(surface.position - vplPosWS.xyz), 4);

        result *= rnd.x * rnd.x;
        indirect += result;
    }
    return saturate(indirect * 100000000);
}


   
GI GetGI(float2 lightMapUV, Surface surfaceWS, BRDF brdf)   
{  
    GI gi;
    gi.diffuse = float3(0.0, 0.0, 0.0);
    gi.specular = float3(0.0, 0.0, 0.0);
    #if defined(_IBL)
    GI iblGi = IBL(surfaceWS, gi);
    gi.diffuse += iblGi.diffuse;
    gi.specular += iblGi.specular;
    #else
    //在启用光照贴图时不启用全局光照 以免冲突
    gi.diffuse += SampleLightMap(lightMapUV) + SampleLightProbe(surfaceWS);
    gi.specular += SampleEnvironment(surfaceWS, brdf);  
    #endif

    // //RSM一般只包含低频信息 可以叠加使用
    // #if defined(_REFLECTIVE_SHADOW_MAP)
    // gi.diffuse += ReflectiveShadowMap(surfaceWS);
    // #endif
    
    // 初始化shadowMask
    gi.shadowMask.always = false;  
    gi.shadowMask.distance = false;  
    gi.shadowMask.shadows = 1.0;
    
    #if defined(_SHADOW_MASK_ALWAYS)  
        gi.shadowMask.always = true;  
        gi.shadowMask.shadows = SampleBakedShadows(lightMapUV, surfaceWS);  
    #elif defined(_SHADOW_MASK_DISTANCE)  
        gi.shadowMask.distance = true;  
        gi.shadowMask.shadows = SampleBakedShadows(lightMapUV, surfaceWS);  
    #endif   
    return gi;  
}  
   
#endif