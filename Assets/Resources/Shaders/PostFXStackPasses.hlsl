#ifndef CUSTOM_POST_FX_PASSES_INCLUDED  
#define CUSTOM_POST_FX_PASSES_INCLUDED  

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl" 

struct Varyings   
{  
    float4 positionCS : SV_POSITION;  
    float2 screenUV : VAR_SCREEN_UV;  
};


bool _BloomBicubicUpsampling;  
float4 _PostFXSource_TexelSize;
float4 _BloomThreshold;
float _BloomIntensity;  

float4 _ColorAdjustments;  
float4 _ColorFilter;

float4 _WhiteBalance;

float4 _SplitToningShadows;  
float4 _SplitToningHighlights;

float4 _ChannelMixerRed;  
float4 _ChannelMixerGreen;  
float4 _ChannelMixerBlue;

float4 _SMHShadows;  
float4 _SMHMidtones;  
float4 _SMHHighlights;  
float4 _SMHRange;

float4 _ColorGradingLUTParameters;

bool _ColorGradingLUTInLogC;

TEXTURE2D(_PostFXSource);
TEXTURE2D(_PostFXSource2);
TEXTURE2D(_ColorGradingLUT);
SAMPLER(sampler_linear_clamp);

sampler2D _CameraDepthTexture;

float4 GetSource(float2 screenUV)   
{  
    return SAMPLE_TEXTURE2D_LOD(_PostFXSource, sampler_linear_clamp, screenUV, 0); 
}

float4 GetSource2(float2 screenUV)   
{  
    return SAMPLE_TEXTURE2D_LOD(_PostFXSource2, sampler_linear_clamp, screenUV, 0);  
}

float4 GetSourceTexelSize ()   
{  
    return _PostFXSource_TexelSize;  
}

float4 GetSourceBicubic (float2 screenUV)   
{  
    return SampleTexture2DBicubic(TEXTURE2D_ARGS(_PostFXSource, sampler_linear_clamp), screenUV,_PostFXSource_TexelSize.zwxy, 1.0, 0.0);  
}

float Luminance(float3 color, bool useACES)   
{  
    return useACES ? AcesLuminance(color) : Luminance(color);  
}

float3 ColorGradePostExposure (float3 color)   
{  
    return color * _ColorAdjustments.x;  
}

float3 ColorGradingContrast (float3 color, bool useACES)   
{  
    color = useACES ? ACES_to_ACEScc(unity_to_ACES(color)) : LinearToLogC(color);  
    color = (color - ACEScc_MIDGRAY) * _ColorAdjustments.y + ACEScc_MIDGRAY;  
    return useACES ? ACES_to_ACEScg(ACEScc_to_ACES(color)) : LogCToLinear(color);  
}

float3 ColorGradeColorFilter (float3 color)   
{  
    return color * _ColorFilter.rgb;
}

float3 ColorGradingHueShift (float3 color)   
{  
    color = RgbToHsv(color);  
    float hue = color.x + _ColorAdjustments.z;  
    color.x = RotateHue(hue, 0.0, 1.0);  
    return HsvToRgb(color);  
}

float3 ColorGradingSaturation (float3 color, bool useACES)   
{  
    float luminance = Luminance(color, useACES);   
    return (color - luminance) * _ColorAdjustments.w + luminance;  
}

float3 ColorGradeWhiteBalance (float3 color)   
{  
    color = LinearToLMS(color);  
    color *= _WhiteBalance.rgb;  
    return LMSToLinear(color);  
}

//色调分离  
float3 ColorGradeSplitToning (float3 color, bool useACES)   
{  
    color = PositivePow(color, 1.0 / 2.2);  
    float t = saturate(Luminance(saturate(color), useACES) + _SplitToningShadows.w);      float3 shadows = lerp(0.5, _SplitToningShadows.rgb, 1.0 - t);  
    float3 highlights = lerp(0.5, _SplitToningHighlights.rgb, t);  
    color = SoftLight(color, shadows);  
    color = SoftLight(color, highlights);  
    return PositivePow(color, 2.2);  
}

float3 ColorGradingChannelMixer(float3 color)   
{  
    return mul(float3x3(_ChannelMixerRed.rgb, _ChannelMixerGreen.rgb, _ChannelMixerBlue.rgb),color);  
}

float3 ColorGradingShadowsMidtonesHighlights(float3 color, bool useACES)   
{   
    float luminance = Luminance(color, useACES);
    float shadowsWeight = 1.0 - smoothstep(_SMHRange.x, _SMHRange.y, luminance);  
    float highlightsWeight = smoothstep(_SMHRange.z, _SMHRange.w, luminance);  
    float midtonesWeight = 1.0 - shadowsWeight- highlightsWeight;  
    return color * _SMHShadows.rgb * shadowsWeight +  
           color * _SMHMidtones.rgb * midtonesWeight +  
           color * _SMHHighlights.rgb * highlightsWeight;  
}  


//颜色分级  
float3 ColorGrade (float3 color, bool useACES = false)   
{  
    color = min(color, 60.0);  
    color = ColorGradePostExposure(color);  
    color = ColorGradeWhiteBalance(color);  
    color = ColorGradingContrast(color, useACES);  
    color = ColorGradeColorFilter(color);  
    color = max(color, 0.0);  
    color = ColorGradeSplitToning(color, useACES);  
    color = ColorGradingChannelMixer(color);  
    color = max(color, 0.0);  
    color = ColorGradingShadowsMidtonesHighlights(color, useACES);  
    color = ColorGradingHueShift(color);  
    color = ColorGradingSaturation(color, useACES);  
    return max(useACES ? ACEScg_to_ACES(color) : color, 0.0);  
    return color;  
}

float3 GetColorGradedLUT(float2 uv, bool useACES = false)   
{  
    float3 color = GetLutStripValue(uv, _ColorGradingLUTParameters);  
    return ColorGrade(LogCToLinear(color), useACES);     
}  

float3 ApplyBloomThreshold (float3 color)   
{
    //catlike coding 方法
    float brightness = Max3(color.r, color.g, color.b);  
    float soft = brightness + _BloomThreshold.y;  
    soft = clamp(soft, 0.0, _BloomThreshold.z);  
    soft = soft * soft * _BloomThreshold.w;  
    float contribution = max(soft, brightness - _BloomThreshold.x);  
    contribution /= max(brightness, 0.00001);  
    return color * contribution;

    // //入门精要
    // float3 luma = dot(float3(0.2126, 0.7152, 0.0722), color);
    // // clamp 约束到 0 - 1 区间
    // float val = clamp(luma - _BloomThreshold.x, 0.0, 1.0);
    // return color * val;
} 


Varyings DefaultPassVertex (uint vertexID : SV_VertexID)   
{  
    Varyings output;
    //三角形顶点坐标分别为（-1，-1），（-1，3）和（3，-1）
    //vertexID=0 CS(-1, -1, 0, 1) vertexID=1 CS(-1, 3) vertexID=2 CS(3, -1, 0, 1)
    output.positionCS = float4(vertexID <= 1 ? -1.0 : 3.0,vertexID == 1 ? 3.0 : -1.0, 0.0, 1.0);
    // 为使可见的 UV 坐标覆盖0到1的范围，则对应的UV坐标为（0，0），（0，2）和（2，0），如下图所示
    output.screenUV = float2(vertexID <= 1 ? 0.0 : 2.0,vertexID == 1 ? 2.0 : 0.0);  
    if (_ProjectionParams.x < 0.0)   
    {   
        output.screenUV.y = 1.0 - output.screenUV.y;  
    }   
    return output;  
}

//采样源纹理
float4 CopyPassFragment (Varyings input) : SV_TARGET   
{   
    return GetSource(input.screenUV);  
}

//采样源纹理
float4  CopyDepthPassFragment (Varyings input) : SV_TARGET   
{
    float depth = tex2D(_CameraDepthTexture,input.screenUV).r;
    float4 col = float4(depth, depth, depth, 1 );
    return col;
}

//获取大于阈值的像素点
float4 BloomPrefilterPassFragment (Varyings input) : SV_TARGET   
{  
    float3 color = ApplyBloomThreshold(GetSource(input.screenUV).rgb);  
    return float4(color, 1.0);  
}

//淡化荧光闪烁
float4 BloomPrefilterFirefliesPassFragment (Varyings input) : SV_TARGET   
{
    float3 color = 0.0;
    float weightSum = 0.0;
    
    float2 offsets[] =    
    {  
        float2(0.0, 0.0),  
        float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0),  
        float2(-1.0, 0.0), float2(1.0, 0.0), float2(0.0, -1.0), float2(0.0, 1.0)  
    };

    //加权平均法 将该点的光照分配到相邻的点上
    for (int i = 0; i < 9; i++)   
    {  
        float3 c = GetSource(input.screenUV + offsets[i] * GetSourceTexelSize().xy * 2.0).rgb;  
        c = ApplyBloomThreshold(c);  
        // Luminance : return dot(linearRgb, real3(0.2126729, 0.7151522, 0.0721750));
        float w = 1.0 / (Luminance(c) + 1.0);  
        color += c * w;  
        weightSum += w;  
    }  
    
    color /= weightSum;  
    return float4(color, 1.0);  
}

//在水平方向的进行滤波
float4 BloomHorizontalPassFragment (Varyings input) : SV_TARGET   
{   
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
        color += GetSource(input.screenUV + float2(offset, 0.0)).rgb * weights[i];  
    }   
    return float4(color, 1.0);  
}

//在竖直方向的进行滤波
float4 BloomVerticalPassFragment (Varyings input) : SV_TARGET   
{   
    float3 color = 0.0;  
    float offsets[] = {-3.23076923, -1.38461538, 0.0, 1.38461538, 3.23076923};  
    float weights[] =    
    {  
        0.07027027, 0.31621622, 0.22702703, 0.31621622, 0.07027027  
    };  
    for (int i = 0; i < 5; i++)    
    {  
        float offset = offsets[i] * 2.0 * GetSourceTexelSize().x;  
        color += GetSource(input.screenUV + float2(0.0, offset)).rgb * weights[i];  
    }   
    return float4(color, 1.0);  
}

//Bloom叠加模式
float4 BloomAddPassFragment (Varyings input) : SV_TARGET   
{  
    float3 lowRes;
    //消除Bloom的方块化问题
    if (_BloomBicubicUpsampling)   
    {  
        lowRes = GetSourceBicubic(input.screenUV).rgb;  
    }  
    else   
    {   
        lowRes = GetSource(input.screenUV).rgb;  
    }  
    float4 highRes = GetSource2(input.screenUV);  
    return float4(lowRes * _BloomIntensity + highRes.rgb, highRes.a);  
}

//Bloom散射模式
float4 BloomScatterPassFragment (Varyings input) : SV_TARGET   
{  
    float3 lowRes;
    //消除Bloom的方块化问题
    if (_BloomBicubicUpsampling)   
    {  
        lowRes = GetSourceBicubic(input.screenUV).rgb;  
    }  
    else   
    {   
        lowRes = GetSource(input.screenUV).rgb;  
    }  
    float3 highRes = GetSource2(input.screenUV).rgb;  
    return float4(lerp(highRes, lowRes, _BloomIntensity), 1.0);  
}

//Bloom散射的最终绘制
float4 BloomScatterFinalPassFragment(Varyings input) : SV_TARGET  
{  
    float3 lowRes;
    //消除Bloom的方块化问题
    if (_BloomBicubicUpsampling)   
    {  
        lowRes = GetSourceBicubic(input.screenUV).rgb;  
    }  
    else   
    {   
        lowRes = GetSource(input.screenUV).rgb;  
    }   
    float4 highRes = GetSource2(input.screenUV);    
    lowRes += highRes.rgb - ApplyBloomThreshold(highRes.rgb); 
    return float4(lerp(highRes.rgb, lowRes, _BloomIntensity), highRes.a);  
}  



//得到颜色值然后立即进行颜色分级
float3 ApplyColorGradingLUT(float3 color) {
    return ApplyLut2D(TEXTURE2D_ARGS(_ColorGradingLUT, sampler_linear_clamp),
        saturate(_ColorGradingLUTInLogC ? LinearToLogC(color) : color),
        _ColorGradingLUTParameters.xyz);
}

//颜色分级且无色调映射
float4 ColorGradingNonePassFragment (Varyings input) : SV_TARGET {
    float3 color = GetColorGradedLUT(input.screenUV);
    return float4(color, 1.0);
}

//颜色分级且Reinhard 色调映射
float4 ColorGradingReinhardPassFragment(Varyings input) : SV_TARGET{
    float3 color = GetColorGradedLUT(input.screenUV);
    color /= color + 1.0;
    return float4(color, 1.0);
}

//颜色分级且Neutral 色调映射
float4 ColorGradingNeutralPassFragment(Varyings input) : SV_TARGET{
    float3 color = GetColorGradedLUT(input.screenUV);
    color = NeutralTonemap(color);
    return float4(color, 1.0);
}

//颜色分级且ACES 色调映射
float4 ColorGradingACESPassFragment(Varyings input) : SV_TARGET{
    float3 color = GetColorGradedLUT(input.screenUV, true);
    color = AcesTonemap(color);
    return float4(color, 1.0);
}

//采样源纹理并应用到颜色分级LUT
float4 FinalPassFragment(Varyings input) : SV_TARGET{
    float4 color = GetSource(input.screenUV);
    color.rgb = ApplyColorGradingLUT(color.rgb);
    return color;
}

#endif