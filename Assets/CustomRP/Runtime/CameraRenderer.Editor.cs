using UnityEngine;  
using UnityEngine.Rendering;
using UnityEngine.Profiling; 
using UnityEditor;


public partial class CameraRenderer {

        partial void DrawUnsupportedShaders ();
        // partial void DrawGizmos();
        partial void PrepareForSceneWindow();
        partial void PrepareBuffer ();
        partial void DrawGizmosBeforeFX();  
        partial void DrawGizmosAfterFX(); 
        
#if UNITY_EDITOR
        
        string SampleName { get; set; }  
        
        //SRP不支持的着色器标签类型  
        static ShaderTagId[] legacyShaderTagIds = {
                new ShaderTagId("Always"),
                new ShaderTagId("ForwardBase"),
                new ShaderTagId("PrepassBase"),
                new ShaderTagId("Vertex"),
                new ShaderTagId("VertexLMRGBM"),
                new ShaderTagId("VertexLM"),
        };

        //绘制成使用错误材质的粉红颜色  
        static Material errorMaterial;
        


        /// <summary>  
        /// 绘制SRP不支持的着色器类型  
        /// </summary>  
        partial void DrawUnsupportedShaders() {
                //不支持的ShaderTag类型我们使用错误材质专用Shader来渲染(粉色颜色) 
                if (errorMaterial == null) {
                        errorMaterial = new Material(Shader.Find("Hidden/InternalErrorShader"));
                }

                //数组第一个元素用来构造DrawingSettings对象的时候设置  
                var drawingSettings = new DrawingSettings(legacyShaderTagIds[0], new SortingSettings(camera))
                        {overrideMaterial = errorMaterial};
                for (int i = 1; i < legacyShaderTagIds.Length; i++) {
                        //遍历数组逐个设置着色器的PassName，从i=1开始  
                        drawingSettings.SetShaderPassName(i, legacyShaderTagIds[i]);
                }

                //使用默认设置即可，反正画出来的都是不支持的  
                var filteringSettings = FilteringSettings.defaultValue;
                //绘制不支持的ShaderTag类型的物体  
                context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings);
        }

        // //绘制DrawGizmos  
        // partial void DrawGizmos(){  
        //         if (Handles.ShouldRenderGizmos())  
        //         {  
        //                 context.DrawGizmos(camera, GizmoSubset.PreImageEffects);  
        //                 context.DrawGizmos(camera, GizmoSubset.PostImageEffects);  
        //         }  
        // }  
        
        /// <summary>  
        /// 在Game视图绘制的几何体也绘制到Scene视图中  
        /// </summary>  
        
        partial void DrawGizmosBeforeFX()  
        {   
                if (Handles.ShouldRenderGizmos())  
                {  
                        context.DrawGizmos(camera, GizmoSubset.PreImageEffects);  
                }  
        }   
   
        partial void DrawGizmosAfterFX()  
        {   
                if (Handles.ShouldRenderGizmos())  
                {  
                        context.DrawGizmos(camera, GizmoSubset.PostImageEffects);  
                }   
        }
        
        
        
        partial void PrepareForSceneWindow()  
        {  
                if (camera.cameraType == CameraType.SceneView)  
                {  
                        //如果切换到了Scene视图，调用此方法完成绘制  
                        ScriptableRenderContext.EmitWorldGeometryForSceneView(camera);  
                }  
        }
        
        partial void PrepareBuffer ()   
        {  
                //设置一下只有在编辑器模式下才分配内存  
                Profiler.BeginSample("Editor Only");  
                buffer.name = SampleName = camera.name;  
                Profiler.EndSample();  
        }
        
#else  
    const string SampleName = bufferName;  
#endif

}



