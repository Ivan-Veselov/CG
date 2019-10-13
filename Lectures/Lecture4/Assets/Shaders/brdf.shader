Shader "Custom/brdf"
{
    Properties
    {
        _EnvTex ("Environment", 2D) = "white" {}
    }
    
    SubShader
    {
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                fixed3 normal : NORMAL;
            };

            struct v2f
            {
                float4 clip : SV_POSITION;
                float4 pos : TEXCOORD1;
                fixed3 normal : NORMAL;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.clip = UnityObjectToClipPos(v.vertex);
                o.pos = mul(UNITY_MATRIX_M, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            static const float PI = 3.14159265f;

            static const float2 invPi = float2(0.5 / PI, 1 / PI);
            float2 UnitSphereVectorToUV(float3 direction)
            {
                float2 uv = float2(atan2(direction.z, direction.x), asin(direction.y));
                uv *= invPi;
                uv += 0.5;
                
                return uv;
            }
            
            uint Hash(uint s)
            {
                s ^= 2747636419u;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                return s;
            }
            
            float ToRandomFloat(uint randomInt)
            {
                return float(randomInt) / 4294967295.0; // 2^32-1
            }
            
            float3 RandomUnitSphereVector(in out uint seed)
            {
                uint hash1 = Hash(seed);
                uint hash2 = Hash(hash1);
                seed = hash2;
                
                float rand1 = 2 * ToRandomFloat(hash1) - 1;
                float rand2 = 2 * PI * ToRandomFloat(hash2);
                
                float y = rand1;
                float smallRadius = sqrt(1 - y * y);
                
                return float3(smallRadius * cos(rand2), y, smallRadius * sin(rand2));
            }
            
            static const float E = 2.71828182f;
            
            // arg should be at least 1
            float EulersGammaApproximation(float arg)
            {
                arg -= 1;
                return sqrt(2 * PI * arg) * pow(arg / E, arg);
            }
            
            static const float specularExp = 50;
            
            float AdHocDensityFunction(float3 fromDirection, float3 outDirection, fixed3 normal)
            {
                // return 0.5 / PI; // pure diffuse
                
                float3 reflectedIn = reflect(-fromDirection, normal);
                
                float densityIntegralUpperBound = 0.5 * pow(PI, 3 / 2) * EulersGammaApproximation((specularExp + 1) / 2) / EulersGammaApproximation(specularExp / 2 + 2);
                // float densityIntegralUpperBound = 0.021310;
                
                densityIntegralUpperBound *= 8;
                
                return pow(max(0, dot(reflectedIn, outDirection)), specularExp) / densityIntegralUpperBound;
            }
            
            static const float widthSquared = 0.008;
            
            float MicroDistribution(fixed3 normal, fixed3 microNormal) {
                float microCos = dot(normal, microNormal);
                float microSin = length(cross(normal, microNormal));
                float microTan = microSin / microCos;
                
                float microCos4 = microCos * microCos * microCos * microCos;
                float Z = widthSquared + microTan * microTan;
                
                return widthSquared / (PI * microCos4 * Z * Z);
            }
            
            float MonoShadowingMaskin(float3 direction, fixed3 normal)
            {
                float microCos = dot(normal, direction);
                float microSin = length(cross(normal, direction));
                float microTan = microSin / microCos;
            
                return 2 / (1 + sqrt(1 + widthSquared * microTan * microTan));
            }
            
            static const float eta = 10;
            
            float FresnelTerm(float3 fromDirection, fixed3 microNormal) {
                float c = dot(fromDirection, microNormal);
                float g = sqrt(eta * eta - 1 + c * c);
                
                float diff = g - c;
                float sum = g + c;
                
                float A = c * sum - 1;
                A *= A;
                
                float B = c * diff + 1;
                B *= B;
                
                return 0.5 * diff * diff / (sum * sum) * (1 + A / B);
            }
            
            float CookTorranceDensityFunction(float3 fromDirection, float3 outDirection, fixed3 normal)
            {
                fixed3 microNormal = normalize(fromDirection + outDirection);
                
                return MicroDistribution(normal, microNormal) *
                        MonoShadowingMaskin(fromDirection, normal) *
                        MonoShadowingMaskin(outDirection, normal) *
                        FresnelTerm(fromDirection, microNormal) /
                        (4 * dot(fromDirection, normal) * dot(outDirection, normal));
            }

            sampler2D _EnvTex;

            fixed4 frag (v2f i) : SV_Target
            {
                fixed3 normal = normalize(i.normal);
                float3 viewDirection = normalize(_WorldSpaceCameraPos - i.pos.xyz);
                
                fixed4 color = 0;
                const uint numOfSamples = 40000; // 512 for interactivity / 40000 for good picture
                // uint seed = asuint(i.pos.x) ^ asuint(i.pos.y) ^ asuint(i.pos.z);
                uint seed = 0;
                for (uint sampleNumber = 0; sampleNumber < numOfSamples; ++sampleNumber) {
                    float3 fromDirection = RandomUnitSphereVector(seed);
                    if (dot(fromDirection, normal) < 0) {
                        fromDirection = -fromDirection;
                    }
                    
                    float2 uv = UnitSphereVectorToUV(fromDirection);
                    fixed4 lightColor = tex2Dlod(_EnvTex, float4(uv, 0, 0));
                    // float density = AdHocDensityFunction(fromDirection, viewDirection, normal);
                    float density = CookTorranceDensityFunction(fromDirection, viewDirection, normal);
                    color += density * lightColor;
                }
                
                color /= numOfSamples;
                color *= 2 * PI; // half sphere surface area
                
                return color;
            }
            ENDCG
        }
    }
}
