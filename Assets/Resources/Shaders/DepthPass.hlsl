#ifndef CUSTOM_DEPTH_PASS_INCLUDED  
#define CUSTOM_DEPTH_PASS_INCLUDED  


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
    float4 color : VAR_COLOR;
    float2 baseUV : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

//顶点函数
Varyings DepthPassVertex(Attributes input){
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    //使UnlitPassVertex输出位置和索引,并复制索引
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    return output;
}
//片元函数
float4  DepthPassFragment (Varyings input) : SV_Target{
    UNITY_SETUP_INSTANCE_ID(input);
    float depthOut = 1.0 - input.positionCS.z * 0.5 + 0.5;
    return float4(depthOut, depthOut, depthOut, 1.0);
   
}

#endif