#ifndef CUSTOM_GBUFFER_PASS_INCLUDED
#define CUSTOM_GBUFFER_PASS_INCLUDED

#include "UnityCG.cginc"

struct appdata
{
    float4 vertex : POSITION;
    float2 uv : TEXCOORD0;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
};

struct v2f
{
    float2 uv : TEXCOORD0;
    float4 vertex : SV_POSITION;
    float3 nDirWS : TEXCOORD1;      //法线方向
    float3 tDirWS : TEXCOORD2;      //切线方向
    float3 bDirWS : TEXCOORD3;      //副切线方向
};

float4 _MainTex_ST;

sampler2D _MainTex;
sampler2D _MetallicMap;
sampler2D _RoughnessMap;
sampler2D _MetallicGlossMap;
sampler2D _EmissionMap;
sampler2D _OcclusionMap;
sampler2D _NormalMap;


float _Use_Metal_Map;
float _Use_Normal_Map;
float _Use_Roughness_Map;
float _Use_MetallicGloss_Map;
float _Receive_Screen_Space_Reflection;
float _Metallic;
float _Roughness;
float4 _BaseColor;

v2f vert (appdata v)
{
    v2f o;
    o.vertex = UnityObjectToClipPos(v.vertex);
    o.uv = TRANSFORM_TEX(v.uv, _MainTex);
    o.nDirWS = UnityObjectToWorldNormal(v.normal);                  //法线信息
    o.tDirWS = mul(unity_ObjectToWorld,float4(v.tangent.xyz,0));    //切线信息
    o.bDirWS = normalize(cross(o.nDirWS,o.tDirWS) * v.tangent.w);   //副切线信息
    return o;
}

void frag (
    v2f i,
    out float4 GT0 : SV_Target0,
    out float4 GT1 : SV_Target1,
    out float3 GT2 : SV_Target2,
    out float3 GT3 : SV_Target3
)
{
    float4 color = _BaseColor * tex2D(_MainTex, i.uv);
    float3 emission = tex2D(_EmissionMap, i.uv).rgb;
    float3 nDirWS = i.nDirWS;
    float metallic = _Metallic;
    float roughness = _Roughness;
    float occlusion = tex2D(_OcclusionMap, i.uv).g;
    if(_Use_Metal_Map)
    {
        float metal = tex2D(_MetallicMap, i.uv).r;
        metallic *= metal.r;
    }
    if(_Use_Roughness_Map)
    {
        float rough = tex2D(_RoughnessMap, i.uv).r;
        roughness *= rough.r;
    }

    if(_Use_MetallicGloss_Map)
    {
        float4 metalRough = tex2D(_MetallicGlossMap, i.uv);
        metallic *= metalRough.r;
        roughness *= 1.0 - metalRough.a;
    }
    
    if(_Use_Normal_Map)
    {
        float3 nDirTS = UnpackNormal(tex2D(_NormalMap, i.uv));
        float3x3 TBN = float3x3(i.tDirWS,i.bDirWS,i.nDirWS);
        nDirWS = mul(TBN, nDirTS);
    } 

    GT0 = color;
    if(_Receive_Screen_Space_Reflection)
    {
        GT1 = float4(nDirWS * 0.5 + 0.5, 1.0);
    }else
    {
        GT1 = float4(nDirWS * 0.5 + 0.5, 0.0);
    }
    // w通道为 SSR遮罩通道
    
    GT2 = float3(roughness, metallic, occlusion);
    GT3 = float3(emission);
}


#endif