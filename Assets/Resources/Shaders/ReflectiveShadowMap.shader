Shader "Hidden/Custom RP/RSM" {
	
	SubShader {
		Cull Off
		ZTest Always
		ZWrite On
		
		HLSLINCLUDE
		#include "./ShaderLibrary/Common.hlsl"
		#include "RsmPass.hlsl"
		ENDHLSL
		
		Pass {
			
			HLSLPROGRAM
				#pragma target 3.5
				#pragma vertex RSMVertex
				#pragma fragment RSMFragment
			ENDHLSL
		}
		
		Pass {
			
			HLSLPROGRAM
				#pragma target 3.5
				#pragma vertex DefaultPassVertex
				#pragma fragment BlurHorizontalFragment
			ENDHLSL
		}
		
		Pass {
			
			HLSLPROGRAM
				#pragma target 3.5
				#pragma vertex DefaultPassVertex
				#pragma fragment BlurVerticalFragment
				
			ENDHLSL
		}
		
		Pass {

			
			
			HLSLPROGRAM
				#pragma target 3.5
				#pragma vertex DefaultPassVertex
				#pragma fragment BlurFinalFragment
				#pragma shader_feature _SCREEN_SPACE_REFLECTION
	            #pragma shader_feature _REFLECTIVE_SHADOW_MAP
			ENDHLSL
		}
	}
}