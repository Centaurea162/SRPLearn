using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;


public partial class CameraRenderer {
        private ScriptableRenderContext context;
        private Camera camera;
        private const string bufferName = "Render Camera";  
        private CommandBuffer buffer = new CommandBuffer {name = bufferName};
        private static ShaderTagId unlitShaderTagId = new ShaderTagId("SRPDefaultUnlit");
        private static ShaderTagId litShaderTagId = new ShaderTagId("CustomForwardLit");
        private Lighting lighting = new Lighting();
        PostFXStack postFXStack = new PostFXStack();

        static int frameBufferId = Shader.PropertyToID("_CameraFrameBuffer");
        
        static int lightPassResId = Shader.PropertyToID("_LightPassRes");
        static int lightPassTextureId = Shader.PropertyToID("_LightPassTexture");
        
        static int ditherMapId = Shader.PropertyToID("_DitherMap");
        static int reflectionTextureId = Shader.PropertyToID("_ReflectionTexture");
        static int SSRBlurSourceId = Shader.PropertyToID("_SSRBlurSource");
        static int SSRHorizontalBlurResId = Shader.PropertyToID("_SSRHorizontalBlurResId");
        static int SSRVerticalBlurResId = Shader.PropertyToID("_SSRVerticalBlurResId");
        
        static int RSMResId = Shader.PropertyToID("_RSMResId");
        static int RSMBlurSourceId = Shader.PropertyToID("_RSMBlurSource");
        static int RSMHorizontalBlurResId = Shader.PropertyToID("_RSMHorizontalBlurResId");
        static int RSMVerticalBlurResId = Shader.PropertyToID("_RSMVerticalBlurResId");
        
        static int deferredTileParamsId = Shader.PropertyToID("_DeferredTileParams"); 
        static int litDeferredTileParamsId = Shader.PropertyToID("_LitDeferredTileParams");
        static int cameraNearPlaneLBId = Shader.PropertyToID("_CameraNearPlaneLB"); 
        static int cameraNearBasisHId = Shader.PropertyToID("_CameraNearBasisH"); 
        static int cameraNearBasisVId = Shader.PropertyToID("_CameraNearBasisV"); 
        
        static int RWTileLightsArgsBufferId = Shader.PropertyToID("_RWTileLightsArgsBuffer");
        static int RWTileLightsIndicesBufferId = Shader.PropertyToID("_RWTileLightsIndicesBuffer");
        
        static int TileLightsArgsBufferId = Shader.PropertyToID("_TileLightsArgsBuffer");
        static int TileLightsIndicesBufferId = Shader.PropertyToID("_TileLightsIndicesBuffer");
        
        
        static int gdepthId = Shader.PropertyToID("_gdepth"); 
    
        
        static CameraSettings defaultCameraSettings = new CameraSettings();  
        
        bool useHDR; 
        
        RenderTexture gdepth;                                               // depth attachment
        RenderTexture[] gbuffers = new RenderTexture[4];                    // color attachments
        RenderTargetIdentifier gdepthID; 
        RenderTargetIdentifier[] gbufferID = new RenderTargetIdentifier[4]; // tex ID
        
        
        //Gbuffer所用的vp矩阵
        Matrix4x4 vpMatrix;
        Matrix4x4 vpMatrixInv;
        
        //SSR所用的p矩阵
        Matrix4x4 pMatrix;
        Matrix4x4 pMatrixInv;

        private ComputeShader tileLightCullingComputeShader;

        static private int tileSizeX = 16;
        static private int tileSizeY = 16;
        
        
        
        private ComputeBuffer _tileLightsIndicesBuffer;
        private ComputeBuffer _tileLightsArgsBuffer;
        
        

        public CameraRenderer() {
                // 创建纹理
                gdepth = new RenderTexture(1920, 1080, 24, RenderTextureFormat.Depth, RenderTextureReadWrite.Linear);
                gdepth.filterMode = FilterMode.Point;
                gbuffers[0] = new RenderTexture(1920, 1080, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
                gbuffers[1] = new RenderTexture(1920, 1080, 0, RenderTextureFormat.ARGB2101010, RenderTextureReadWrite.Linear);
                gbuffers[2] = new RenderTexture(1920, 1080, 0, RenderTextureFormat.RGB111110Float, RenderTextureReadWrite.Linear);
                gbuffers[3] = new RenderTexture(1920, 1080, 0, RenderTextureFormat.RGB111110Float, RenderTextureReadWrite.Linear);

                // 给纹理 ID 赋值
                gdepthID = gdepth;
                for (int i = 0; i < 4; i++) { 
                        gbufferID[i] = gbuffers[i];
                }
        }
        
        public void Render(ScriptableRenderContext context, Camera camera, 
                bool allowHDR,
                bool useDynamicBatching, bool useGPUInstancing,
                bool useLightsPerObject, 
                bool tileBasedLightCulling,
                DeferredShadingSetting deferredShadingSetting,
                ShadowSettings shadowSettings, 
                PostFXSettings postFXSettings,
                GISettings giSettings,
                int colorLUTResolution) {
                
                this.context = context;
                this.camera = camera;
                if (tileBasedLightCulling) {
                        tileLightCullingComputeShader = Resources.Load<ComputeShader>("Shaders/TilebasedLightCulling");
                }
                
                
                var crpCamera = camera.GetComponent<CustomRenderPipelineCamera>();  
                CameraSettings cameraSettings = crpCamera ? crpCamera.Settings : defaultCameraSettings;
                
                //设置命令缓冲区的名字   "Editor Only"
                PrepareBuffer();  
                // 在Game视图绘制的几何体也绘制到Scene视图中  
                PrepareForSceneWindow();  
                
                if (!Cull(shadowSettings.maxDistance)) {
                        return;
                }
                useHDR = allowHDR && camera.allowHDR; 
                
                // 添加命令，以开始对指定Name的配置文件进行采样。
                buffer.BeginSample(SampleName);
                ExecuteBuffer();
                
                bool isCulling = lighting.Setup(camera ,context, cullingResults, shadowSettings, giSettings, useLightsPerObject, tileBasedLightCulling, tileLightCullingComputeShader);
                postFXStack.Setup(context, camera, postFXSettings, useHDR, colorLUTResolution, cameraSettings.finalBlendMode);
                buffer.EndSample(SampleName);
                context.SetupCameraProperties(camera);

                if (!deferredShadingSetting.DeferredShading && tileBasedLightCulling && isCulling) {
                        //用于为计算分块光照索引提供深度图
                        PreDepth(tileBasedLightCulling);
                        //计算分块光照索引
                        TilebasedLightCulling(tileBasedLightCulling, isCulling);
                }
                //设置相机的属性和矩阵 同时 若开启了后处理 则将结果渲染到frameBufferId 以便后续进行后处理渲染
                Setup();
                
                if (deferredShadingSetting.DeferredShading) {

                        //绘制gbuffer
                        DrawGBuffer();
                        //计算分块光照索引
                        TilebasedLightCulling(tileBasedLightCulling, isCulling);
                        //渲染光照
                        DrawDeferredLight(deferredShadingSetting.AllowSSR, giSettings);
                        //SSR
                        ScreenSpaceReflection(deferredShadingSetting.AllowSSR, deferredShadingSetting);
                        //RSM
                        ReflectiveShadowMap(giSettings);
                        GIAdd(deferredShadingSetting.AllowSSR, giSettings);
                        context.DrawSkybox(camera);
                }
                else {
                        //绘制几何体  
                        DrawVisibleGeometry(useDynamicBatching, useGPUInstancing, useLightsPerObject);  
                        //绘制SRP不支持的着色器类型  
                        DrawUnsupportedShaders();
                }
                
                

                // 绘制Gizmos  
                // DrawGizmos(); 
                
                DrawGizmosBeforeFX();  
                if (postFXStack.IsActive)  
                {   
                        postFXStack.Render(frameBufferId);  
                }  
                DrawGizmosAfterFX();
                
                // 释放申请的RT内存空间
                Cleanup();
                
                // 提交绘制命令
                buffer.EndSample(SampleName);
                context.Submit();
                CleanupAfterDraw();
                
        }

        // 存储了我们相机剔除后的所有视野内可见物体的数据信息  
        CullingResults cullingResults;  
        
        /// <summary>  
        /// 剔除  
        /// </summary>  
        /// <returns></returns>
        bool Cull(float maxShadowDistance) {

                // 得到需要进行剔除检查的所有物体 存入p
                if (camera.TryGetCullingParameters(out ScriptableCullingParameters p)) {
                        //得到最大阴影距离,和相机远截面作比较，取最小的那个作为阴影距离  
                        p.shadowDistance = Mathf.Min(maxShadowDistance, camera.farClipPlane);  
                        cullingResults = context.Cull(ref p);  
                        return true;  
                }

                return false;
        }



        
        /// <summary>  
        /// 绘制可见物  
        /// </summary>  
        void DrawVisibleGeometry(bool useDynamicBatching, bool useGPUInstancing, bool useLightsPerObject) {
                

                //逐对象光源
                PerObjectData lightsPerObjectFlags = useLightsPerObject ? PerObjectData.LightData | PerObjectData.LightIndices : PerObjectData.None;  
                
                //设置绘制顺序和指定渲染相机  
                var sortingSettings = new SortingSettings(camera)  {  
                        criteria = SortingCriteria.CommonOpaque  
                };  
                
                //设置渲染的Shader Pass和排序模式  
                var drawingSettings = new DrawingSettings(unlitShaderTagId, sortingSettings) {
                        //设置渲染时批处理的使用状态  
                        enableDynamicBatching = useDynamicBatching,  
                        enableInstancing = useGPUInstancing,
                        perObjectData = PerObjectData.Lightmaps | PerObjectData.ShadowMask |
                                        PerObjectData.LightProbe | PerObjectData.LightProbeProxyVolume |
                                        PerObjectData.OcclusionProbe | PerObjectData.OcclusionProbeProxyVolume |
                                        PerObjectData.ReflectionProbes | lightsPerObjectFlags  
                };  
                drawingSettings.SetShaderPassName(1, litShaderTagId);
                
                //设置哪些类型的渲染队列可以被绘制   只绘制RenderQueue为opaque不透明的物
                var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);  
                // 1.绘制不透明物体  
                context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);  
   
                // 2.绘制天空盒  
                context.DrawSkybox(camera);  
                
                sortingSettings.criteria = SortingCriteria.CommonTransparent;  
                drawingSettings.sortingSettings = sortingSettings;  
                // 只绘制RenderQueue为transparent透明的物体  
                filteringSettings.renderQueueRange = RenderQueueRange.transparent;  
                // 3.绘制透明物体  
                context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);
                
        }

        void DrawGBuffer() {
                // 设置相机矩阵
                Matrix4x4 viewMatrix = camera.worldToCameraMatrix;
                Matrix4x4 projMatrix = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
                vpMatrix = projMatrix * viewMatrix;
                vpMatrixInv = vpMatrix.inverse;
                buffer.SetGlobalMatrix("_vpMatrix", vpMatrix);
                buffer.SetGlobalMatrix("_vpMatrixInv", vpMatrixInv);
                // 清屏
                buffer.SetRenderTarget(gbufferID, gdepthID);
                buffer.ClearRenderTarget(true, true, Color.clear);
                //  gbuffer 
                buffer.SetGlobalTexture("_gdepth", gdepth);
                for (int i = 0; i < 4; i++) {
                        buffer.SetGlobalTexture("_GBuffer"+i, gbuffers[i]);
                }
                
                ExecuteBuffer();   
        
                // config settings
                ShaderTagId shaderTagId = new ShaderTagId("gbuffer");   // 使用 LightMode 为 gbuffer 的 shader
                //设置绘制顺序和指定渲染相机 
                SortingSettings sortingSettings = new SortingSettings(camera);
                DrawingSettings drawingSettings = new DrawingSettings(shaderTagId, sortingSettings);
                //设置哪些类型的渲染队列可以被绘制 
                FilteringSettings filteringSettings = FilteringSettings.defaultValue; 
        
                
                // 绘制不透明物体 延迟渲染只支持不透明物体
                context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);
        }

        void PreDepth(bool tileBasedLightCulling) {
                if (!tileBasedLightCulling) {
                        return;
                }
                // 清屏
                buffer.SetRenderTarget(gdepthID);
                buffer.ClearRenderTarget(true, true, Color.clear);
                buffer.SetGlobalTexture("_gdepth", gdepth);
                ExecuteBuffer();
                
                // config settings
                ShaderTagId shaderTagId = new ShaderTagId("DepthOnly");   // 使用 LightMode 为 DepthOnly 的 shader
                //设置绘制顺序和指定渲染相机 
                SortingSettings sortingSettings = new SortingSettings(camera);
                DrawingSettings drawingSettings = new DrawingSettings(shaderTagId, sortingSettings);
                //设置哪些类型的渲染队列可以被绘制 
                FilteringSettings filteringSettings = FilteringSettings.defaultValue; 
        
                
                // 绘制不透明物体 延迟渲染只支持不透明物体
                context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);
                //  gbuffer 
                
                ExecuteBuffer();
                
        }        
        
        void TilebasedLightCulling(bool TileBasedDeferredShading, bool isCulling) {
                if (TileBasedDeferredShading == false || isCulling == false) {
                        return;
                }
                
                int kernelIndex = tileLightCullingComputeShader.FindKernel("CSMain");
                
                
                //计算compute shader所需的参数 包括线程数 偏移所需的宽和高向量
                var screenWidth = camera.pixelWidth;
                var screenHeight = camera.pixelHeight;
                var tileCountX = Mathf.CeilToInt(screenWidth * 1f / tileSizeX);
                var tileCountY = Mathf.CeilToInt(screenHeight * 1f / tileSizeY);
                
                var nearPlaneZ = camera.nearClipPlane;
                var nearPlaneHeight = Mathf.Tan(Mathf.Deg2Rad * camera.fieldOfView * 0.5f) * nearPlaneZ * 2;
                var nearPlaneWidth = camera.aspect * nearPlaneHeight;
                
                var CameraNearPlaneLB = new Vector4( -nearPlaneWidth/2, -nearPlaneHeight/2, nearPlaneZ, 0);
                var basisH = new Vector4(tileSizeX * nearPlaneWidth / screenWidth, 0, 0, 0);
                var basisV = new Vector4(0, tileSizeY * nearPlaneHeight / screenHeight, 0, 0);
                
                buffer.SetGlobalVector(litDeferredTileParamsId, new Vector4(tileSizeX, tileSizeY, tileCountX, tileCountY));
                buffer.SetComputeVectorParam(tileLightCullingComputeShader, deferredTileParamsId, new Vector4(tileSizeX, tileSizeY, tileCountX, tileCountY));
                buffer.SetComputeVectorParam(tileLightCullingComputeShader, cameraNearPlaneLBId, CameraNearPlaneLB);
                buffer.SetComputeVectorParam(tileLightCullingComputeShader, cameraNearBasisHId, basisH);
                buffer.SetComputeVectorParam(tileLightCullingComputeShader, cameraNearBasisVId, basisV);
                buffer.SetComputeTextureParam(tileLightCullingComputeShader, kernelIndex, gdepthId, gdepth);
                
                //设置最后传送给lit shader的buffer 包括每个tile的灯光数和对应的灯光索引
                var tileCount = tileCountX * tileCountY;
                var argsBufferSize = tileCount;
                int MaxLightCountPerTile = 32;
                var indicesBufferSize = tileCount * MaxLightCountPerTile;
                
                _tileLightsArgsBuffer = new ComputeBuffer(argsBufferSize,sizeof(uint));
                buffer.SetComputeBufferParam(tileLightCullingComputeShader, kernelIndex, RWTileLightsArgsBufferId, _tileLightsArgsBuffer);
                _tileLightsIndicesBuffer = new ComputeBuffer(indicesBufferSize,sizeof(uint));
                buffer.SetComputeBufferParam(tileLightCullingComputeShader, kernelIndex, RWTileLightsIndicesBufferId, _tileLightsIndicesBuffer);
                buffer.DispatchCompute(tileLightCullingComputeShader, kernelIndex, tileCountX, tileCountY,1);
                ExecuteBuffer();
                context.Submit();
                
                // for debug
                // int[] tileLightsArgsBuffer = new int[30];
                // Array arrayArgs = Array.CreateInstance(typeof(int), 30);
                // _tileLightsArgsBuffer.GetData(arrayArgs);
                // // Debug.Log(arrayArgs.GetValue(1));
                // int[] tileLightsIndicesBuffer = new int[1024];
                // Array arrayIndex = Array.CreateInstance(typeof(int), 1024);
                // _tileLightsIndicesBuffer.GetData(arrayIndex);
                //
                // for (int i = 0; i < 32; i++) {
                //         Debug.Log(i + ":" + arrayIndex.GetValue(i));
                // }
                
                buffer.SetGlobalBuffer(TileLightsArgsBufferId, _tileLightsArgsBuffer);
                buffer.SetGlobalBuffer(TileLightsIndicesBufferId, _tileLightsIndicesBuffer);

                
        }
        

        void DrawDeferredLight(bool AllowSSR, GISettings giSettings) {
                
                Material mat = new Material(Shader.Find("CustomRP/DeferredLit"));
                if (AllowSSR || giSettings.allowRSM) {
                        buffer.GetTemporaryRT(lightPassResId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default); 
                        buffer.Blit(null, lightPassResId, mat);
                        //设置lightpass渲染结果为全局纹理
                        buffer.SetGlobalTexture(lightPassTextureId,lightPassResId);
                }else if (postFXStack.IsActive && !AllowSSR) {
                        buffer.Blit(null, frameBufferId, mat);
                }else {
                        buffer.Blit(null, BuiltinRenderTextureType.CameraTarget, mat);
                }
                
                ExecuteBuffer();
        }

        private Texture2D GenerateDitherMap()
        {
                int texSize = 4;
                var ditherMap = new Texture2D(texSize, texSize, TextureFormat.Alpha8, false, true);
                ditherMap.filterMode = FilterMode.Point;
                Color32[] colors = new Color32[texSize * texSize];
 
                colors[0] = GetDitherColor(0.0f);
                colors[1] = GetDitherColor(8.0f);
                colors[2] = GetDitherColor(2.0f);
                colors[3] = GetDitherColor(10.0f);
 
                colors[4] = GetDitherColor(12.0f);
                colors[5] = GetDitherColor(4.0f);
                colors[6] = GetDitherColor(14.0f);
                colors[7] = GetDitherColor(6.0f);
 
                colors[8] = GetDitherColor(3.0f);
                colors[9] = GetDitherColor(11.0f);
                colors[10] = GetDitherColor(1.0f);
                colors[11] = GetDitherColor(9.0f);
 
                colors[12] = GetDitherColor(15.0f);
                colors[13] = GetDitherColor(7.0f);
                colors[14] = GetDitherColor(13.0f);
                colors[15] = GetDitherColor(5.0f);
 
                ditherMap.SetPixels32(colors);
                ditherMap.Apply();
                return ditherMap;
        }
 
        private Color32 GetDitherColor(float value)
        {
                byte byteValue = (byte)(value / 16.0f * 255);
                return new Color32(byteValue, byteValue, byteValue, byteValue);
        }
        
        
        void ScreenSpaceReflection(bool AllowSSR, DeferredShadingSetting deferredShadingSetting) {
                if (AllowSSR == false) {
                        return;
                }
                buffer.EnableShaderKeyword("_SCREEN_SPACE_REFLECTION");
                //设置RayMarching参数
                buffer.SetGlobalFloat("_maxRayMarchingDistance",deferredShadingSetting.ScreenSpaceReflectionSetting.maxRayMarchingDistance);
                buffer.SetGlobalInt("_maxRayMarchingStep",deferredShadingSetting.ScreenSpaceReflectionSetting.maxRayMarchingStep);
                buffer.SetGlobalInt("_maxRayMarchingBinarySearchCount",deferredShadingSetting.ScreenSpaceReflectionSetting.maxRayMarchingBinarySearchCount);
                buffer.SetGlobalFloat("_rayMarchingStepSize",deferredShadingSetting.ScreenSpaceReflectionSetting.rayMarchingStepSize);
                buffer.SetGlobalFloat("_depthThickness",deferredShadingSetting.ScreenSpaceReflectionSetting.depthThickness / camera.farClipPlane);
                
                
                // 设置变换到视空间所需矩阵
                pMatrix = camera.projectionMatrix;
                pMatrixInv = pMatrix.inverse;
                buffer.SetGlobalMatrix("_pMatrix", pMatrix);
                buffer.SetGlobalMatrix("_pMatrixInv", pMatrixInv);
                var clipToScreenMatrix = new Matrix4x4();
                // (clip * 0.5 + 0.5)变换到screenspace，*width或height，得到真正的像素位置
                clipToScreenMatrix.SetRow(0, new Vector4(Screen.width * 0.5f, 0, 0, Screen.width * 0.5f));
                clipToScreenMatrix.SetRow(1, new Vector4(0, Screen.height * 0.5f, 0, Screen.height * 0.5f));
                clipToScreenMatrix.SetRow(2, new Vector4(0, 0, 1.0f, 0));
                clipToScreenMatrix.SetRow(3, new Vector4(0, 0, 0, 1.0f));
                var viewToScreenMatrix = clipToScreenMatrix * pMatrix;
                buffer.SetGlobalMatrix("_ViewToScreenMatrix", viewToScreenMatrix);
                
                // 扰动图 用于增加随机性 同时减少步进次数
                Texture2D ditherMap =  GenerateDitherMap();
                buffer.SetGlobalTexture(ditherMapId, ditherMap);


                buffer.GetTemporaryRT(reflectionTextureId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
                Material mat = new Material(Shader.Find("Hidden/Custom RP/SSR"));
                buffer.Blit(null, reflectionTextureId, mat, 0);
                ExecuteBuffer();
                
                //BlurPass
                buffer.SetGlobalTexture(SSRBlurSourceId, reflectionTextureId);
                buffer.GetTemporaryRT(SSRHorizontalBlurResId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
                buffer.Blit(null, SSRHorizontalBlurResId, mat, 1);
                
                buffer.SetGlobalTexture(SSRBlurSourceId, SSRHorizontalBlurResId);
                buffer.GetTemporaryRT(SSRVerticalBlurResId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
                buffer.Blit(null, SSRVerticalBlurResId, mat, 2);
                
                buffer.SetGlobalTexture(SSRBlurSourceId, SSRVerticalBlurResId);

                ExecuteBuffer();
                

                
        }

        void ReflectiveShadowMap(GISettings giSettings) {
                if (!giSettings.allowRSM) {
                        return;
                }
                
                Material mat = new Material(Shader.Find("Hidden/Custom RP/RSM"));
                buffer.GetTemporaryRT(RSMResId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
                buffer.Blit(null, RSMResId, mat, 0);

                
                //BlurPass
                buffer.SetGlobalTexture(RSMBlurSourceId, RSMResId);
                buffer.GetTemporaryRT(RSMHorizontalBlurResId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
                buffer.Blit(null, RSMHorizontalBlurResId, mat, 1);

                
                buffer.SetGlobalTexture(RSMBlurSourceId, RSMHorizontalBlurResId);
                buffer.GetTemporaryRT(RSMVerticalBlurResId, Screen.width, Screen.height, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
                buffer.Blit(null, RSMVerticalBlurResId, mat, 2);

                
                
                buffer.SetGlobalTexture(RSMBlurSourceId, RSMVerticalBlurResId);
                ExecuteBuffer();
                


        }

        void GIAdd(bool allowSSR, GISettings giSettings) {
                if (!allowSSR && !giSettings.allowRSM) {
                        return;
                }
                
                
                Material mat = new Material(Shader.Find("Hidden/Custom RP/RSM"));
                //叠加
                if (postFXStack.IsActive) {
                        buffer.Blit(null, frameBufferId, mat, 3);
                }
                else {
                        buffer.Blit(null, BuiltinRenderTextureType.CameraTarget, mat, 3);
                }
                ExecuteBuffer();

                if (allowSSR) {
                        buffer.ReleaseTemporaryRT(reflectionTextureId);
                        buffer.ReleaseTemporaryRT(SSRHorizontalBlurResId);
                        buffer.ReleaseTemporaryRT(SSRVerticalBlurResId);
                }

                if (giSettings.allowRSM) {
                        buffer.ReleaseTemporaryRT(RSMResId);
                        buffer.ReleaseTemporaryRT(RSMHorizontalBlurResId);
                        buffer.ReleaseTemporaryRT(RSMVerticalBlurResId);
                }
                buffer.ReleaseTemporaryRT(lightPassResId);



        }

        // 设置相机的属性和矩阵
        void Setup() {
                
                
                /*
                首先在Setup方法中通过camera.clearFlags得到相机的CameraClearFlags对象。需要注意的是，
                这是一个枚举，枚举值从小到大分别是Skybox，Color，Depth和Nothing。最后一个值代表什么都不清除，
                其它三个都会清除深度缓冲区，所以这是一个清除量递减的枚举。
                */
                // 得到相机的clear flags
                CameraClearFlags flags = camera.clearFlags;
                
                if (postFXStack.IsActive){  
                        //因此当后处理特效栈被启用时，应当始终清除颜色和深度缓冲，我们在Setup方法中对相机的ClearFlags进行强制设置。
                        if (flags > CameraClearFlags.Color)  
                        {   
                                flags = CameraClearFlags.Color;  
                        }  
                        buffer.GetTemporaryRT(frameBufferId, camera.pixelWidth, camera.pixelHeight,32, FilterMode.Bilinear, 
                                useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default);
                        buffer.SetRenderTarget(frameBufferId,RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
                }
 



                //设置相机清除状态  大于小于号对应枚举的值 传入的参数为前两个为bool 代表是否清除深度缓冲,颜色缓冲,
                buffer.ClearRenderTarget(flags <= CameraClearFlags.Depth, 
                                         flags == CameraClearFlags.Color,
                                         flags == CameraClearFlags.Color ? camera.backgroundColor.linear : Color.clear
                                        );
                buffer.BeginSample(SampleName);
                

                ExecuteBuffer();
                
        }
        
        


        void Cleanup()  
        {  
                
                lighting.Cleanup();
                if (postFXStack.IsActive)  
                {   
                        buffer.ReleaseTemporaryRT(frameBufferId);  
                }
                
        }
        
        void CleanupAfterDraw()  
        {  
                if (_tileLightsIndicesBuffer != null || _tileLightsArgsBuffer != null) {
                        _tileLightsIndicesBuffer.Dispose();
                        _tileLightsArgsBuffer.Dispose();
                }
        }
        
        /// <summary>
        /// 执行缓冲区命令
        /// </summary>
        void ExecuteBuffer()
        {
                context.ExecuteCommandBuffer(buffer);
                buffer.Clear();
        }
        
        
        /// <summary>
        /// 提交命令缓冲区
        /// </summary>
        void Submit()
        {
                buffer.EndSample(SampleName);
                ExecuteBuffer();
                context.Submit();
        }
        
}