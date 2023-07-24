#ifndef CUSTOM_RSM_PASS_INCLUDED
#define CUSTOM_RSM_PASS_INCLUDED

#include "UnityCG.cginc"

#define MAX_OTHER_LIGHT_COUNT 256

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
    float3 posWorld : TEXCOORD4;
};

float4 _MainTex_ST;

sampler2D _MainTex;
sampler2D _EmissionMap;
sampler2D _NormalMap;


float _Use_Normal_Map;
float4 _BaseColor;

CBUFFER_START(Custom_Lit)
int _rsmLightId;
float4 _OtherLightColors[MAX_OTHER_LIGHT_COUNT];  
float4 _OtherLightPositions[MAX_OTHER_LIGHT_COUNT];
float4 _OtherLightDirections[MAX_OTHER_LIGHT_COUNT];
float4 _OtherLightSpotAngles[MAX_OTHER_LIGHT_COUNT];

float4x4 _rsmVpMatrix;
CBUFFER_END

float Square (float v)   
{  
    return v * v;  
}

v2f vert (appdata v)
{
    v2f o;
    o.posWorld = mul(unity_ObjectToWorld,v.vertex);
    o.vertex = UnityObjectToClipPos(v.vertex);  
    o.uv = v.uv;
    o.nDirWS = UnityObjectToWorldNormal(v.normal);                  //法线信息
    o.tDirWS = mul(unity_ObjectToWorld,float4(v.tangent.xyz,0));    //切线信息
    o.bDirWS = normalize(cross(o.nDirWS,o.tDirWS) * v.tangent.w);   //副切线信息
    return o;
}

void frag (
    v2f i,
    out float4 GT0 : SV_Target0,
    out float4 GT1 : SV_Target1
)
{
    //normal
    float3 nDirWS = i.nDirWS;
    
    if(_Use_Normal_Map)
    {
        float3 nDirTS = UnpackNormal(tex2D(_NormalMap, i.uv));
        float3x3 TBN = float3x3(i.tDirWS,i.bDirWS,i.nDirWS);
        nDirWS = mul(TBN, nDirTS);
    } 
    
    //flux
    float4 color = _BaseColor * tex2D(_MainTex, i.uv);
    float3 emission = tex2D(_EmissionMap, i.uv).rgb;
    float3 lightColor =  _OtherLightColors[_rsmLightId].rgb;
    float3 ray = _WorldSpaceCameraPos.xyz - i.posWorld;
    //光照强度随距离衰减  
    float distanceSqr = max(dot(ray, ray), 0.00001);  
    //入射光线方向
    float3 direction = normalize(ray);  
    //套用公式计算随光照范围衰减  
    float rangeAttenuation = Square(saturate(1.0 - Square(distanceSqr * _OtherLightPositions[_rsmLightId].w)));
    
    float4 spotAngles = _OtherLightSpotAngles[_rsmLightId];
    float3 spotDirection = _OtherLightDirections[_rsmLightId].xyz;
    //计算聚光灯衰减值
    float spotAttenuation = Square(saturate(dot(normalize(_OtherLightDirections[_rsmLightId].xyz), direction) * spotAngles.x + spotAngles.y));

    float attenuation =  spotAttenuation * rangeAttenuation / distanceSqr;
    //简单的认为是漫反射 指计算低频信息
    float3 flux = color * lightColor * attenuation + emission;
    
    
    GT0 = float4(flux, 0.0);
    // GT0 = spotAttenuation;
    GT1 = float4(nDirWS * 0.5 + 0.5, 0.0);

    
}


#endif