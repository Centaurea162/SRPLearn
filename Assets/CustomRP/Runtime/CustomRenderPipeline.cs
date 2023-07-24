using UnityEngine;  
using UnityEngine.Rendering;  

public partial class CustomRenderPipeline : RenderPipeline {
    
    private CameraRenderer renderer = new CameraRenderer();
    
    bool allowHDR;  
    //测试SRP合批启用 
    bool useDynamicBatching, useGPUInstancing, useLightsPerObject, tileBasedLightCulling, useReflectiveShadowMaps;


    DeferredShadingSetting deferredShadingSetting;
    ShadowSettings shadowSettings;
    PostFXSettings postFXSettings;  
    GISettings giSettings; 
    
    int colorLUTResolution;  
    
    public CustomRenderPipeline(bool allowHDR, bool useDynamicBatching, bool useGPUInstancing, bool useSRPBatcher, bool useLightsPerObject,bool tileBasedLightCulling, DeferredShadingSetting deferredShadingSetting, ShadowSettings shadowSettings, PostFXSettings postFXSettings,GISettings giSettings, int colorLUTResolution) {
        
        
        this.colorLUTResolution = colorLUTResolution; 
        this.allowHDR = allowHDR; 
        //设置合批启用状态  
        this.useDynamicBatching = useDynamicBatching;  
        this.useGPUInstancing = useGPUInstancing;  
        this.useLightsPerObject = useLightsPerObject;
        this.tileBasedLightCulling = tileBasedLightCulling;
        this.deferredShadingSetting = deferredShadingSetting;
        GraphicsSettings.useScriptableRenderPipelineBatching = useSRPBatcher;
        
        this.shadowSettings = shadowSettings;
        this.postFXSettings = postFXSettings;
        this.giSettings = giSettings;
        
        //灯光使用线性强度  
        GraphicsSettings.lightsUseLinearIntensity = true;
        InitializeForEditor();  
    }
    
    
    protected override void Render(ScriptableRenderContext context, Camera[] cameras)  
    {
        
        foreach (Camera camera in cameras) {
            renderer.Render(context, camera, allowHDR, useDynamicBatching, useGPUInstancing, useLightsPerObject, tileBasedLightCulling, deferredShadingSetting, shadowSettings, postFXSettings, giSettings, colorLUTResolution);  
        }
    }  
}