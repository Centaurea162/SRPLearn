using System.Collections;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;


public class Lighting{
    const string bufferName = "Lighting";  
   
    CommandBuffer buffer = new CommandBuffer  
    {  
        name = bufferName  
    };
    
    //限制最大可见平行光数量为4  
    const int maxDirLightCount = 4;  
    //定义其他类型光源的最大数量  
    const int maxOtherLightCount = 256;


    static int dirLightCountId = Shader.PropertyToID("_DirectionalLightCount");  
    static int dirLightColorsId = Shader.PropertyToID("_DirectionalLightColors");  
    static int dirLightDirectionsId = Shader.PropertyToID("_DirectionalLightDirections");
    static int dirLightShadowDataId = Shader.PropertyToID("_DirectionalLightShadowData");
    static int otherLightCountId = Shader.PropertyToID("_OtherLightCount");  
    static int otherLightColorsId = Shader.PropertyToID("_OtherLightColors");  
    static int otherLightPositionsId = Shader.PropertyToID("_OtherLightPositions");
    static int otherLightDirectionsId = Shader.PropertyToID("_OtherLightDirections");
    static int otherLightSpotAnglesId = Shader.PropertyToID("_OtherLightSpotAngles");
    static int otherLightShadowDataId = Shader.PropertyToID("_OtherLightShadowData");  

    static int diffuseIBLId = Shader.PropertyToID("_diffuseIBL");
    static int specularIBLId = Shader.PropertyToID("_specularIBL");
    static int brdfLutId = Shader.PropertyToID("_brdfLut");  
    
    static int deferredOtherLightCountId = Shader.PropertyToID("_DeferredOtherLightCount");  
    static int lightPositionAndRangesId = Shader.PropertyToID("_LightPositionAndRanges"); 

    
    //存储方向光的颜色和方向  
    static Vector4[] dirLightColors = new Vector4[maxDirLightCount];  
    static Vector4[] dirLightDirections = new Vector4[maxDirLightCount];
    //存储阴影数据  
    static Vector4[] dirLightShadowData = new Vector4[maxDirLightCount];  
    //存储其它类型光源的颜色和位置数据  
    static Vector4[] otherLightColors = new Vector4[maxOtherLightCount];  
    static Vector4[] otherLightPositions = new Vector4[maxOtherLightCount];
    static Vector4[] otherLightDirections = new Vector4[maxOtherLightCount];
    static Vector4[] otherLightSpotAngles = new Vector4[maxOtherLightCount];
    static Vector4[] otherLightShadowData = new Vector4[maxOtherLightCount];
    static float[] otherLightRanges = new float[maxOtherLightCount];
    
    PositionAndRange[] otherLightPositionsAndRangesData = new PositionAndRange[maxOtherLightCount];
    

    struct MainCameraSettings
    {
        public Vector3 position;
        public Quaternion rotation;
        public float nearClipPlane;
        public float farClipPlane;
        public float aspect;
    };
    MainCameraSettings settings;
    
    
    static string lightsPerObjectKeyword = "_LIGHTS_PER_OBJECT";
    
    
    //存储相机剔除后的结果  
    CullingResults cullingResults;

    Shadows shadows = new Shadows();
    
    public struct PositionAndRange
    {
        public Vector3 pos;//等价于float3
        public float range;//等价于float4
    }
    
        
    private ComputeBuffer _LightPositionAndRanges;

    RenderTexture rsmDepth; 
    RenderTexture[] rsmBuffers = new RenderTexture[2];                    // color attachments
    RenderTargetIdentifier rsmDepthID; 
    RenderTargetIdentifier[] rsmBuffersId = new RenderTargetIdentifier[2]; // tex ID
    static int rsmLightId = -1;
    
    public Lighting() {
        // 创建纹理
        rsmDepth = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.Depth, RenderTextureReadWrite.Linear);
        rsmDepth.filterMode = FilterMode.Point;
        // normal
        rsmBuffers[0] = new RenderTexture(Screen.width, Screen.height, 0, RenderTextureFormat.ARGB2101010, RenderTextureReadWrite.Linear);
        // flux
        rsmBuffers[1] = new RenderTexture(Screen.width, Screen.height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
        
        // 给纹理 ID 赋值
        rsmDepthID = rsmDepth;
        for (int i = 0; i < 2; i++) { 
            rsmBuffersId[i] = rsmBuffers[i];
        }
    }
    
    public bool Setup(Camera camera, ScriptableRenderContext context, CullingResults cullingResults, 
        ShadowSettings shadowSettings, 
        GISettings giSettings, 
        bool useLightsPerObject, 
        bool tileBasedLightCulling,
        ComputeShader tileLightCullingComputeShader)  
    {  
        this.cullingResults = cullingResults;  
        buffer.BeginSample(bufferName);

        SetupIBL(context, giSettings);
        
        //传递阴影数据  
        shadows.Setup(context, cullingResults, shadowSettings);  
        
        //发送光源数据  
        int otherLitCount = SetupLights(useLightsPerObject);
        bool isCulling = SetupLightCulling(context, tileLightCullingComputeShader, tileBasedLightCulling, otherLitCount);
        shadows.Render();  
        SetupReflectiveShadowMaps(context, camera, cullingResults, shadowSettings, giSettings);
        
        buffer.EndSample(bufferName);  
        context.ExecuteCommandBuffer(buffer);  
        buffer.Clear();
        return isCulling;
    }


    void SetupIBL(ScriptableRenderContext context,GISettings giSettings) {
        if (giSettings.allowIBL) {
            buffer.SetGlobalTexture(diffuseIBLId, giSettings.diffuseIBL);
            buffer.SetGlobalTexture(specularIBLId, giSettings.specularIBL);
            buffer.SetGlobalTexture(brdfLutId, giSettings.brdfLut);
            buffer.EnableShaderKeyword("_IBL");
            context.ExecuteCommandBuffer(buffer);
            buffer.Clear();
        }
        else {
            buffer.DisableShaderKeyword("_IBL");
        }
    }
    
    
    //发送多个光源数据  
    int SetupLights(bool useLightsPerObject)   
    {  
        
        //拿到光源索引列表  
        NativeArray<int> indexMap = useLightsPerObject ? cullingResults.GetLightIndexMap(Allocator.Temp) : default;  
        //得到所有可见光  
        NativeArray<VisibleLight> visibleLights = cullingResults.visibleLights;
        
        int dirLightCount = 0;
        //其他类型光源数量
        int otherLightCount = 0;
        
        int i;  
        for (i = 0; i < visibleLights.Length; i++)  
        {  
            //非方向光才有索引
            int newIndex = -1;  
            VisibleLight visibleLight = visibleLights[i];  
            switch (visibleLight.lightType)  
            {  
                case LightType.Directional:  
                    if (dirLightCount < maxDirLightCount)  
                    {  
                        SetupDirectionalLight(dirLightCount++, i, ref visibleLight);  
                    }  
                    break;  
                case LightType.Point:  
                    if (otherLightCount < maxOtherLightCount)  
                    {  
                        newIndex = otherLightCount;  
                        SetupPointLight(otherLightCount++, i, ref visibleLight);  
                    }  
                    break;  
                case LightType.Spot:  
                    if (otherLightCount < maxOtherLightCount)  
                    {  
                        newIndex = otherLightCount;  
                        SetupSpotLight(otherLightCount++, i, ref visibleLight);  
                    }  
                    break;  
            }
            
            if (useLightsPerObject)  
            {  
                indexMap[i] = newIndex;  
            }
        }
        
        //消除所有不可见光的索引
        if (useLightsPerObject)  
        {  
            for (; i < indexMap.Length; i++)  
            {  
                indexMap[i] = -1;  
            }  
   
            cullingResults.SetLightIndexMap(indexMap);  
            indexMap.Dispose();   
            Shader.EnableKeyword(lightsPerObjectKeyword);  
        }else  
        {  
            Shader.DisableKeyword(lightsPerObjectKeyword);  
        }  
        
        
        
        buffer.SetGlobalInt(dirLightCountId,dirLightCount);  
        if (dirLightCount > 0)   
        {  
            buffer.SetGlobalVectorArray(dirLightColorsId, dirLightColors);  
            buffer.SetGlobalVectorArray(dirLightDirectionsId, dirLightDirections);  
            buffer.SetGlobalVectorArray(dirLightShadowDataId, dirLightShadowData);  
        }  
        
        buffer.SetGlobalInt(otherLightCountId, otherLightCount);  
        if (otherLightCount > 0)  
        {  
            buffer.SetGlobalVectorArray(otherLightColorsId, otherLightColors);  
            buffer.SetGlobalVectorArray(otherLightPositionsId, otherLightPositions);
            buffer.SetGlobalVectorArray(otherLightDirectionsId, otherLightDirections);
            buffer.SetGlobalVectorArray(otherLightSpotAnglesId, otherLightSpotAngles);
            buffer.SetGlobalVectorArray(otherLightShadowDataId, otherLightShadowData);
            
        }

        return otherLightCount;

    }


    
    
    
    //将场景主光源的光照颜色和方向传递到GPU  
    void SetupDirectionalLight(int index, int visibleIndex, ref VisibleLight visibleLight) {
        dirLightColors[index] = visibleLight.finalColor;
        dirLightDirections[index] = -visibleLight.localToWorldMatrix.GetColumn(2);
        //存储阴影数据  
        dirLightShadowData[index] = shadows.ReserveDirectionalShadows(visibleLight.light, visibleIndex); 
    }  
    
    void SetupPointLight(int index, int visibleIndex, ref VisibleLight visibleLight)  
    {
        otherLightColors[index] = visibleLight.finalColor;  
        //位置信息在本地到世界的转换矩阵的最后一列  
        Vector4 position = visibleLight.localToWorldMatrix.GetColumn(3);  
        //将光照范围的平方的倒数存储在光源位置的W分量中  
        position.w = 1f / Mathf.Max(visibleLight.range * visibleLight.range, 0.00001f);
        otherLightRanges[index] = visibleLight.range;
        otherLightPositions[index] = position;
        otherLightSpotAngles[index] = new Vector4(0f, 1f);  
        Light light = visibleLight.light;
        otherLightShadowData[index] = shadows.ReserveOtherShadows(light, visibleIndex);  

    }
    
    //将聚光灯光源的颜色、位置和方向信息存储到数组  
    void SetupSpotLight(int index, int visibleIndex, ref VisibleLight visibleLight)  
    {  
        otherLightColors[index] = visibleLight.finalColor;  
        Vector4 position = visibleLight.localToWorldMatrix.GetColumn(3);  
        position.w = 1f / Mathf.Max(visibleLight.range * visibleLight.range, 0.00001f);
        
        otherLightRanges[index] = visibleLight.range;
        otherLightPositions[index] = position;  
        //本地到世界的转换矩阵的第三列在求反得到光照方向  
        otherLightDirections[index] = -visibleLight.localToWorldMatrix.GetColumn(2);
        otherLightDirections[index].z = 1.0f;
        Light light = visibleLight.light;
        if (light.renderMode == LightRenderMode.ForcePixel) {
            rsmLightId = visibleIndex;
        }
        float innerCos = Mathf.Cos(Mathf.Deg2Rad * 0.5f * light.innerSpotAngle);  
        float outerCos = Mathf.Cos(Mathf.Deg2Rad * 0.5f * visibleLight.spotAngle);  
        float angleRangeInv = 1f / Mathf.Max(innerCos - outerCos, 0.001f);  
        otherLightSpotAngles[index] = new Vector4(angleRangeInv, -outerCos * angleRangeInv);
        otherLightShadowData[index] = shadows.ReserveOtherShadows(light, visibleIndex);
    }
    
    
    bool SetupLightCulling(ScriptableRenderContext context,ComputeShader tileLightCullingComputeShader, bool tileBasedLightCulling, int otherLitCount) {
        if (otherLitCount == 0 || tileBasedLightCulling == false || tileLightCullingComputeShader == null) {
            buffer.DisableShaderKeyword("_TILE_BASED_LIGHT_CULLING");
            return false;
        }
        //启用关键字
        buffer.EnableShaderKeyword("_TILE_BASED_LIGHT_CULLING");
        
        int kernelIndex = tileLightCullingComputeShader.FindKernel("CSMain");
        
        _LightPositionAndRanges = new ComputeBuffer(maxOtherLightCount,sizeof(float) * 4);


        //Setup Buffer
        for (int i = 0; i < maxOtherLightCount; i++) {
            // Debug.Log(otherLightPositionsAndRangesData[i].range);
            otherLightPositionsAndRangesData[i].pos = otherLightPositions[i];
            otherLightPositionsAndRangesData[i].range = otherLightRanges[i];
        }

        _LightPositionAndRanges.SetData(otherLightPositionsAndRangesData);

        tileLightCullingComputeShader.SetBuffer(kernelIndex, lightPositionAndRangesId,_LightPositionAndRanges);
        tileLightCullingComputeShader.SetInt(deferredOtherLightCountId,otherLitCount);
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
        return true;
    }

    
    // 保存相机参数, 更改为正交投影
    public void SaveMainCameraSettings(ref Camera camera)
    {
        settings.position = camera.transform.position;
        settings.rotation = camera.transform.rotation;
        settings.farClipPlane = camera.farClipPlane;
        settings.nearClipPlane = camera.nearClipPlane;
        settings.aspect = camera.aspect;
        camera.orthographic = true;
    }

    // 还原相机参数, 更改为透视投影
    public void RevertMainCameraSettings(ref Camera camera)
    {
        camera.transform.position = settings.position;
        camera.transform.rotation = settings.rotation;
        camera.farClipPlane = settings.farClipPlane;
        camera.nearClipPlane = settings.nearClipPlane;
        camera.aspect = settings.aspect;
        camera.orthographic = false;
    }

    void SetupReflectiveShadowMaps(ScriptableRenderContext context, Camera camera,
        CullingResults cullingResults, 
        ShadowSettings shadowSettings,
        GISettings giSettings) {
        if (!giSettings.allowRSM || rsmLightId == -1) {
            buffer.DisableShaderKeyword("_REFLECTIVE_SHADOW_MAP");
            return;
        }
        buffer.EnableShaderKeyword("_REFLECTIVE_SHADOW_MAP");
        SaveMainCameraSettings(ref camera);
        // 我们已有深度图 现在需要获取在光源视角下的法线 渲染结果
        cullingResults.ComputeSpotShadowMatricesAndCullingPrimitives(rsmLightId, out Matrix4x4 viewMatrix,out Matrix4x4 projectionMatrix, out ShadowSplitData splitData);
        FrustumPlanes frustumPlanes = projectionMatrix.decomposeProjection;
        
        Matrix4x4 rsmVpMatrix = projectionMatrix * viewMatrix;
        buffer.SetGlobalMatrix("_rsmVpMatrix",rsmVpMatrix);
        buffer.SetGlobalMatrix("_rsmVpMatrixInv",rsmVpMatrix.inverse);
        buffer.SetGlobalInt("_rsmLightId",rsmLightId);
        buffer.SetGlobalFloat("_rsmIntensity", giSettings.rsmIntensity);

        
        // float disPerPix = Mathf.Abs(frustumPlanes.top * 2.0f / Screen.height);
        Vector3 center = otherLightPositions[rsmLightId];
        Vector3 lightDir = otherLightDirections[rsmLightId];
        //
        // Matrix4x4 toShadowViewInv = Matrix4x4.LookAt(Vector3.zero, lightDir, Vector3.up);
        // Matrix4x4 toShadowView = toShadowViewInv.inverse;
        // // 相机坐标旋转到光源坐标系下取整
        // center = matTransform(toShadowView, center, 1.0f);
        // for(int i=0; i<3; i++)
        //     center[i] = Mathf.Floor(center[i] / disPerPix) * disPerPix;
        // center = matTransform(toShadowViewInv, center, 1.0f);
        
        
        // 配置相机
        // camera.transform.rotation = Quaternion.LookRotation(lightDir);
        // camera.transform.position = center; 
        // camera.nearClipPlane = frustumPlanes.zNear;
        // camera.farClipPlane = frustumPlanes.zFar;
        // camera.aspect = 1.0f;
        // camera.orthographicSize = Mathf.Abs(frustumPlanes.top);
        
        
        // 绘制前准备
        context.SetupCameraProperties(camera);
        buffer.SetRenderTarget(rsmBuffersId,rsmDepthID);
        buffer.ClearRenderTarget(true, true, Color.clear);
        buffer.SetGlobalTexture("_rsmDepth",rsmDepthID);
        for (int i = 0; i < 2; i++) {
            buffer.SetGlobalTexture("_rsmBuffer" + i, rsmBuffersId[i]);
        }
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();

        // 剔除
        camera.TryGetCullingParameters(out var cullingParameters);
        var rsmCullingResults = context.Cull(ref cullingParameters);
        // config settings
        ShaderTagId shaderTagId = new ShaderTagId("rsmBuffer");
        SortingSettings sortingSettings = new SortingSettings(camera);
        DrawingSettings drawingSettings = new DrawingSettings(shaderTagId, sortingSettings);
        FilteringSettings filteringSettings = FilteringSettings.defaultValue;

        // 绘制
        context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);
        // context.Submit();   // 每次 set camera 之后立即提交
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
        RevertMainCameraSettings(ref camera);
    }
    
    //释放阴影贴图RT内存  和申请的ComputeBuffer
    public void Cleanup()  
    {
        if (_LightPositionAndRanges != null) {
            _LightPositionAndRanges.Release();
        }

        shadows.Cleanup();  
    }
    
    // 齐次坐标矩阵乘法变换
    Vector3 matTransform(Matrix4x4 m, Vector3 v, float w)
    {
        Vector4 v4 = new Vector4(v.x, v.y, v.z, w);
        v4 = m * v4;
        return new Vector3(v4.x, v4.y, v4.z);
    }
    
}