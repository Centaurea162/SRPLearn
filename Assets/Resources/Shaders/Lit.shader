Shader "CustomRP/Lit"  
{  
    Properties  
    {  
        _BaseColor("Color",Color) = (1.0, 1.0, 1.0, 1.0)
        _BaseMap("Texture", 2D) = "white" {}
        
        _Alpha("Alpha", Range(0, 1)) = 0.5
        //金属度和光滑度  
        _Metallic("Metallic", Range(0, 1)) = 0  
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        _Fresnel("Fresnel", Range(0, 1)) = 0.5

        
        //透明度测试的阈值  
        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        [Toggle(_CLIPPING)] _Clipping("Alpha Clipping", Float) = 0
        [Toggle(_PREMULTIPLY_ALPHA)] _PremulAlpha("Premultiply Alpha", Float) = 0
        //设置混合模式
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Dst Blend", Float) = 0
        //默认写入深度缓冲区  
        [Enum(Off, 0, On, 1)] _ZWrite("Z Write", Float) = 1
        
        //投影模式  
        [KeywordEnum(On, Clip, Dither, Off)] _Shadows ("Shadows", Float) = 0
        //是否接受投影的切换开关
        [Toggle(_RECEIVE_SHADOWS)] _ReceiveShadows ("Receive Shadows", Float) = 1
        
        //是否接受全局光照贴图
        [Toggle(_IBL)] _AllowIBL ("Allow Global IBL", Float) = 0
        
        //自发光  
        [NoScaleOffset] _EmissionMap("Emission", 2D) = "white" {}   //对于具有此特性的纹理属性，材质检视面板不会显示纹理平铺/偏移字段。
        [HDR] _EmissionColor("Emission", Color) = (0.0, 0.0, 0.0, 0.0)
        
        [HideInInspector] _MainTex("Texture for Lightmap", 2D) = "white" {}  
        [HideInInspector] _Color("Color for Lightmap", Color) = (0.5, 0.5, 0.5, 1.0)
        
         //遮罩纹理  
        [Toggle(_OCCLUSION_MAP)] _OcclusionMapToggle("Occlusion Map", Float) = 0
        _OcclusionMap("Occlusion Map", 2D) = "white" {}
        
        //法线贴图  
        [Toggle(_NORMAL_MAP)] _NormalMapToggle("Normal Map", Float) = 0
        [NoScaleOffset] _NormalMap("Normals", 2D) = "bump" {}  
        _NormalScale("Normal Scale", Range(0, 1)) = 1
        
        //金属度
        [Toggle(_METALLIC_MAP)] _MetallicMapToggle ("Metal Map", Float) = 0
        _MetallicMap ("Metallic Map", 2D) = "white" {}
        
        //粗造度
        [Toggle(_ROUGHNESS_MAP)] _ROUGHNESSMapToggle ("Roughness Map", Float) = 0
        _RoughnessMap ("Roughness Map", 2D) = "white" {}
        
        
    }  
    SubShader  
    {       
        HLSLINCLUDE  
        #include "./ShaderLibrary/Common.hlsl"  
        #include "LitInput.hlsl"  
        ENDHLSL  
        
        Pass  
        {  
            Tags{
                "LightMode" = "CustomForwardLit"    
            }
            
            //定义混合模式  
            Blend[_SrcBlend][_DstBlend]  
            //是否写入深度  
            ZWrite[_ZWrite]
            
            HLSLPROGRAM
            #pragma target 3.5  
            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment
            // #pragma shader_feature _CLIPPING
            #pragma shader_feature _ _SHADOWS_CLIP _SHADOWS_DITHER
            #pragma shader_feature _RECEIVE_SHADOWS
            //是否透明通道预乘  
            #pragma shader_feature _PREMULTIPLY_ALPHA
            
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _OCCLUSION_MAP
            #pragma shader_feature _METALLIC_MAP
            #pragma shader_feature _ROUGHNESS_MAP
            #pragma shader_feature _IBL
            #pragma shader_feature _TILE_BASED_LIGHT_CULLING
            #pragma shader_feature _REFLECTIVE_SHADOW_MAP
            
            #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
            #pragma multi_compile _ _OTHER_PCF3 _OTHER_PCF5 _OTHER_PCF7
            #pragma multi_compile _ _PCSS_OFF _PCSS_ON  
            #pragma multi_compile _ _CASCADE_BLEND_SOFT _CASCADE_BLEND_DITHER
            #pragma multi_compile _ _SHADOW_MASK_ALWAYS _SHADOW_MASK_DISTANCE
            #pragma multi_compile _ LIGHTMAP_ON  
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            //是否使用逐对象光源  
            #pragma multi_compile _ _LIGHTS_PER_OBJECT
            #pragma multi_compile_instancing
            
            #include "LitPass.hlsl"

            
            ENDHLSL
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
        
        
        Pass   
        {  
            Tags   
            {  
                "LightMode" = "Meta"  
            }  

            Cull Off
		    ZTest Always
		    ZWrite Off  
           
            HLSLPROGRAM  
            #pragma target 3.5  
            #pragma vertex MetaPassVertex  
            #pragma fragment MetaPassFragment  
            #include "MetaPass.hlsl"  
            ENDHLSL  
        }
        
        Pass   
        {  
            Tags   
            {  
                "LightMode" = "DepthOnly"  
            }  
           
            Cull Off
            ZWrite On
           
            HLSLPROGRAM  
            #pragma target 3.5  
            #pragma vertex DepthPassVertex
            #pragma fragment DepthPassFragment
            #include "DepthPass.hlsl"  
            ENDHLSL  
        }
        
        

        
        
        
    } 
    FallBack "Diffuse"
    CustomEditor "CustomShaderGUI"  
}