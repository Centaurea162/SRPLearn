Shader "CustomRP/gbuffer"
{
    Properties
    {
        _BaseColor("Color",Color) = (1.0, 1.0, 1.0, 1.0)
        _MainTex ("Albedo Map", 2D) = "white" {}
        [Space(25)]

        _Metallic ("Metallic", Range(0, 1)) = 0.5
        _Roughness ("Roughness", Range(0, 1)) = 0.5
        [Toggle] _Use_Metal_Map ("Use Metal Map", Float) = 1
        _MetallicMap ("Metallic Map", 2D) = "white" {}
        [Toggle] _Use_Roughness_Map ("Use Roughness Map", Float) = 1
        _RoughnessMap ("Roughness Map", 2D) = "white" {}
        [Toggle] _Use_MetallicGloss_Map ("Use MetallicGloss Map", Float) = 0
        _MetallicGlossMap ("MetallicGloss Map", 2D) = "white" {}
        [Space(25)]
        
        [Space(25)]
        
        
        
        _EmissionMap ("Emission Map", 2D) = "black" {}
        [Space(25)]

        _OcclusionMap ("Occlusion Map", 2D) = "white" {}
        [Space(25)]

        [Toggle] _Use_Normal_Map ("Use Normal Map", Float) = 1
        [Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        
        [Toggle] _Receive_Screen_Space_Reflection ("Receive Screen Space Reflection", Float) = 0
    }
    SubShader
    {
        

        Pass
        {
            
            Tags { "LightMode"="gbuffer" }
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "GBufferPass.cginc"
            
            ENDCG
        }
        
        Pass
          
        {  
            Tags   
            {  
                "LightMode" = "ShadowCaster"  
            }  
            ColorMask 0  
       
            HLSLPROGRAM  
            #pragma target 3.5  
            #pragma shader_feature _CLIPPING  
            #pragma multi_compile_instancing  
            #pragma vertex ShadowCasterPassVertex  
            #pragma fragment ShadowCasterPassFragment
            #include "ShadowCasterPass.hlsl"  
            ENDHLSL  
        }
        
        
        Pass{
            Tags{
                "LightMode" = "rsmBuffer"    
            }
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "RsmBufferPass.cginc"
            
            ENDCG
            
        }
    }
    
}