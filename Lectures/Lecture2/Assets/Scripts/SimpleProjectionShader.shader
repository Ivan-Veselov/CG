Shader "Custom/Triplanar"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _XYTex ("XY Albedo (RGB)", 2D) = "white" {}
        _XZTex ("XZ Albedo (RGB)", 2D) = "white" {}
        _YZTex ("YZ Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
    }
    SubShader
    {
        Pass
        {
            // indicate that our pass is the "base" pass in forward
            // rendering pipeline. It gets ambient and main directional
            // light data set up; light direction in _WorldSpaceLightPos0
            // and color in _LightColor0
            Tags {"LightMode"="ForwardBase"}
        
            CGPROGRAM
            #pragma enable_d3d11_debug_symbols
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc" // for UnityObjectToWorldNormal
            #include "UnityLightingCommon.cginc" // for _LightColor0

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 wpos : WORLD_POSITION;
                fixed3 normal : NORMAL;
            };

            v2f vert (appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.wpos = v.vertex.xyz;
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }
            
            sampler2D _XYTex;
            sampler2D _XZTex;
            sampler2D _YZTex;

            fixed4 frag (v2f i) : SV_Target
            {
                i.normal = normalize(i.normal);
            
                half nl = max(0, dot(i.normal, _WorldSpaceLightPos0.xyz));
                half3 light = nl * _LightColor0;
                light += ShadeSH9(half4(i.normal,1));
                
                fixed4 xySample = tex2D(_XYTex, i.wpos.xy);
                fixed4 xzSample = tex2D(_XZTex, i.wpos.xz);
                fixed4 yzSample = tex2D(_YZTex, i.wpos.yz);
                
                fixed3 weights = i.normal * i.normal;
                
                fixed4 col = xySample * weights.z + xzSample * weights.y + yzSample * weights.x;
                col.rgb *= light;
                
                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
