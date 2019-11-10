// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/POM shader"
{
    Properties
    {
        _Ambient    ("Ambient", Color) = (0, 0, 0, 1)
        _MainTex    ("Albedo (RGB)", 2D) = "white" {}
        _NormalsTex ("Normals", 2D) = "white" {}
        _HeightTex  ("Height", 2D) = "white" {}
        _MaxDepth   ("Max depth", Range(0, 0.2)) = 0.02
        _StepLength ("Step length", Range(0, 0.2)) = 0.001
        _StepsNum   ("Number of steps", Int) = 32
        _Shininess  ("Shininess", Float) = 1
        _Occlusion  ("Occlusion limit", Float) = 0.002
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        Pass
        {
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
    
            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
    
            struct appdata
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                float4 tangent : TANGENT;
                float2 uv      : TEXCOORD0;
            };
    
            struct v2f
            {
                float3 worldPos : TEXCOORD2;
                float4 vertex   : SV_POSITION;
                float3 normal   : TEXCOORD1;
                float3 tangent  : TANGENT;
                float2 uv       : TEXCOORD0;
            };
    
            float3 _Ambient;
    
            sampler2D _MainTex;
            float4 _MainTex_ST;
    
            sampler2D _NormalsTex;
            float4 _NormalsTex_ST;
            
            sampler2D _HeightTex;
            float4 _HeightTex_ST;
    
            float _MaxDepth;
            float _StepLength;
            int _StepsNum;
            float _Shininess;
            float _Occlusion;
   
            v2f vert(appdata v)
            {
                v2f o;
                
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.vertex   = UnityObjectToClipPos(v.vertex);
                o.normal   = UnityObjectToWorldNormal(v.normal);
                o.tangent  = UnityObjectToWorldDir(v.tangent.xyz);
                o.uv       = TRANSFORM_TEX(v.uv, _MainTex);
                
                return o;
            }
    
            float depthAt(float2 uv) {
                return _MaxDepth * (1 - tex2Dlod(_HeightTex, float4(uv, 0, 0)));
            }
    
            void frag(v2f input, out fixed4 color: COLOR, out float zDepth: DEPTH)
            {   
                float3 normal    = normalize(input.normal);
                float3 tangent   = normalize(input.tangent - dot(input.tangent, normal) * normal);
                float3 bitangent = cross(tangent, normal);   
                float3x3 TBN     = float3x3(tangent, bitangent, normal);
                
                float3 viewDirectionTBN = mul(TBN, normalize(input.worldPos - _WorldSpaceCameraPos));
               
                float rayDepth = 0;
                float matDepth = 0;
                float previousRayDepth = 0;
                float previousMatDepth = 0;
                
                [unroll(64)]
                for (int i = 1; i <= _StepsNum; ++i) {
                    float3 offset = viewDirectionTBN * (i * _StepLength);
                    
                    rayDepth = -offset.z;
                    matDepth = depthAt(input.uv + offset.xy);
                    
                    if (matDepth <= rayDepth) {
                        break;
                    }
                    
                    previousRayDepth = rayDepth;
                    previousMatDepth = matDepth;
                }
                
                float rayDepthDiff = rayDepth - previousRayDepth;
                float matDepthDiff = matDepth - previousMatDepth;
                
                float t = (previousRayDepth - previousMatDepth) / (matDepthDiff - rayDepthDiff);
                float depth = lerp(previousMatDepth, matDepth, t);
                
                viewDirectionTBN *= depth / (-viewDirectionTBN.z);
                float2 uv = input.uv + viewDirectionTBN.xy;
                
                float4 clip = UnityWorldToClipPos(input.worldPos + mul(viewDirectionTBN, TBN));
                zDepth = clip.z / clip.w;
                
                // zDepth = input.vertex.z;
                // float2 uv = input.uv;
                
                float3 lightDirectionTBN = mul(TBN, normalize(_WorldSpaceLightPos0.xyz));
                
                float shadowness = 0;
                [unroll(64)]
                for (int i = 1; i <= _StepsNum; ++i) {
                    float3 offset = lightDirectionTBN * (i * _StepLength);
                    
                    rayDepth = depth - offset.z;
                    matDepth = depthAt(uv + offset.xy);
                    
                    if (matDepth <= rayDepth) {
                        shadowness = max(shadowness, (rayDepth - matDepth) / _Occlusion);
                    }
                }
                
                float2 uvDx = ddx(uv);
                float2 uvDy = ddy(uv);
                
                fixed4 albedo      = tex2D(_MainTex, uv, uvDx, uvDy);
                fixed3 normSample  = normalize(UnpackNormal(tex2D(_NormalsTex, uv, uvDx, uvDy)));
                float3 tangentNorm = mul(normSample.xyz, TBN);
                
                half3 diffuse = max(0, dot(tangentNorm, _WorldSpaceLightPos0.xyz)) * _LightColor0;
                
                float3 viewDirection = normalize(_WorldSpaceCameraPos - input.worldPos);
                float cosAlpha = max(0.0, dot(reflect(-_WorldSpaceLightPos0.xyz, tangentNorm), viewDirection));
                half3 specular = pow(cosAlpha, _Shininess) * _LightColor0 / 2;
                
                // shadowness = 0;
                color = half4(albedo * ((1 - shadowness) * (diffuse + specular) + _Ambient), 1);
            }
            
            ENDCG
        }
    }
    
    Fallback "Diffuse"
}
