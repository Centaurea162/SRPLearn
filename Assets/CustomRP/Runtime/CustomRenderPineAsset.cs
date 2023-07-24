using Unity.VisualScripting;
using UnityEngine;  
using UnityEngine.Rendering;  

//该标签会让你在Project下右键->Create菜单中添加一个新的子菜单  
[CreateAssetMenu(menuName ="Rendering/CreateCustomRenderPipeline")]  
public class CustomRenderPineAsset : RenderPipelineAsset  
{  
    
    //定义合批状态字段  
    [SerializeField] private bool useDynamicBatching = true,
        useGPUInstancing = true,
        useSRPBatcher = true,
        useLightsPerObject = true,
        tileBasedLightCulling = false,
        allowHDR = true;



    //IBL设置  
    [SerializeField] 
    DeferredShadingSetting deferredShadingSetting = default;
    
    //IBL设置  
    [SerializeField] 
    GISettings giSettings = default;

    //阴影设置  
    [SerializeField]  
    ShadowSettings shadows = default;

    //后效资产配置  
    [SerializeField]  
    PostFXSettings postFXSettings = default; 
    
    public enum ColorLUTResolution   
    {  
        _16 = 16,   
        _32 = 32,  
        _64 = 64   
    }  
    //LUT分辨率    
    [SerializeField]  
    ColorLUTResolution colorLUTResolution = ColorLUTResolution._32;
    
    
    //重写抽象方法，需要返回一个RenderPipeline实例对象  
    protected override RenderPipeline CreatePipeline()   
    {  
        return new CustomRenderPipeline(allowHDR, useDynamicBatching, useGPUInstancing, useSRPBatcher, useLightsPerObject, tileBasedLightCulling, deferredShadingSetting, shadows, postFXSettings, giSettings, (int)colorLUTResolution);  
    }

    
 


}