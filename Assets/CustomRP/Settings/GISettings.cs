using UnityEngine;


//阴影属性设置  
[System.Serializable]  
public class GISettings {
    public bool allowIBL = false;
    // IBL 贴图
    public Cubemap diffuseIBL;
    public Cubemap specularIBL;
    public Texture brdfLut;

    public bool allowRSM = false;
    [Range(0f, 4f)]  
    public float rsmIntensity;


}