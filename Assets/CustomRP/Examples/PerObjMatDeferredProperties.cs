using UnityEngine;

[DisallowMultipleComponent]  
public class PerObjMatDeferredProperties : MonoBehaviour {
    static int baseColorId = Shader.PropertyToID("_BaseColor");
    static int metallicId = Shader.PropertyToID("_Metallic");  
    static int roughnessId = Shader.PropertyToID("_Roughness");  
    static int ReceiveSSRId = Shader.PropertyToID("_Receive_Screen_Space_Reflection");
 
    
    [SerializeField]
    Color baseColor = Color.white;
    //定义金属度和光滑度  
    [SerializeField, Range(0f, 1f)]  
    float metallic = 0.5f;  
    [SerializeField, Range(0f, 1f)]  
    float roughness = 0.5f;  
    [SerializeField, Range(0, 1)]  
    float ReceiveSSR = 0.0f;  

    
    static MaterialPropertyBlock block;

    
    void OnValidate() {
        if (block == null) {
            block = new MaterialPropertyBlock();
        }
        
        //设置材质属性
        block.SetColor(baseColorId, baseColor);
        block.SetFloat(metallicId, metallic);  
        block.SetFloat(roughnessId, roughness);
        block.SetFloat(ReceiveSSRId, ReceiveSSR);
        GetComponent<Renderer>().SetPropertyBlock(block);
    }
    
    void Awake()  
    {  
        OnValidate();  
    }  
}