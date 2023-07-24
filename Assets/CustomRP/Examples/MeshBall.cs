using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using Random = UnityEngine.Random;

/// <summary>
/// 生成1023个mesh和小球对象
/// </summary>
public class MeshBall : MonoBehaviour {
    static int baseColorId = Shader.PropertyToID("_BaseColor");  
    static int metallicId = Shader.PropertyToID("_Metallic");  
    static int smoothnessId = Shader.PropertyToID("_Smoothness");  
    
    [SerializeField]  
    Mesh mesh = default;  
    [SerializeField]  
    Material material = default;

    private Matrix4x4[] matrices = new Matrix4x4[1023];
    private Vector4[] baseColors = new Vector4[1023];
    
    //添加金属度和光滑度属性调节参数  
    float[] metallic = new float[1023];  
    float[] smoothness = new float[1023];  

    private MaterialPropertyBlock block;

    private void Awake() {
        for (int i = 0; i < matrices.Length; i++) {
            
            matrices[i] = Matrix4x4.TRS(Random.insideUnitSphere*10f, 
                Quaternion.Euler(Random.value * 360f, Random.value * 360f, Random.value * 360f),  
                Vector3.one * Random.Range(0.5f, 1.5f));  
            
            baseColors[i] = new Vector4(Random.value,Random.value,Random.value,Random.Range(0.5f,1f));
            
            //金属度和光滑度按条件随机  
            metallic[i] = Random.value < 0.25f ? 1f : 0f;  
            smoothness[i] = Random.Range(0.05f, 0.95f);  
        
        }
    }

    [SerializeField]  
    LightProbeProxyVolume lightProbeVolume = null;  
    private void Update() {
        if (block == null) {
            block = new MaterialPropertyBlock();
            block.SetVectorArray(baseColorId, baseColors);
            block.SetFloatArray(metallicId, metallic);  
            block.SetFloatArray(smoothnessId, smoothness);


            if (!lightProbeVolume) {
                var positions = new Vector3[1023];  
                for (int i = 0; i < matrices.Length; i++)  
                {  
                    positions[i] = matrices[i].GetColumn(3);  
                }  
                var lightProbes = new SphericalHarmonicsL2[1023];
                var occlusionProbes = new Vector4[1023];  
                //该方法需要传递三个参数，对象实例的位置和光照探针数据，第三个参数用于遮挡，我们设置为空。
                LightProbes.CalculateInterpolatedLightAndOcclusionProbes(positions, lightProbes, occlusionProbes);
                //block.CopySHCoefficientArraysFrom方法将光照探针数据复制到材质属性块中
                block.CopySHCoefficientArraysFrom(lightProbes);  
                block.CopyProbeOcclusionArrayFrom(occlusionProbes);   
            }
            
            
        }
        
        //第1个参数代表是否投射阴影，我们启用它。第2个布尔参数代表是否接收阴影，我们设为true。
        //第3个参数代表层级，我们使用默认的0。第4个参数代表提供一个渲染相机，我们设置null为所有相机渲染它们。
        //第5个参数代表光照探针插值类型，我们使用CustomProvided。
        Graphics.DrawMeshInstanced(mesh,0,material,matrices,1023,block,
                                    ShadowCastingMode.On, true, 0,null,
                                    lightProbeVolume ? LightProbeUsage.UseProxyVolume : LightProbeUsage.CustomProvided,
                                    lightProbeVolume);  
    }
}