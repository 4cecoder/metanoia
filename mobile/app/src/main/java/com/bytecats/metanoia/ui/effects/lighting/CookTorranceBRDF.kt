package com.bytecats.metanoia.ui.effects.lighting

import androidx.compose.ui.graphics.Color
import org.intellij.lang.annotations.Language

/**
 * Cook-Torrance BRDF implementation in AGSL for physically-based rendering
 * Implements GGX distribution, Schlick's Fresnel, and Smith geometry functions
 */
object CookTorranceBRDF {

    @Language("AGSL")
    const val PBR_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float time;
        
        // Material properties
        uniform float3 albedo;
        uniform float metallic;
        uniform float roughness;
        uniform float3 emissive;
        uniform float normalStrength;
        uniform float occlusion;
        uniform float opacity;
        
        // Light properties (array of lights)
        uniform int lightCount;
        uniform float3 lightPositions[8];
        uniform float3 lightColors[8];
        uniform float lightIntensities[8];
        uniform int lightTypes[8];  // 0 = point, 1 = directional, 2 = spot
        uniform float3 lightDirections[8];  // For directional/spot lights
        uniform float lightSpotAngles[8];   // For spot lights
        
        // View properties
        uniform float3 cameraPos;
        
        // Environment maps
        uniform bool useIBL;
        uniform sampler2D irradianceMap;
        uniform sampler2D radianceMap;
        uniform sampler2D brdfLUT;
        
        // Quality settings
        uniform float qualityLevel;  // 0.0 = low, 1.0 = high
        uniform int maxReflections;
        
        // Constants
        const float PI = 3.14159265359;
        const float EPSILON = 0.0001;
        const float MAX_REFLECTION_LOD = 6.0;
        
        // Normalize RGB values to [0,1]
        float3 normalizeColor(float3 color) {
            return clamp(color, float3(0.0), float3(1.0));
        }
        
        // Decode normal map from [0,1] to [-1,1]
        float3 decodeNormal(float3 normalMap) {
            return normalize(normalMap * 2.0 - 1.0);
        }
        
        // GGX/Trowbridge-Reitz distribution function
        float distributionGGX(float3 N, float3 H, float roughness) {
            float a = roughness * roughness;
            float a2 = a * a;
            float NdotH = max(dot(N, H), 0.0);
            float NdotH2 = NdotH * NdotH;
            
            float num = a2;
            float denom = (NdotH2 * (a2 - 1.0) + 1.0);
            denom = PI * denom * denom;
            
            return num / max(denom, EPSILON);
        }
        
        // Mobile-optimized GGX
        float optimizedGGX(float3 N, float3 H, float roughness) {
            float a = roughness * roughness;
            float a2 = a * a;
            float NdotH = max(dot(N, H), 0.0);
            float NdotH2 = NdotH * NdotH;
            
            float denomBase = NdotH2 * (a2 - 1.0) + 1.0;
            float denom = PI * denomBase * denomBase;
            
            return a2 / max(denom, 0.001);
        }
        
        // Schlick's approximation for Fresnel
        float3 fresnelSchlick(float cosTheta, float3 F0) {
            return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
        }
        
        // Fresnel with roughness modification for IBL
        float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
            return F0 + (max(float3(1.0 - roughness), F0) - F0) * 
                   pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
        }
        
        // Optimized Fresnel for mobile
        float3 optimizedFresnel(float cosTheta, float3 F0) {
            float pow5 = (1.0 - cosTheta) * (1.0 - cosTheta);
            pow5 = pow5 * pow5 * (1.0 - cosTheta);
            return F0 + (1.0 - F0) * pow5;
        }
        
        // Geometry function (Smith method)
        float geometrySchlickGGX(float NdotV, float roughness) {
            float r = (roughness + 1.0);
            float k = (r * r) / 8.0;
            
            float num = NdotV;
            float denom = NdotV * (1.0 - k) + k;
            
            return num / max(denom, EPSILON);
        }
        
        float geometrySmith(float3 N, float3 L, float3 V, float roughness) {
            float NdotL = max(dot(N, L), 0.0);
            float NdotV = max(dot(N, V), 0.0);
            float ggx1 = geometrySchlickGGX(NdotL, roughness);
            float ggx2 = geometrySchlickGGX(NdotV, roughness);
            
            return ggx1 * ggx2;
        }
        
        // Mobile-optimized geometry function
        float optimizedGeometry(float NdotV, float roughness) {
            float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
            return NdotV / max(NdotV * (1.0 - k) + k, EPSILON);
        }
        
        // Cook-Torrance BRDF calculation
        float3 cookTorranceBRDF(float3 N, float3 L, float3 V, float3 F0, float roughness) {
            float3 H = normalize(L + V);
            
            // Normal Distribution Function
            float NDF = distributionGGX(N, H, roughness);
            
            // Geometry function
            float G = geometrySmith(N, L, V, roughness);
            
            // Fresnel term
            float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);
            
            // Specular BRDF
            float3 numerator = NDF * G * F;
            float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0);
            float3 specular = numerator / max(denominator, EPSILON);
            
            return specular;
        }
        
        // Mobile-optimized BRDF
        float3 optimizedBRDF(float3 N, float3 L, float3 V, float3 F0, float roughness) {
            float3 H = normalize(L + V);
            
            float a = roughness * roughness;
            float a2 = a * a;
            float NdotH = max(dot(N, H), 0.0);
            float NdotH2 = NdotH * NdotH;
            
            float num = a2;
            float denomBase = NdotH2 * (a2 - 1.0) + 1.0;
            float denom = PI * denomBase * denomBase;
            float D = num / max(denom, 0.001);
            
            float cosTheta = max(dot(H, V), 0.0);
            float3 F = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
            
            float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
            float NdotL = max(dot(N, L), 0.0);
            float NdotV = max(dot(N, V), 0.0);
            float G = NdotL / max(NdotL * (1.0 - k) + k, 0.001) * 
                      NdotV / max(NdotV * (1.0 - k) + k, 0.001);
            
            float3 specular = (D * F * G) / max(4.0 * NdotL * NdotV + EPSILON, 0.001);
            
            return specular;
        }
        
        // Energy conservation
        void calculateEnergyConservation(float metallic, float3 F, 
                                         out float3 k_s, out float3 k_d) {
            k_s = F;
            k_d = (1.0 - k_s) * (1.0 - metallic);
        }
        
        // Spherical coordinates for environment sampling
        float2 sphericalCoords(float3 v) {
            const float2 invAtan = float2(0.1591, 0.3183);
            float2 uv = float2(atan(v.z, v.x), asin(v.y));
            uv *= invAtan;
            uv += 0.5;
            return uv;
        }
        
        // Diffuse irradiance from environment map
        float3 sampleDiffuseIrradiance(float3 N) {
            float2 uv = sphericalCoords(N);
            return texture(irradianceMap, uv).rgb;
        }
        
        // Specular radiance with roughness-based LOD
        float3 sampleSpecularRadiance(float3 R, float roughness) {
            float lod = roughness * MAX_REFLECTION_LOD;
            float2 uv = sphericalCoords(R);
            return textureLod(radianceMap, uv, lod).rgb;
        }
        
        // BRDF lookup table sampling
        float2 sampleBRDFLUT(float NdotV, float roughness) {
            return texture(brdfLUT, float2(NdotV, roughness)).rg;
        }
        
        // Image-based lighting calculation
        float3 calculateIBL(float3 N, float3 V, float3 albedo, float metallic, 
                           float roughness, float3 F0) {
            float3 R = reflect(-V, N);
            
            // Diffuse IBL
            float3 k_d = (1.0 - metallic) * albedo;
            float3 diffuse = k_d * sampleDiffuseIrradiance(N);
            
            // Specular IBL
            float3 F = fresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
            float3 prefilteredColor = sampleSpecularRadiance(R, roughness);
            float2 brdf = sampleBRDFLUT(max(dot(N, V), 0.0), roughness);
            float3 specular = prefilteredColor * (F * brdf.x + brdf.y);
            
            return diffuse + specular;
        }
        
        // Mobile-optimized IBL
        float3 optimizedIBL(float3 N, float3 V, float3 albedo, float metallic, 
                           float roughness, float3 F0) {
            float3 irradiance = textureLod(irradianceMap, sphericalCoords(N), 2.0).rgb;
            float3 R = reflect(-V, N);
            float3 radiance = textureLod(radianceMap, sphericalCoords(R), 
                                        roughness * 4.0 + 2.0).rgb;
            
            float3 F = fresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
            float3 k_d = (1.0 - metallic) * (1.0 - F);
            
            return k_d * irradiance + F * radiance;
        }
        
        // Distance attenuation for point lights
        float calculateAttenuation(float distance, float radius) {
            float attenuation = 1.0 / (distance * distance + 1.0);
            float fade = smoothstep(radius, radius * 0.8, distance);
            return attenuation * fade;
        }
        
        // Spot light calculation
        float calculateSpotLight(float3 L, float3 spotDir, float spotAngle) {
            float cosAngle = dot(L, -spotDir);
            float innerCutoff = cos(spotAngle * 0.5);
            float outerCutoff = cos(spotAngle * 0.4);
            float intensity = smoothstep(outerCutoff, innerCutoff, cosAngle);
            return intensity;
        }
        
        // Calculate single light contribution
        float3 calculateLight(int lightIndex, float3 worldPos, float3 normal, 
                            float3 viewDir, float3 albedo, float metallic, 
                            float roughness, float3 F0) {
            float3 lightPos = lightPositions[lightIndex];
            float3 lightColor = lightColors[lightIndex];
            float lightIntensity = lightIntensities[lightIndex];
            int lightType = lightTypes[lightIndex];
            
            float3 L;
            float attenuation = 1.0;
            
            if (lightType == 0) {  // Point light
                float3 lightVec = lightPos - worldPos;
                float distance = length(lightVec);
                L = normalize(lightVec);
                attenuation = calculateAttenuation(distance, 50.0);
            } else if (lightType == 1) {  // Directional light
                L = normalize(lightDirections[lightIndex]);
                attenuation = 1.0;
            } else if (lightType == 2) {  // Spot light
                float3 lightVec = lightPos - worldPos;
                float distance = length(lightVec);
                L = normalize(lightVec);
                attenuation = calculateAttenuation(distance, 50.0);
                attenuation *= calculateSpotLight(L, lightDirections[lightIndex], 
                                                 lightSpotAngles[lightIndex]);
            }
            
            float3 radiance = lightColor * lightIntensity * attenuation;
            
            // PBR lighting calculation
            float3 H = normalize(L + viewDir);
            float3 F = fresnelSchlick(max(dot(H, viewDir), 0.0), F0);
            
            float3 k_s, k_d;
            calculateEnergyConservation(metallic, F, k_s, k_d);
            
            // Lambertian diffuse
            float3 diffuse = k_d * albedo / PI;
            
            // Specular
            float3 specular = cookTorranceBRDF(normal, L, viewDir, F0, roughness);
            
            // Combine
            float NdotL = max(dot(normal, L), 0.0);
            float3 result = (diffuse + specular) * radiance * NdotL;
            
            return result;
        }
        
        // Main PBR calculation function
        float3 calculatePBR(float3 worldPos, float3 normal, float3 viewDir, 
                          float3 albedo, float metallic, float roughness, 
                          float3 emissive, float ao) {
            // Clamp material parameters
            roughness = clamp(roughness, 0.04, 1.0);
            metallic = clamp(metallic, 0.0, 1.0);
            
            // Calculate Fresnel at normal incidence
            float3 F0 = mix(float3(0.04), albedo, metallic);
            
            // Direct lighting from all lights
            float3 Lo = float3(0.0);
            int actualLightCount = min(lightCount, 8);
            
            for (int i = 0; i < actualLightCount; i++) {
                Lo += calculateLight(i, worldPos, normal, viewDir, albedo, 
                                    metallic, roughness, F0);
            }
            
            // Image-based lighting
            float3 ambient = float3(0.03);
            if (useIBL) {
                if (qualityLevel > 0.5) {
                    ambient = calculateIBL(normal, viewDir, albedo, metallic, 
                                          roughness, F0);
                } else {
                    ambient = optimizedIBL(normal, viewDir, albedo, metallic, 
                                         roughness, F0);
                }
            }
            
            // Apply ambient occlusion
            ambient *= ao;
            
            // Combine direct and indirect lighting
            float3 color = ambient + Lo;
            
            // Add emissive
            color += emissive;
            
            return color;
        }
        
        // Adaptive quality BRDF selection
        float3 adaptiveBRDF(float3 N, float3 L, float3 V, float3 F0, float roughness) {
            if (qualityLevel > 0.5) {
                return cookTorranceBRDF(N, L, V, F0, roughness);
            } else {
                return optimizedBRDF(N, L, V, F0, roughness);
            }
        }
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            
            // Skip processing for fully transparent pixels
            if (orig.a < 0.01) {
                return orig;
            }
            
            // Calculate surface normal from alpha gradient (simplified)
            float2 epsilon = float2(1.0 / resolution.x, 1.0 / resolution.y);
            half4 sampleX = composable.eval(fragCoord + float2(epsilon.x, 0.0));
            half4 sampleY = composable.eval(fragCoord + float2(0.0, epsilon.y));
            
            float3 normal = normalize(float3(
                (sampleX.a - orig.a) / epsilon.x,
                (sampleY.a - orig.a) / epsilon.y,
                1.0
            ));
            normal = normalize(normal * float3(normalStrength, normalStrength, 1.0));
            
            // Calculate world position (simplified, assuming UV maps to world)
            float3 worldPos = float3(uv.x * 100.0, uv.y * 100.0, 0.0);
            
            // Calculate view direction
            float3 viewDir = normalize(cameraPos - worldPos);
            
            // Normalize input colors
            float3 albedoNorm = normalizeColor(albedo);
            float3 emissiveNorm = normalizeColor(emissive);
            
            // Calculate PBR lighting
            float3 color = calculatePBR(worldPos, normal, viewDir, albedoNorm, 
                                       metallic, roughness, emissiveNorm, occlusion);
            
            // HDR tonemapping (simple reinhard)
            color = color / (color + float3(1.0));
            
            // Gamma correction
            color = pow(color, float3(1.0 / 2.2));
            
            return half4(color, orig.a * opacity);
        }
    """

    @Language("AGSL")
    const val MOBILE_OPTIMIZED_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        
        // Simplified material properties
        uniform float3 albedo;
        uniform float metallic;
        uniform float roughness;
        uniform float3 emissive;
        
        // Single light source for mobile
        uniform float3 lightPosition;
        uniform float3 lightColor;
        uniform float lightIntensity;
        uniform float3 lightDirection;
        
        uniform float3 cameraPos;
        
        const float PI = 3.14159265359;
        const float EPSILON = 0.0001;
        
        // Optimized GGX
        float optimizedGGX(float3 N, float3 H, float roughness) {
            float a = roughness * roughness;
            float a2 = a * a;
            float NdotH = max(dot(N, H), 0.0);
            float NdotH2 = NdotH * NdotH;
            
            float denomBase = NdotH2 * (a2 - 1.0) + 1.0;
            float denom = PI * denomBase * denomBase;
            
            return a2 / max(denom, 0.001);
        }
        
        // Optimized Fresnel
        float3 optimizedFresnel(float cosTheta, float3 F0) {
            float pow5 = (1.0 - cosTheta) * (1.0 - cosTheta);
            pow5 = pow5 * pow5 * (1.0 - cosTheta);
            return F0 + (1.0 - F0) * pow5;
        }
        
        // Optimized geometry
        float optimizedGeometry(float NdotL, float NdotV, float roughness) {
            float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
            return (NdotL / max(NdotL * (1.0 - k) + k, 0.001)) * 
                   (NdotV / max(NdotV * (1.0 - k) + k, 0.001));
        }
        
        // Complete optimized PBR
        float3 optimizedPBR(float3 albedo, float metallic, float roughness, 
                           float3 N, float3 L, float3 V) {
            float3 H = normalize(L + V);
            float3 F0 = mix(float3(0.04), albedo, metallic);
            
            // Optimized specular
            float D = optimizedGGX(N, H, roughness);
            float3 F = optimizedFresnel(max(dot(H, V), 0.0), F0);
            float G = optimizedGeometry(max(dot(N, L), 0.0), max(dot(N, V), 0.0), roughness);
            
            float3 specular = (D * F * G) / max(4.0 * max(dot(N, L), 0.0) * 
                                            max(dot(N, V), 0.0) + EPSILON, 0.001);
            
            // Energy conservation
            float3 k_s = F;
            float3 k_d = (1.0 - k_s) * (1.0 - metallic);
            float3 diffuse = k_d * albedo / PI;
            
            return diffuse + specular;
        }
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            
            if (orig.a < 0.01) return orig;
            
            // Calculate normal
            float2 epsilon = float2(1.0 / resolution.x, 1.0 / resolution.y);
            float alphaL = composable.eval(fragCoord + float2(-epsilon.x, 0.0)).a;
            float alphaR = composable.eval(fragCoord + float2(epsilon.x, 0.0)).a;
            float alphaD = composable.eval(fragCoord + float2(0.0, epsilon.y)).a;
            float alphaU = composable.eval(fragCoord + float2(0.0, -epsilon.y)).a;
            
            float3 normal = normalize(float3(
                (alphaL - alphaR),
                (alphaU - alphaD),
                1.0
            ));
            
            float3 worldPos = float3(uv.x * 100.0, uv.y * 100.0, 0.0);
            float3 lightDir = normalize(lightPosition - worldPos);
            float3 viewDir = normalize(cameraPos - worldPos);
            
            // Distance attenuation
            float distance = length(lightPosition - worldPos);
            float attenuation = 1.0 / (distance * distance * 0.01 + 1.0);
            float3 radiance = lightColor * lightIntensity * attenuation;
            
            // Calculate PBR
            float3 color = optimizedPBR(albedo, metallic, roughness, normal, 
                                       lightDir, viewDir);
            
            // Apply lighting
            color *= radiance * max(dot(normal, lightDir), 0.0);
            
            // Add ambient and emissive
            color += albedo * 0.03 + emissive;
            
            // Simple tonemapping
            color = color / (color + float3(1.0));
            color = pow(color, float3(1.0 / 2.2));
            
            return half4(color, orig.a);
        }
    """

    /**
     * BRDF shader code for integration with Kotlin
     */
    @Language("AGSL")
    const val BRDF_INTEGRATION_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float3 N;
        uniform float3 V;
        uniform float3 albedo;
        uniform float metallic;
        uniform float roughness;
        
        const float PI = 3.14159265359;
        const float EPSILON = 0.0001;
        const uint SAMPLE_COUNT = 1024u;
        
        float radicalInverse_VdC(uint bits) {
            bits = (bits << 16u) | (bits >> 16u);
            bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAau) >> 1u);
            bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
            bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
            bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
            return float(bits) * 2.3283064365386963e-10;
        }
        
        float2 hammersley(uint i, uint N) {
            return float2(float(i) / float(N), radicalInverse_VdC(i));
        }
        
        float3 importanceSampleGGX(float2 Xi, float3 N, float roughness) {
            float a = roughness * roughness;
            float phi = 2.0 * PI * Xi.x;
            float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
            float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
            
            float3 H;
            H.x = cos(phi) * sinTheta;
            H.y = sin(phi) * sinTheta;
            H.z = cosTheta;
            
            float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
            float3 tangent = normalize(cross(up, N));
            float3 bitangent = cross(N, tangent);
            
            return normalize(tangent * H.x + bitangent * H.y + N * H.z);
        }
        
        float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
            return F0 + (max(float3(1.0 - roughness), F0) - F0) * 
                   pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
        }
        
        half4 main(float2 fragCoord) {
            float3 F0 = mix(float3(0.04), albedo, metallic);
            float3 R = reflect(-V, N);
            
            float3 prefilteredColor = float3(0.0);
            float totalWeight = 0.0;
            
            for (uint i = 0u; i < SAMPLE_COUNT; i++) {
                float2 Xi = hammersley(i, SAMPLE_COUNT);
                float3 H = importanceSampleGGX(Xi, N, roughness);
                float3 L = normalize(2.0 * dot(V, H) * H - V);
                
                float NdotL = max(dot(N, L), 0.0);
                if (NdotL > 0.0) {
                    prefilteredColor += L;  // Would sample environment in real implementation
                    totalWeight += NdotL;
                }
            }
            
            prefilteredColor /= max(totalWeight, 0.001);
            
            return half4(prefilteredColor, 1.0);
        }
    """
}