using UnityEditor;
using UnityEngine;  
using UnityEngine.Rendering;  
using static PostFXSettings;  

public partial  class PostFXStack  
{  
    const string bufferName = "Post FX";  
    CommandBuffer buffer = new CommandBuffer  
    {  
        name = bufferName  
    };
    
    enum Pass   
    {
        Copy,
        CopyDepth,
        BloomHorizontal,  
        BloomVertical,
        BloomAdd,  
        BloomScatter,  
        BloomScatterFinal, 
        BloomPrefilter,
        BloomPrefilterFireflies,
        ColorGradingNone,
        ColorGradingReinhard,
        ColorGradingNeutral,
        ColorGradingACES,
        Final

        
    }
    
    ScriptableRenderContext context;
    Camera camera;  
    PostFXSettings settings;  

    
    public bool IsActive => settings != null;
    bool useHDR;  
    
    static int frameBufferId = Shader.PropertyToID("_CameraFrameBuffer"); 
    static int fxSourceId = Shader.PropertyToID("_PostFXSource");
    int fxSource2Id = Shader.PropertyToID("_PostFXSource2");
    int bloomBucibicUpsamplingId = Shader.PropertyToID("_BloomBicubicUpsampling");
    int bloomPrefilterId = Shader.PropertyToID("_BloomPrefilter");
    int bloomThresholdId = Shader.PropertyToID("_BloomThreshold");
    int bloomIntensityId = Shader.PropertyToID("_BloomIntensity");  
    int bloomResultId = Shader.PropertyToID("_BloomResult");
    
    int colorAdjustmentsId = Shader.PropertyToID("_ColorAdjustments");  
    int colorFilterId = Shader.PropertyToID("_ColorFilter");
    
    int whiteBalanceId = Shader.PropertyToID("_WhiteBalance");  
    
    int splitToningShadowsId = Shader.PropertyToID("_SplitToningShadows");  
    int splitToningHighlightsId = Shader.PropertyToID("_SplitToningHighlights");
    
    int channelMixerRedId = Shader.PropertyToID("_ChannelMixerRed");  
    int channelMixerGreenId = Shader.PropertyToID("_ChannelMixerGreen");  
    int channelMixerBlueId = Shader.PropertyToID("_ChannelMixerBlue");  
    
    int smhShadowsId = Shader.PropertyToID("_SMHShadows");  
    int smhMidtonesId = Shader.PropertyToID("_SMHMidtones");  
    int smhHighlightsId = Shader.PropertyToID("_SMHHighlights");  
    int smhRangeId = Shader.PropertyToID("_SMHRange");  
    
    int colorGradingLUTId = Shader.PropertyToID("_ColorGradingLUT");
    int colorGradingLUTParametersId = Shader.PropertyToID("_ColorGradingLUTParameters");
    int colorGradingLUTInLogId = Shader.PropertyToID("_ColorGradingLUTInLogC");

    int finalSrcBlendId = Shader.PropertyToID("_FinalSrcBlend");  
    int finalDstBlendId = Shader.PropertyToID("_FinalDstBlend");  

    //最大纹理金字塔级别
    const int maxBloomPyramidLevels = 16;
    
    //纹理标识符  
    int bloomPyramidId;
    //LUT分辨率
    int colorLUTResolution;  
    
    CameraSettings.FinalBlendMode finalBlendMode; 
    
    public PostFXStack()   
    {  
        bloomPyramidId = Shader.PropertyToID("_BloomPyramid0");    
        for (int i = 1; i < maxBloomPyramidLevels * 2; i++)   
        {  
            Shader.PropertyToID("_BloomPyramid" + i);   
        }  
    }
    
    //获取颜色调整的配置  
    void ConfigureColorAdjustments()   
    {  
        ColorAdjustmentsSettings colorAdjustments = settings.ColorAdjustments;  
        buffer.SetGlobalVector(colorAdjustmentsId, new Vector4(  
            Mathf.Pow(2f, colorAdjustments.postExposure),  
            colorAdjustments.contrast * 0.01f + 1f,  
            colorAdjustments.hueShift * (1f / 360f),  
            colorAdjustments.saturation * 0.01f + 1f));  
        buffer.SetGlobalColor(colorFilterId, colorAdjustments.colorFilter.linear);          
    } 
    
    void ConfigureWhiteBalance()   
    {  
        WhiteBalanceSettings whiteBalance = settings.WhiteBalance;  
        buffer.SetGlobalVector(whiteBalanceId, ColorUtils.ColorBalanceToLMSCoeffs(whiteBalance.temperature, whiteBalance.tint));  
    }  
    
    void ConfigureSplitToning()  
    {  
        SplitToningSettings splitToning = settings.SplitToning;  
        Color splitColor = splitToning.shadows;  
        splitColor.a = splitToning.balance * 0.01f;  
        buffer.SetGlobalColor(splitToningShadowsId, splitColor);  
        buffer.SetGlobalColor(splitToningHighlightsId, splitToning.highlights);  
    }

    void ConfigureChannelMixer()   
    {  
        ChannelMixerSettings channelMixer = settings.ChannelMixer;  
        buffer.SetGlobalVector(channelMixerRedId, channelMixer.red);  
        buffer.SetGlobalVector(channelMixerGreenId, channelMixer.green);  
        buffer.SetGlobalVector(channelMixerBlueId, channelMixer.blue);  
    }  
    
    void ConfigureShadowsMidtonesHighlights()  
    {  
        ShadowsMidtonesHighlightsSettings smh = settings.ShadowsMidtonesHighlights;  
        buffer.SetGlobalColor(smhShadowsId, smh.shadows.linear);  
        buffer.SetGlobalColor(smhMidtonesId, smh.midtones.linear);  
        buffer.SetGlobalColor(smhHighlightsId, smh.highlights.linear);  
        buffer.SetGlobalVector(smhRangeId, new Vector4(smh.shadowsStart, smh.shadowsEnd, smh.highlightsStart, smh.highLightsEnd));  
    }  
    
    void DoColorGradingAndToneMapping(int sourceId)   
    {  
        ConfigureColorAdjustments(); 
        ConfigureWhiteBalance(); 
        ConfigureSplitToning();  
        ConfigureChannelMixer();  
        ConfigureShadowsMidtonesHighlights();  
        
        int lutHeight = colorLUTResolution;  
        int lutWidth = lutHeight * lutHeight;
        
        buffer.GetTemporaryRT(colorGradingLUTId, lutWidth, lutHeight, 0,FilterMode.Bilinear, RenderTextureFormat.DefaultHDR);
        buffer.SetGlobalVector(colorGradingLUTParametersId, new Vector4(lutHeight, 0.5f / lutWidth, 0.5f / lutHeight, lutHeight / (lutHeight - 1f)));
        
        ToneMappingSettings.Mode mode = settings.ToneMapping.mode;  
        Pass pass = Pass.ColorGradingNone + (int)mode;
        buffer.SetGlobalFloat(colorGradingLUTInLogId, useHDR && pass != Pass.ColorGradingNone ? 1f : 0f);

        //将源纹理渲染到LUT纹理中而不是相机目标
        Draw(sourceId, colorGradingLUTId, pass);  
   
        buffer.SetGlobalVector(colorGradingLUTParametersId,new Vector4(1f / lutWidth, 1f / lutHeight, lutHeight - 1f));
        // Draw(sourceId, BuiltinRenderTextureType.CameraTarget, Pass.Final);  
        DrawFinal(sourceId);  
        buffer.ReleaseTemporaryRT(colorGradingLUTId);  
    }
    
    bool DoBloom(int sourceId)   
    {
        PostFXSettings.BloomSettings bloom = settings.Bloom; 
        int width = camera.pixelWidth / 2, height = camera.pixelHeight / 2;
        if (bloom.maxIterations == 0 || bloom.intensity <= 0f ||height < bloom.downscaleLimit * 2 || width < bloom.downscaleLimit * 2)  
        {
            return false; 
        }  
        buffer.BeginSample("Bloom");
        //计算权重公式的常数部分
        Vector4 threshold;  
        threshold.x = Mathf.GammaToLinearSpace(bloom.threshold);  
        threshold.y = threshold.x * bloom.thresholdKnee;  
        threshold.z = 2f * threshold.y;  
        threshold.w = 0.25f / (threshold.y + 0.00001f);  
        threshold.y -= threshold.x;  
        buffer.SetGlobalVector(bloomThresholdId, threshold);  
        
        RenderTextureFormat format = useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default;   
        buffer.GetTemporaryRT(bloomPrefilterId, width, height, 0, FilterMode.Bilinear, format);  
        //prefilter 先指选中高于阈值的像素
        Draw(sourceId, bloomPrefilterId, bloom.fadeFireflies ? Pass.BloomPrefilterFireflies : Pass.BloomPrefilter);  
        width /= 2;  
        height /= 2; 
        int fromId = bloomPrefilterId;  
        // +1 因为 midId为 bloomPyramidId0
        int toId = bloomPyramidId + 1;  
        int i;   
        for (i = 0; i < bloom.maxIterations; i++)  
        {   
            if (height < bloom.downscaleLimit || width < bloom.downscaleLimit)  
            {   
                break;  
            }  
            int midId = toId - 1;  
            buffer.GetTemporaryRT(midId, width, height, 0, FilterMode.Bilinear, format);  
            buffer.GetTemporaryRT(toId, width, height, 0, FilterMode.Bilinear, format);  
            Draw(fromId, midId, Pass.BloomHorizontal);
            Draw(midId, toId, Pass.BloomVertical);
            // if (i == 0) {
            //     buffer.GetTemporaryRT(bloomLeadWeightId, width, height, 0, FilterMode.Bilinear, format); 
            //     Draw(midId, bloomLeadWeightId, Pass.BloomVertical);
            //     Draw(bloomLeadWeightId, toId, Pass.LeadWeight);
            // }
            // else {
            //     Draw(midId, toId, Pass.BloomVertical);
            // }
            fromId = toId;  
            toId += 2;
            width /= 2;  
            height /= 2;   
        }  
        buffer.ReleaseTemporaryRT(bloomPrefilterId);
        // Draw(fromId, BuiltinRenderTextureType.CameraTarget, Pass.Copy);  
        // Draw(fromId, BuiltinRenderTextureType.CameraTarget, Pass.BloomHorizontal);
        // buffer.SetGlobalFloat(bloomIntensityId, 1f); 
        buffer.SetGlobalFloat(bloomBucibicUpsamplingId, bloom.bicubicUpsampling ? 1f : 0f);
        Pass combinePass, finalPass;  
        float finalIntensity;  
        if (bloom.mode == PostFXSettings.BloomSettings.Mode.Additive)  
        {   
            combinePass = finalPass = Pass.BloomAdd; 
            buffer.SetGlobalFloat(bloomIntensityId, 1f);   
            finalIntensity = bloom.intensity; 
        }  
        else   
        {  
            combinePass = Pass.BloomScatter;  
            finalPass = Pass.BloomScatterFinal;  
            buffer.SetGlobalFloat(bloomIntensityId, bloom.scatter);  
            finalIntensity = Mathf.Min(bloom.intensity, 0.95f);  
        }   
        if (i > 1)  
        {   
            //释放mip1BloomCombine只进行了BloomHorizontal的纹理
            buffer.ReleaseTemporaryRT(fromId - 1);  
            //为何-5 首先 因为上次循环最后有一个多余的+2操作 所以-2是最终的mip0 -4是mip1 -5是mip2仅进行水平滤波
            toId -= 5;  
            for (i -= 1; i > 0; i--)  
            {   
                //fxSource2Id GlobalTexture为mip1 供我们在BloomCombine Pass中使用
                buffer.SetGlobalTexture(fxSource2Id, toId + 1);
                //fromId为mip0
                Draw(fromId, toId, Pass.BloomAdd);
                //释放mip0和mip1
                buffer.ReleaseTemporaryRT(fromId);  
                buffer.ReleaseTemporaryRT(toId + 1);  
                fromId = toId;  
                toId -= 2;  
            }  
 
        }  
        else  
        {  
            buffer.ReleaseTemporaryRT(bloomPyramidId);  
        }  
        buffer.SetGlobalFloat(bloomIntensityId, finalIntensity);  
        buffer.SetGlobalTexture(fxSource2Id, sourceId);  
        buffer.GetTemporaryRT(bloomResultId, camera.pixelWidth, camera.pixelHeight, 0,  
            FilterMode.Bilinear, format);  
        Draw(fromId, bloomResultId, finalPass);  
        buffer.ReleaseTemporaryRT(fromId);  
        buffer.EndSample("Bloom");  
        return true; 

    }
    
    void Draw(RenderTargetIdentifier from, RenderTargetIdentifier to, Pass pass)  
    {   
        buffer.SetGlobalTexture(fxSourceId, from);  
        buffer.SetRenderTarget(to, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        // 前三个分别是未使用的矩阵、用于后处理特效的材质和指定的Pass。第四个参数指示我们要绘制的形状，这里用MeshTopology.Triangles表示绘制成三角形。第五个参数是我们想要多少个顶点，单个三角形就是3个。
        buffer.DrawProcedural(Matrix4x4.identity, settings.Material, (int)pass, MeshTopology.Triangles, 3);  
    }  
    
    void DrawFinal(RenderTargetIdentifier from)  
    {   
        buffer.SetGlobalFloat(finalSrcBlendId, (float)finalBlendMode.source);  
        buffer.SetGlobalFloat(finalDstBlendId, (float)finalBlendMode.destination);  
        
        buffer.SetGlobalTexture(fxSourceId, from);  
        buffer.SetRenderTarget(BuiltinRenderTextureType.CameraTarget,   
            finalBlendMode.destination == BlendMode.Zero ? RenderBufferLoadAction.DontCare: RenderBufferLoadAction.Load, RenderBufferStoreAction.Store);  
        
        //设置视口    
        buffer.SetViewport(camera.pixelRect);  
        buffer.DrawProcedural(Matrix4x4.identity, settings.Material, (int)Pass.Final, MeshTopology.Triangles, 3);  
    } 
    
    public void Setup(ScriptableRenderContext context, Camera camera, PostFXSettings settings, bool useHDR, int colorLUTResolution, CameraSettings.FinalBlendMode finalBlendMode)  
    {  
        this.colorLUTResolution = colorLUTResolution;
        this.useHDR = useHDR;  
        this.context = context;  
        this.camera = camera;
        this.settings = camera.cameraType <= CameraType.SceneView ? settings : null;
        this.finalBlendMode = finalBlendMode;  
        ApplySceneViewState();
    }  
    
    public void Render(int sourceId)  
    {  
        // Draw(sourceId, BuiltinRenderTextureType.CameraTarget, Pass.Copy);  
        //调用buffer.Blit方法完成对图像的处理并显示到屏幕上
        // 第一个参数对应了源纹理，在屏幕后处理技术中，这个参数通常就是当前屏幕的渲染纹理或上一步处理后得到的渲染纹理。
        // 第二个参数是渲染目标，现在我们还没有编写用于处理图像的Shader，所以渲染目标设置为当前渲染相机的帧缓冲区。
        // buffer.Blit(sourceId, BuiltinRenderTextureType.CameraTarget);
        
        // DoBloom(sourceId);  
        // context.ExecuteCommandBuffer(buffer);  
        // buffer.Clear();
        
        if (DoBloom(sourceId))   
        {  
            DoColorGradingAndToneMapping(bloomResultId);  
            buffer.ReleaseTemporaryRT(bloomResultId);   
        }  
        else   
        {  
            DoColorGradingAndToneMapping(sourceId);   
        }  
        context.ExecuteCommandBuffer(buffer);   
        buffer.Clear();  
    }
    
}