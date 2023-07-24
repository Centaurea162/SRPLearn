#ifndef CUSTOM_SCREEN_SPACE_REFLECTION_PASS_INCLUDED  
#define CUSTOM_SCREEN_SPACE_REFLECTION_PASS_INCLUDED

//顶点函数输入结构体
struct Attributes {
    float3 positionOS : POSITION;
    float2 baseUV : TEXCOORD0;
};
//片元函数输入结构体
struct Varyings {
    float4 positionCS : SV_POSITION;
    float2 baseUV : VAR_BASE_UV;
    float3 viewRay : TEXCOORD0;
};


float4 _SSRBlurSource_TexelSize;

TEXTURE2D(_LightPassTexture);
SAMPLER(sampler_LightPassTexture);
TEXTURE2D(_SSRBlurSource);
SAMPLER(sampler_linear_clamp);
TEXTURE2D(_DitherMap);
SAMPLER(sampler_DitherMap);

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

float _maxRayMarchingDistance;
int _maxRayMarchingStep;
int _maxRayMarchingBinarySearchCount;
float _rayMarchingStepSize;
float _depthThickness;

float distanceSquared(float2 A, float2 B)
{
    A -= B;
    return dot(A, A);
}

void swap(inout float v0, inout float v1)
{
	float temp = v0;
	v0 = v1;
	v1 = temp;
}


bool checkDepthCollision(float3 positionVS, out float2 screenPos, inout float depthDistance)
{
    float pDepth = positionVS.z / -_ProjectionParams.z;
    float4 positionCS = mul(_pMatrix, float4(positionVS, 1.0));
    positionCS /= positionCS.w;
    screenPos = positionCS.xy * 0.5 + 0.5;
    float mask = tex2Dlod(_GBuffer1, float4(screenPos,0,0)).a;

    float camDepth = Linear01Depth(tex2Dlod(_gdepth, float4(screenPos,0,0)).r, _ZBufferParams);
    //判断当前反射点是否在屏幕外，或者超过了当前深度值并且不超过太多的情况下
    depthDistance = pDepth - camDepth;
    // cam < p < cam + thick
    return screenPos.x > 0 && screenPos.y > 0 && screenPos.x < 1.0 && screenPos.y < 1.0 && mask == 0.0 && pDepth > camDepth;

}


bool viewSpaceRayMarching(float3 rayOri, float3 rayDir, float currentStepSize, inout float depthDistance,inout float3 currentViewPos, inout float2 hitScreenPos)
{
    
    UNITY_LOOP
    for(int i = 1; i < _maxRayMarchingStep; i++)
    {
        float3 currentPos = rayOri + rayDir * currentStepSize * i;
        if (length(rayOri - currentPos) > _maxRayMarchingDistance)
        {
            return false;
        }
            
        if (checkDepthCollision(currentPos, hitScreenPos, depthDistance))
        {
            currentViewPos = currentPos;
            return true;
            
        }
    }
    return false;
}

bool binarySearchRayMarching(float3 rayOri, float3 rayDir, inout float2 hitScreenPos)
{
    //反方向反射的，本身也看不见，索性直接干掉
    if (rayDir.z > 0.0)
        return false;
    float currentStepSize = _rayMarchingStepSize;
    float3 currentPos = rayOri;
    float depthDistance = 0;
    UNITY_LOOP
    for(int i = 0; i < _maxRayMarchingBinarySearchCount; i++)
    {
        if(viewSpaceRayMarching(rayOri, rayDir, currentStepSize, depthDistance, currentPos, hitScreenPos))
        {
            //若相交 则回退一个步长 且把步长减半
            if (depthDistance < _depthThickness)
            {
                return true;
            }
            rayOri = currentPos - rayDir * currentStepSize;
            currentStepSize *= 0.5;
        }
        else
        {
            return false;
        }
    }
    return false;
}


bool screenSpaceRayMarching(float3 rayOri, float3 rayDir, inout float2 hitScreenPos)
{
	//反方向反射的，本身也看不见，索性直接干掉
	if (rayDir.z > 0.0)
		return false;
	//首先求得视空间终点位置，不超过最大距离
	float magnitude = _maxRayMarchingDistance;
	float end = rayOri.z + rayDir.z * magnitude;
	//如果光线反过来超过了近裁剪面，需要截取到近裁剪面 注意这里的end最远只到近裁剪面
	if (end > -_ProjectionParams.y)
	{
		// 注意视空间下的z 正对的是负轴 
		magnitude = -_ProjectionParams.y - rayOri.z;
	}
	//用于下方的归一化
	magnitude /= rayDir.z;
	float3 rayEnd = rayOri + rayDir * magnitude;	
	//直接把cliptoscreen与projection矩阵结合，得到齐次坐标系下屏幕位置
	float4 homoRayOri = mul(_ViewToScreenMatrix, float4(rayOri, 1.0));
	float4 homoRayEnd = mul(_ViewToScreenMatrix, float4(rayEnd, 1.0));
	//w
	float kOri = 1.0 / homoRayOri.w;
	float kEnd = 1.0 / homoRayEnd.w;
	//屏幕空间位置
	float2 screenRayOri = homoRayOri.xy * kOri;
	float2 screenRayEnd = homoRayEnd.xy * kEnd;
	screenRayEnd = (distanceSquared(screenRayEnd, screenRayOri) < 0.0001) ? screenRayOri + float2(0.01, 0.01) : screenRayEnd;
	
	float3 QOri = rayOri * kOri;
	float3 QEnd = rayEnd * kEnd;
	
	float2 displacement = screenRayEnd - screenRayOri;
	bool permute = false;
	if (abs(displacement.x) < abs(displacement.y))
	{
		permute = true;
		
		displacement = displacement.yx;
		screenRayOri.xy = screenRayOri.yx;
		screenRayEnd.xy = screenRayEnd.yx;
	}
	float dir = sign(displacement.x);
	float invdx = dir / displacement.x;
	float2 dp = float2(dir, invdx * displacement.y) * _rayMarchingStepSize;
	float3 dq = (QEnd - QOri) * invdx * _rayMarchingStepSize;
	float  dk = (kEnd - kOri) * invdx * _rayMarchingStepSize;
	float rayZmin = rayOri.z;
	float rayZmax = rayOri.z;
	float preZ = rayOri.z;
	
	float2 screenPoint = screenRayOri;
	float3 Q = QOri;
	float k = kOri;

	// float2 offsetUV = (fmod(floor(screenRayOri), 4.0));
	// float ditherValue = SAMPLE_TEXTURE2D(_DitherMap, sampler_DitherMap, offsetUV / 4.0);
	// 	
	// screenPoint += dp * ditherValue;
	// Q.z += dq.z * ditherValue;
	// k += dk * ditherValue;
	
	UNITY_LOOP
	for(int i = 0; i < _maxRayMarchingStep; i++)
	{
		//向前步进一个单位
		screenPoint += dp;
		Q.z += dq.z;
		k += dk;
		
		//得到步进前后两点的深度
		rayZmin = preZ;
		rayZmax = (dq.z * 0.5 + Q.z) / (dk * 0.5 + k);
		preZ = rayZmax;
		if (rayZmin > rayZmax)
		{
			swap(rayZmin, rayZmax);
		}
		
		//得到当前屏幕空间位置，交换过的xy换回来，并且根据像素宽度还原回（0,1）区间而不是屏幕区间
		hitScreenPos = permute ? screenPoint.yx : screenPoint;
		hitScreenPos.x /= _ScreenParams.x;
		hitScreenPos.y /= _ScreenParams.y;

		//计算物体遮罩 防止自遮罩
		float mask = tex2Dlod(_GBuffer1, float4(hitScreenPos.xy,0,0)).a;
		
		//转换回屏幕（0,1）区间，剔除出屏幕的反射
		if (any(hitScreenPos.xy < 0.0) || any(hitScreenPos.xy > 1.0))
			return false;
		
		//采样当前点深度图，转化为视空间的深度（负值）
		float depth = - LinearEyeDepth(tex2Dlod(_gdepth, float4(hitScreenPos,0,0)).r, _ZBufferParams);
		
		bool isBehand = (rayZmin <= depth);
		bool intersecting = isBehand && (rayZmax >= depth - _depthThickness);
		
		if (intersecting)
			return true;
	}
	return false;
}


//顶点函数
Varyings SSRVertex(Attributes input){
    Varyings output;
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    output.baseUV = input.baseUV;
    float4 clipPos = float4(input.baseUV * 2.0 - 1.0, 1.0, 1.0);
    float4 viewRay = mul(_pMatrixInv, clipPos);
    output.viewRay = viewRay.xyz / viewRay.w;
    
    return output;
}

//片元函数
float4 SSRFragment (Varyings input, out float depthOut : SV_Depth) : SV_TARGET {
    float depth = tex2D(_gdepth, input.baseUV).r;
    depthOut = depth;
    
    //最终输出结果
    float4 final = float4(0.0, 0.0, 0.0, 0.0);
    //采样GBuffer
    float4 GBuffer1 = tex2D(_GBuffer1, input.baseUV);
     // SSR遮罩为0 直接返回 只接受遮罩为1的反射
     if(GBuffer1.a == 0.0)
     {
         return final;
     }
    
    float3 normalWS = GBuffer1.rgb * 2.0 - 1.0;
    float3 normalVS = normalize(mul(_vMatrix, normalWS));
    
    
    // 反投影重建坐标
    float3 positionVS = input.viewRay * Linear01Depth(depth,_ZBufferParams);
    
    float3 viewDir = normalize(positionVS);
    float3 reflectDir = reflect(viewDir, normalVS);

    
    float2 hitScreenPos = float2(0,0);
    
	// ViewSpaceRayMarching
    if (binarySearchRayMarching(positionVS, reflectDir, hitScreenPos))
    {
        final += SAMPLE_TEXTURE2D(_LightPassTexture, sampler_LightPassTexture, hitScreenPos);
    }
	
	// // ScreenSpaceRayMarching
 //    if (screenSpaceRayMarching(positionVS, reflectDir, hitScreenPos))
 //    {
 //        final += SAMPLE_TEXTURE2D(_LightPassTexture, sampler_LightPassTexture, hitScreenPos);
 //    	// final += float4(1.0, 1.0, 1.0, 0.0);
 //    }
	
    
    return final;

}

//顶点函数
Varyings DefaultPassVertex(Attributes input){
    Varyings output;
    float3 positionWS = TransformObjectToWorld(input.positionOS);
    output.positionCS = TransformWorldToHClip(positionWS);
    output.baseUV = input.baseUV;
    output.viewRay = 0.0;
    
    return output;
}

float4 GetSource(float2 screenUV)   
{  
    return SAMPLE_TEXTURE2D_LOD(_SSRBlurSource, sampler_linear_clamp, screenUV, 0); 
}

float4 GetSourceTexelSize ()   
{  
    return _SSRBlurSource_TexelSize;  
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

// //叠加
// float4 BlurFinalFragment(Varyings input, out float depthOut : SV_Depth) : SV_TARGET{
//     float depth = tex2D(_gdepth, input.baseUV).r;
//     depthOut = depth;
//     
//     float4 lightRes = SAMPLE_TEXTURE2D(_LightPassTexture, sampler_LightPassTexture, input.baseUV);
//     float4 reflectRes = GetSource(input.baseUV);
//     float4 final = lightRes + reflectRes;
//     return float4(final.xyz, 1.0);
// }


#endif