﻿#ifndef CUSTOM_UNLIT_PASS_INCLUDED
#define CUSTOM_UNLIT_PASS_INCLUDED

//顶点函数输入结构体
struct Attributes {
    float3 positionOS : POSITION;
    float4 color : COLOR;
    float2 baseUV : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
//片元函数输入结构体
struct Varyings {
    float4 positionCS : SV_POSITION;
    #if defined(_VERTEX_COLORS)
    float4 color : VAR_COLOR;
    #endif
    float2 baseUV : VAR_BASE_UV;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};


//顶点函数
Varyings UnlitPassVertex(Attributes input){
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    //使UnlitPassVertex输出位置和索引,并复制索引
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    #if defined(_VERTEX_COLORS)
    output.color = input.color;
    #endif
    //计算缩放和偏移后的UV坐标
    output.baseUV = TransformBaseUV(input.baseUV);
    return output;
}
//片元函数
float4 UnlitPassFragment (Varyings input) : SV_TARGET {
    UNITY_SETUP_INSTANCE_ID(input);
    InputConfig config = GetInputConfig(input.baseUV);
    float4 base = GetBase(config);
    #if defined(_CLIPPING)
    //透明度低于阈值的片元进行舍弃
    clip(base.a - GetCutoff(config));
    #endif
    return float4(base.rgb, GetFinalAlpha(base.a));
}

#endif
