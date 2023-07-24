using UnityEngine;


//阴影属性设置  
[System.Serializable]  
public class DeferredShadingSetting {
    public bool DeferredShading = false;
    // SSR
    public bool AllowSSR = false;
    
    [System.Serializable]  
    public struct SSR  
    {
        [Range(0, 1000.0f)]
        public float maxRayMarchingDistance;
        [Range(0, 256)]
        public int maxRayMarchingStep;
        [Range(0, 32)]
        public int maxRayMarchingBinarySearchCount;
        [Range(0, 8.0f)]
        public float rayMarchingStepSize;
        [Range(0, 2.0f)]
        public float depthThickness;
    }  
    
    //默认尺寸为1024  
    public SSR ScreenSpaceReflectionSetting = new SSR  
    {
        maxRayMarchingDistance = 500.0f,
        maxRayMarchingStep = 64,
        maxRayMarchingBinarySearchCount = 8,
        rayMarchingStepSize = 0.05f,  
        depthThickness = 0.01f
    };
    
    

}