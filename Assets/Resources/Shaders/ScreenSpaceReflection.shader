Shader "Hidden/Custom RP/SSR" {
	
	SubShader {
		Cull Off
		ZTest Always
		ZWrite On
		
		HLSLINCLUDE
		#include "./ShaderLibrary/Common.hlsl"
		#include "ScreenSpaceReflectionPass.hlsl"
		ENDHLSL
		
		Pass {
			
			HLSLPROGRAM
				#pragma target 3.5
				#pragma vertex SSRVertex
				#pragma fragment SSRFragment
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
		

	}
}