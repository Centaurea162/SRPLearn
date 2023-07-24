Shader "CustomRP/DeferredLit"
{
    Properties  
    {  
    }  
    SubShader  
    {       
        Cull Off ZWrite On ZTest Always
        
        HLSLINCLUDE  
        #include "./ShaderLibrary/Common.hlsl"
        #include "./ShaderLibrary/UnityInput.hlsl"
        ENDHLSL  
   
        Pass  
        {  
            Tags{
                "LightMode" = "Deferred"    
            }

            
            HLSLPROGRAM
            #pragma vertex DeferredLitVertex
            #pragma fragment DeferredLitFragment
            
            #pragma shader_feature _ _SHADOWS_CLIP _SHADOWS_DITHER
            #pragma shader_feature _RECEIVE_SHADOWS
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
            #pragma multi_compile_instancing1
            #include "DeferredLitPass.hlsl"

            
            ENDHLSL
        }  
        

        

    }  
}