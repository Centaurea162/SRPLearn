//BRDF相关库  
#ifndef CUSTOM_BRDF_INCLUDED  
#define CUSTOM_BRDF_INCLUDED  

//电介质的反射率平均约0.04  
#define MIN_REFLECTIVITY 0.04  

struct BRDF   
{  
    float3 diffuse;  
    float3 specular;  
    float roughness;  
    float perceptualRoughness;
    float fresnel; 
};

//获取给定表面的BRDF数据  
BRDF GetBRDF (Surface surface, bool applyAlphaToDiffuse = false)   
{  
    BRDF brdf;
    // kd项 漫反射的权重系数
    float oneMinusReflectivity = 1.0 - surface.metallic;
    
    brdf.diffuse = surface.color * oneMinusReflectivity / PI;
    //透明度预乘  
    if (applyAlphaToDiffuse)   
    {  
        brdf.diffuse *= surface.alpha;  
    }  
    brdf.specular = lerp(MIN_REFLECTIVITY, surface.color, surface.metallic);
    
    //光滑度转为实际粗糙度  
    brdf.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(surface.smoothness);  
    brdf.roughness = PerceptualRoughnessToRoughness(brdf.perceptualRoughness);
    brdf.fresnel = saturate(surface.smoothness + 1.0 - oneMinusReflectivity);
    
    return brdf;  
}

// 微表面模型  用于计算镜面反射强度
// D
float Trowbridge_Reitz_GGX(float NdotH, float a)
{
    float a2     = a * a;
    float NdotH2 = NdotH * NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}

// F
float3 SchlickFresnel(float HdotV, float3 F0)
{
    float m = clamp(1-HdotV, 0, 1);
    float m2 = m * m;
    float m5 = m2 * m2 * m; // pow(m,5)
    return F0 + (1.0 - F0) * m5;
}

// G
float SchlickGGX(float NdotV, float k)
{
    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}


//直接光照的表面颜色  
float3 DirectBRDF (Surface surface,Light light)   
{
    float roughness = max(1 - surface.smoothness, 0.05);   // 保证光滑物体也有高光
    
    float3 h = normalize(light.direction + surface.viewDirection);
    float NdotL = max(dot(surface.normal, light.direction), 0);
    float NdotV = max(dot(surface.normal, surface.viewDirection), 0);
    float NdotH = max(dot(surface.normal, h), 0);
    float HdotV  = max(dot(surface.viewDirection, h), 0);
    roughness = 1 - surface.smoothness;
    float alpha = roughness * roughness;
    float k = ((alpha+1) * (alpha+1)) / 8.0;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), surface.color, surface.metallic);

    float  D = Trowbridge_Reitz_GGX(NdotH, alpha);
    float3 F = SchlickFresnel(HdotV, F0);
    float  G = SchlickGGX(NdotV, k) * SchlickGGX(NdotL, k);

    float3 k_s = F;
    float3 k_d = (1.0 - k_s) * (1 - surface.metallic);
    float3 f_diffuse = surface.color / PI;
    float3 f_specular = (D * F * G) / (4.0 * NdotV * NdotL + 0.0001);

    float3 color = (k_d * f_diffuse + f_specular) * light.color * NdotL;
    
    return color;
}




//计算间接光照
float3 IndirectBRDF (Surface surface, BRDF brdf, float3 diffuse, float3 specular)   
{
    #if defined(_IBL)
    //全局光照贴图
    return (diffuse + specular) * surface.occlusion; 
    #else
    //反射探针+光照探针 的光照和反射贴图
    //通过fresnel项控制反射强度
    float fresnelStrength = surface.fresnelStrength * Pow4(1.0 - saturate(dot(surface.normal, surface.viewDirection)));
    float3 reflection = specular * lerp(brdf.specular, brdf.fresnel, fresnelStrength);  
    //根据表面的粗糙度散射镜面反射
    reflection /= brdf.roughness * brdf.roughness + 1.0;
    
    return (diffuse * brdf.diffuse + reflection) * surface.occlusion;
    #endif
}
   
#endif