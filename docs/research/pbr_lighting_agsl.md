# Physically-Based Rendering and Advanced Lighting Algorithms for Mobile AGSL Shaders

**Research Date**: August 5, 2026
**Research Focus**: Mobile PBR implementation, AGSL shader optimization, real-time rendering techniques

---

## Executive Summary

This document provides comprehensive research on implementing physically-based rendering (PBR) and advanced lighting algorithms specifically optimized for mobile AGSL (Android Graphics Shading Language) shaders. The research covers fundamental PBR concepts, mathematical formulations, practical shader code implementations, and performance optimization strategies for mobile GPU constraints.

## Table of Contents

1. [Physically-Based Rendering Fundamentals](#1-physically-based-rendering-fundamentals)
2. [Cook-Torrance BRDF Implementation](#2-cook-torrance-brdf-implementation)
3. [GGX Distribution Function and Schlick's Approximation](#3-ggx-distribution-function-and-schlicks-approximation)
4. [Energy Conservation in Lighting Models](#4-energy-conservation-in-lighting-models)
5. [Material Properties: Albedo, Roughness, Metallic, Normal Maps](#5-material-properties-albedo-roughness-metallic-normal-maps)
6. [Mobile-Optimized PBR Techniques](#6-mobile-optimized-pbr-techniques)
7. [Image-Based Lighting (IBL) Implementation](#7-image-based-lighting-ibl-implementation)
8. [Screen-Space Reflections and Ambient Occlusion](#8-screen-space-reflections-and-ambient-occlusion)
9. [Ray Tracing Approximations for Real-Time Rendering](#9-ray-tracing-approximations-for-real-time-rendering)
10. [AGSL-Specific Lighting Optimizations](#10-agsl-specific-lighting-optimizations)
11. [Multiple Light Source Handling](#11-multiple-light-source-handling)
12. [Shadow Mapping Techniques](#12-shadow-mapping-techniques)

---

## 1. Physically-Based Rendering Fundamentals

### 1.1 Core Principles

Physically-based rendering is a rendering approach that simulates the physical behavior of light interacting with materials based on real-world physics. The key principles include:

1. **Energy Conservation**: Light cannot be created or destroyed, only reflected, transmitted, or absorbed
2. **Microfacet Theory**: Surfaces are composed of microscopic facets that reflect light
3. **Fresnel Effect**: Reflectance varies based on viewing angle
4. **Reciprocity**: BRDF remains symmetric when light and view directions are swapped

### 1.2 BRDF Mathematical Foundation

The Bidirectional Reflectance Distribution Function (BRDF) is defined as:

```
f(l, v) = dL_o(v) / dE_i(l)
```

Where:
- `l` = incident light direction
- `v` = outgoing view direction  
- `dL_o(v)` = differential outgoing radiance
- `dE_i(l)` = differential incoming irradiance

### 1.3 Mobile PBR Considerations

**GPU Constraints on Mobile Devices:**
- Limited computational power vs desktop GPUs
- Restricted memory bandwidth
- Power consumption constraints
- Limited texture sampling rates
- Variable precision across mobile GPUs

**AGSL Specifics:**
AGSL is nearly identical to GLSL ES 1.0 but integrated into Skia's rendering pipeline. Key differences from traditional GLSL:

```agsl
// AGSL shader structure
uniform shader input;  // Input shader from Skia pipeline
uniform float2 resolution;
uniform float time;

vec4 main(vec2 coords) {
    vec4 currValue = input.eval(coords);
    // PBR calculations here
    return result;
}
```

---

## 2. Cook-Torrance BRDF Implementation

### 2.1 Mathematical Formulation

The Cook-Torrance BRDF is defined as:

```
f(l, v) = k_d * f_lambert + k_s * f_cooktorrance
```

Where:
```
f_cooktorrance = (D * F * G) / (4 * (n·l) * (n·v))
```

Components:
- **D**: Normal Distribution Function (NDF) - describes microfacet orientation
- **F**: Fresnel term - describes reflectance based on viewing angle
- **G**: Geometry function - describes microfacet shadowing and masking
- **k_d**: Diffuse contribution coefficient
- **k_s**: Specular contribution coefficient

### 2.2 AGSL Implementation

```agsl
// Cook-Torrance BRDF for AGSL
vec3 CookTorranceBRDF(vec3 N, vec3 L, vec3 V, vec3 F0, float roughness) {
    vec3 H = normalize(L + V);  // Halfway vector
    
    // Normal Distribution Function (GGX)
    float NDF = DistributionGGX(N, H, roughness);
    
    // Geometry function
    float G = GeometrySmith(N, L, V, roughness);
    
    // Fresnel term (Schlick approximation)
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    
    // Cook-Torrance specular BRDF
    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0);
    vec3 specular = numerator / max(denominator, 0.001);
    
    return specular;
}

// Energy conservation calculation
vec3 CalculatePBR(vec3 albedo, float metallic, float roughness, vec3 N, vec3 L, vec3 V) {
    vec3 H = normalize(L + V);
    
    // Fresnel at normal incidence
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    
    // Cook-Torrance BRDF
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    vec3 k_s = F;  // Specular equals Fresnel
    vec3 k_d = (1.0 - k_s) * (1.0 - metallic);  // Diffuse
    
    // Lambertian diffuse
    vec3 diffuse = k_d * albedo / PI;
    
    // Specular
    vec3 specular = CookTorranceBRDF(N, L, V, F0, roughness);
    
    return diffuse + specular;
}
```

### 2.3 Mobile Optimizations

**Precomputed Constants:**
```agsl
const float PI = 3.14159265359;
const float EPSILON = 0.0001;

// Mobile-optimized BRDF with reduced operations
vec3 OptimizedBRDF(vec3 N, vec3 L, vec3 V, vec3 F0, float roughness) {
    vec3 H = normalize(L + V);
    
    // Optimized GGX distribution
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    
    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    float D = num / (PI * denom * denom);
    
    // Optimized Fresnel
    float cosTheta = max(dot(H, V), 0.0);
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    
    // Simplified geometry for mobile
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float G = NdotL / (NdotL * (1.0 - k) + k) * NdotV / (NdotV * (1.0 - k) + k);
    
    // Combined specular calculation
    vec3 specular = (D * F * G) / (4.0 * NdotL * NdotV + EPSILON);
    
    return specular;
}
```

---

## 3. GGX Distribution Function and Schlick's Approximation

### 3.1 GGX Distribution Function

The GGX (Trowbridge-Reitz) distribution function provides more accurate tail behavior compared to Beckmann distribution:

```
D(h) = α² / (π * ((n·h)² * (α² - 1) + 1)²)
```

Where `α` is the roughness parameter and `h` is the halfway vector.

### 3.2 AGSL Implementation

```agsl
// GGX/Trowbridge-Reitz distribution
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    
    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
    
    return num / denom;
}

// Mobile-optimized GGX with reduced precision operations
float OptimizedGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    
    // Precompute denominator components
    float denomBase = NdotH2 * (a2 - 1.0) + 1.0;
    float denom = PI * denomBase * denomBase;
    
    return a2 / max(denom, 0.001);
}
```

### 3.3 Schlick's Fresnel Approximation

Schlick's approximation provides a computationally efficient way to calculate Fresnel reflectance:

```
F(θ) = F₀ + (1 - F₀) * (1 - cos θ)^5
```

**AGSL Implementation:**

```agsl
// Schlick's Fresnel approximation
vec3 FresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Fresnel with roughness modification for IBL
vec3 FresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
}

// Optimized Fresnel for mobile
vec3 OptimizedFresnel(float cosTheta, vec3 F0) {
    float pow5 = (1.0 - cosTheta) * (1.0 - cosTheta);
    pow5 = pow5 * pow5 * (1.0 - cosTheta);  // (1-cos)^5 optimized
    
    return F0 + (1.0 - F0) * pow5;
}

// Precomputed Fresnel for rough materials
vec3 FresnelRough(vec3 F0, float roughness) {
    return F0 + (vec3(1.0) - F0) * roughness;
}
```

### 3.4 Geometry Functions

**Smith Geometry Function for GGX:**

```agsl
float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;  // IBL: k = roughness² / 2
    
    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;
    
    return num / denom;
}

float GeometrySmith(vec3 N, vec3 L, vec3 V, float roughness) {
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    
    return ggx1 * ggx2;
}

// Mobile-optimized geometry function
float OptimizedGeometry(float NdotV, float roughness) {
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}
```

---

## 4. Energy Conservation in Lighting Models

### 4.1 Energy Conservation Principles

Energy conservation ensures that the total reflected light never exceeds the incident light. For PBR materials:

```
k_d + k_s ≤ 1.0
```

Where `k_d` is diffuse energy and `k_s` is specular energy.

### 4.2 Energy Conservation Implementation

```agsl
// Energy conservation calculation
void CalculateEnergyConservation(float metallic, vec3 F0, out vec3 k_s, out vec3 k_d) {
    // Specular contribution (Fresnel term)
    k_s = F0;  // Will be calculated per-light using FresnelSchlick
    
    // Diffuse contribution with energy conservation
    k_d = (1.0 - k_s) * (1.0 - metallic);
}

// Integrated energy conservation
vec3 CalculateConservedLighting(vec3 albedo, float metallic, float roughness,
                                  vec3 N, vec3 L, vec3 V) {
    vec3 H = normalize(L + V);
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    
    // Calculate Fresnel
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    
    // Energy conservation
    vec3 k_s = F;
    vec3 k_d = (1.0 - k_s) * (1.0 - metallic);
    
    // Diffuse term
    vec3 diffuse = k_d * albedo / PI;
    
    // Specular term
    vec3 specular = CookTorranceBRDF(N, L, V, F0, roughness);
    
    // Ensure energy conservation
    float NdotL = max(dot(N, L), 0.0);
    vec3 result = (diffuse + specular) * NdotL;
    
    return result;
}
```

### 4.3 Mobile Energy Conservation Optimizations

```agsl
// Simplified energy conservation for mobile
vec3 MobileEnergyConservation(vec3 albedo, float metallic, vec3 F) {
    // Precompute common factors
    vec3 k_s = F;
    vec3 k_d = (1.0 - k_s) * (1.0 - metallic);
    
    return k_d * albedo;  // Specular handled separately
}

// Conservative energy approximation
float ConservativeEnergy(float roughness, float NdotV) {
    // Ensure energy doesn't exceed 1.0
    return min(1.0, NdotV * (1.0 + roughness));
}
```

---

## 5. Material Properties: Albedo, Roughness, Metallic, Normal Maps

### 5.1 Material Texture Packing

Mobile optimization packs material properties into fewer textures:

```agsl
// Sample packed material textures
vec4 SampleMaterialTextures(sampler2D albedoMap, sampler2D metallicRoughnessMap,
                            sampler2D normalMap, vec2 uv) {
    vec4 albedo = texture(albedoMap, uv);
    
    // Metallic-Roughness-Occlusion packed as BGR
    vec4 metallicRoughnessOcclusion = texture(metallicRoughnessMap, uv);
    float metallic = metallicRoughnessOcclusion.b;
    float roughness = metallicRoughnessOcclusion.g;
    float occlusion = metallicRoughnessOcclusion.r;
    
    // Normal map decoding
    vec3 normal = DecodeNormal(texture(normalMap, uv).rgb);
    
    return vec4(albedo.rgb, metallic);
}

// Normal map decoding
vec3 DecodeNormal(vec3 normalMap) {
    // Convert from [0,1] to [-1,1]
    vec3 normal = normalMap * 2.0 - 1.0;
    
    // Normalize for non-normalized normal maps
    return normalize(normal);
}

// Mobile-optimized normal decoding
vec3 FastDecodeNormal(vec3 normalMap) {
    // Assumes normalized normal maps
    return normalMap * 2.0 - 1.0;
}
```

### 5.2 Material Parameter Ranges

```agsl
// Clamp and normalize material parameters
float NormalizeRoughness(float roughness) {
    return clamp(roughness, 0.04, 1.0);  // Prevent division by zero
}

float NormalizeMetallic(float metallic) {
    return clamp(metallic, 0.0, 1.0);
}

vec3 NormalizeAlbedo(vec3 albedo) {
    return clamp(albedo, vec3(0.0), vec3(1.0));
}

// Apply gamma correction for albedo
vec3 ApplyGammaCorrection(vec3 albedo) {
    return pow(albedo, vec3(2.2));
}

// Remove gamma correction (linearize)
vec3 RemoveGammaCorrection(vec3 albedo) {
    return pow(albedo, vec3(1.0/2.2));
}
```

### 5.3 Material Blending

```agsl
// Blend materials based on weight
vec3 BlendMaterials(vec3 albedo1, vec3 albedo2, float metallic1, float metallic2,
                    float roughness1, float roughness2, float weight) {
    vec3 albedo = mix(albedo1, albedo2, weight);
    float metallic = mix(metallic1, metallic2, weight);
    float roughness = mix(roughness1, roughness2, weight);
    
    return vec3(albedo.r, albedo.g, albedo.b);  // Simplified return
}

// Layered materials
struct MaterialLayer {
    vec3 albedo;
    float metallic;
    float roughness;
    float opacity;
};

MaterialLayer BlendLayers(MaterialLayer base, MaterialLayer top, float topOpacity) {
    MaterialLayer result;
    result.albedo = mix(base.albedo, top.albedo, topOpacity);
    result.metallic = mix(base.metallic, top.metallic, topOpacity);
    result.roughness = mix(base.roughness, top.roughness, topOpacity);
    result.opacity = mix(base.opacity, top.opacity, topOpacity);
    
    return result;
}
```

---

## 6. Mobile-Optimized PBR Techniques

### 6.1 Texture Optimization Strategies

**Half-Precision Textures:**
```agsl
// Use lowp mediump for mobile where appropriate
lowp vec3 SampleAlbedo(sampler2D albedoMap, vec2 uv) {
    return texture(albedoMap, uv).rgb;
}

mediump vec3 SampleNormal(sampler2D normalMap, vec2 uv) {
    return texture(normalMap, uv).rgb;
}
```

**Mipmapping and LOD:**
```agsl
// Manual LOD control for performance
vec3 SampleWithLOD(sampler2D tex, vec2 uv, float lod) {
    return textureLod(tex, uv, lod).rgb;
}

// Distance-based LOD
float CalculateLOD(float distance) {
    return log2(distance * 0.1);
}
```

### 6.2 Computation Optimization

**Branch Elimination:**
```agsl
// Avoid dynamic branching
vec3 NoBranchLighting(vec3 color1, vec3 color2, bool condition, float factor) {
    // Use mix() instead of if-else
    vec3 selectedColor = mix(color1, color2, float(condition));
    return selectedColor * factor;
}

// Precomputed lighting lookup
vec3 PrecomputedLighting(float NdotL, float roughness, sampler2D lut) {
    vec2 uv = vec2(NdotL, roughness);
    return texture(lut, uv).rgb;
}
```

**Shared Calculations:**
```agsl
// Calculate shared terms once
struct PBRSharedTerms {
    vec3 N;
    vec3 L;
    vec3 V;
    vec3 H;
    float NdotL;
    float NdotV;
    float NdotH;
    float LdotH;
    float VdotH;
};

PBRSharedTerms CalculateSharedTerms(vec3 normal, vec3 lightDir, vec3 viewDir) {
    PBRSharedTerms terms;
    terms.N = normal;
    terms.L = lightDir;
    terms.V = viewDir;
    terms.H = normalize(lightDir + viewDir);
    
    terms.NdotL = max(dot(normal, lightDir), 0.0);
    terms.NdotV = max(dot(normal, viewDir), 0.0);
    terms.NdotH = max(dot(normal, terms.H), 0.0);
    terms.LdotH = max(dot(lightDir, terms.H), 0.0);
    terms.VdotH = max(dot(viewDir, terms.H), 0.0);
    
    return terms;
}
```

### 6.3 Memory Bandwidth Optimization

**Texture Coordinate Compression:**
```agsl
// Compressed UV interpolation
vec2 CompressUV(vec2 uv, vec2 uvMin, vec2 uvRange) {
    return (uv - uvMin) / uvRange;
}

// Texture atlas sampling with compression
vec3 SampleAtlas(sampler2D atlas, vec2 uv, vec2 atlasOffset, vec2 atlasScale) {
    vec2 atlasUV = uv * atlasScale + atlasOffset;
    return texture(atlas, atlasUV).rgb;
}
```

**Vertex Shader Optimizations:**
```agsl
// Precompute TBN matrix in vertex shader
out mat3 TBN;

void CalculateTBN(vec3 normal, vec3 tangent, vec3 bitangent) {
    TBN = mat3(tangent, bitangent, normal);
}

// Pass to fragment shader
in mat3 TBN;

// Use in fragment shader
vec3 CalculateWorldNormal(vec3 tangentNormal) {
    return normalize(TBN * tangentNormal);
}
```

### 6.4 Adaptive Quality

**LOD-Based Quality Scaling:**
```agsl
// Adaptive quality based on performance
uniform float qualityLevel;  // 0.0 = low, 1.0 = high

float AdaptiveRoughness(float roughness) {
    // Reduce roughness precision at low quality
    return mix(floor(roughness * 4.0) / 4.0, roughness, qualityLevel);
}

vec3 AdaptiveLighting(vec3 N, vec3 L, vec3 V, vec3 albedo, float roughness, float metallic) {
    if (qualityLevel < 0.5) {
        // Simplified PBR
        return SimplifiedPBR(N, L, V, albedo, roughness, metallic);
    } else {
        // Full PBR
        return FullPBR(N, L, V, albedo, roughness, metallic);
    }
}
```

---

## 7. Image-Based Lighting (IBL) Implementation

### 7.1 IBL Fundamentals

Image-based lighting uses environment maps to provide realistic indirect lighting. The two main components are:

1. **Diffuse Irradiance**: Ambient lighting from environment
2. **Specular Radiance**: Reflection of environment based on roughness

### 7.2 Diffuse Irradiance Implementation

```agsl
// Sample diffuse irradiance map
vec3 SampleDiffuseIrradiance(sampler2D irradianceMap, vec3 N) {
    // Convert normal to spherical coordinates
    vec2 uv = SphericalCoords(N);
    return texture(irradianceMap, uv).rgb;
}

// Spherical coordinate conversion
vec2 SphericalCoords(vec3 v) {
    const vec2 invAtan = vec2(0.1591, 0.3183);
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    uv *= invAtan;
    uv += 0.5;
    return uv;
}

// Mobile-optimized diffuse IBL
vec3 FastDiffuseIBL(vec3 N, sampler2D irradianceMap, vec3 albedo, float metallic) {
    vec3 irradiance = SampleDiffuseIrradiance(irradianceMap, N);
    vec3 k_d = (1.0 - metallic) * albedo;
    
    return k_d * irradiance;
}
```

### 7.3 Specular Radiance Implementation

```agsl
// Sample specular radiance map with roughness-based LOD
vec3 SampleSpecularRadiance(sampler2D radianceMap, vec3 R, float roughness) {
    // Calculate roughness-based LOD
    float lod = roughness * MAX_REFLECTION_LOD;
    vec2 uv = SphericalCoords(R);
    
    return textureLod(radianceMap, uv, lod).rgb;
}

// Compute reflection vector
vec3 ReflectVector(vec3 V, vec3 N) {
    return reflect(-V, N);
}

// Full specular IBL calculation
vec3 SpecularIBL(vec3 N, vec3 V, vec3 R, vec3 F0, float roughness,
                 sampler2D radianceMap, sampler2D brdfLUT) {
    vec3 F = FresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
    vec3 prefilteredColor = SampleSpecularRadiance(radianceMap, R, roughness);
    vec2 brdf = texture(brdfLUT, vec2(max(dot(N, V), 0.0), roughness)).rg;
    vec3 specular = prefilteredColor * (F * brdf.x + brdf.y);
    
    return specular;
}
```

### 7.4 BRDF Integration LUT

```agsl
// Sample BRDF lookup table
vec2 SampleBRDFLUT(sampler2D brdfLUT, float NdotV, float roughness) {
    return texture(brdfLUT, vec2(NdotV, roughness)).rg;
}

// Integrated IBL calculation
vec3 CalculateIBL(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness,
                  sampler2D irradianceMap, sampler2D radianceMap, sampler2D brdfLUT) {
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 R = ReflectVector(V, N);
    
    // Diffuse IBL
    vec3 k_d = (1.0 - metallic) * albedo;
    vec3 diffuse = k_d * SampleDiffuseIrradiance(irradianceMap, N);
    
    // Specular IBL
    vec3 F = FresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
    vec3 prefilteredColor = SampleSpecularRadiance(radianceMap, R, roughness);
    vec2 brdf = SampleBRDFLUT(brdfLUT, max(dot(N, V), 0.0), roughness);
    vec3 specular = prefilteredColor * (F * brdf.x + brdf.y);
    
    return diffuse + specular;
}
```

### 7.5 Mobile IBL Optimizations

```agsl
// Reduced resolution IBL
vec3 LowResIBL(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness,
                sampler2D irradianceMap, sampler2D radianceMap) {
    // Use lower resolution maps
    vec3 irradiance = textureLod(irradianceMap, SphericalCoords(N), 2.0).rgb;
    vec3 R = ReflectVector(V, N);
    vec3 radiance = textureLod(radianceMap, SphericalCoords(R), roughness * 4.0 + 2.0).rgb;
    
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 F = FresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
    vec3 k_d = (1.0 - metallic) * (1.0 - F);
    
    return k_d * irradiance + F * radiance;
}

// Prefiltered environment map approximation
vec3 ApproximateIBL(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness,
                     sampler2D envMap) {
    vec3 R = ReflectVector(V, N);
    vec3 envColor = textureLod(envMap, SphericalCoords(R), roughness * 6.0).rgb;
    
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 F = FresnelSchlick(max(dot(N, V), 0.0), F0);
    
    return mix(envColor, envColor * F, metallic * 0.5);
}
```

---

## 8. Screen-Space Reflections and Ambient Occlusion

### 8.1 Screen-Space Reflections (SSR)

SSR provides real-time reflections using screen-space information.

```agsl
// Screen-space ray marching
vec3 ScreenSpaceReflection(sampler2D depthBuffer, sampler2D colorBuffer,
                           vec2 screenUV, vec3 viewPos, vec3 viewNormal,
                           float roughness) {
    vec3 reflectDir = reflect(normalize(viewPos), viewNormal);
    vec3 rayPos = viewPos;
    
    float stepSize = 0.05;
    float maxSteps = 32.0;
    
    for (float i = 0.0; i < maxSteps; i++) {
        rayPos += reflectDir * stepSize;
        
        // Convert to screen space
        vec2 screenPos = ProjectToScreen(rayPos);
        
        if (screenPos.x < 0.0 || screenPos.x > 1.0 ||
            screenPos.y < 0.0 || screenPos.y > 1.0) {
            break;  // Out of bounds
        }
        
        // Check depth intersection
        float depth = texture(depthBuffer, screenPos).r;
        if (abs(depth - rayPos.z) < 0.001) {
            return texture(colorBuffer, screenPos).rgb;
        }
    }
    
    return vec3(0.0);  // No reflection found
}

// Mobile-optimized SSR
vec3 MobileSSR(sampler2D colorBuffer, vec2 screenUV, vec3 viewPos, vec3 viewNormal,
               float roughness) {
    vec3 reflectDir = reflect(normalize(viewPos), viewNormal);
    vec3 rayPos = viewPos;
    
    // Reduced steps for mobile
    float stepSize = 0.1;
    float maxSteps = 16.0;
    
    vec3 reflectionColor = vec3(0.0);
    float reflectionWeight = 0.0;
    
    for (float i = 0.0; i < maxSteps; i++) {
        rayPos += reflectDir * stepSize;
        vec2 screenPos = ProjectToScreen(rayPos);
        
        if (screenPos.x >= 0.0 && screenPos.x <= 1.0 &&
            screenPos.y >= 0.0 && screenPos.y <= 1.0) {
            reflectionColor = texture(colorBuffer, screenPos).rgb;
            reflectionWeight = 1.0 - (i / maxSteps);
            break;
        }
    }
    
    // Fade based on roughness
    reflectionWeight *= (1.0 - roughness);
    
    return reflectionColor * reflectionWeight;
}
```

### 8.2 Screen-Space Ambient Occlusion (SSAO)

SSAO approximates ambient occlusion using screen-space depth information.

```agsl
// SSAO sample generation
vec3 SSAOSampleOffsets[16] = vec3[](
    vec3(1, 0, 0), vec3(-1, 0, 0),
    vec3(0, 1, 0), vec3(0, -1, 0),
    vec3(1, 1, 0), vec3(-1, -1, 0),
    vec3(1, -1, 0), vec3(-1, 1, 0),
    vec3(1, 0, 1), vec3(-1, 0, 1),
    vec3(0, 1, 1), vec3(0, -1, 1),
    vec3(1, 1, 1), vec3(-1, -1, 1),
    vec3(1, -1, 1), vec3(-1, 1, 1)
);

// Calculate SSAO
float CalculateSSAO(sampler2D depthBuffer, sampler2D normalBuffer,
                    vec2 screenUV, vec3 viewPos, vec3 viewNormal) {
    float occlusion = 0.0;
    float radius = 0.5;
    
    for (int i = 0; i < 16; i++) {
        vec3 samplePos = viewPos + SSAOSampleOffsets[i] * radius;
        vec2 sampleUV = ProjectToScreen(samplePos);
        
        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
            sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
            
            float sampleDepth = texture(depthBuffer, sampleUV).r;
            vec3 sampleNormal = texture(normalBuffer, sampleUV).rgb;
            
            float rangeCheck = smoothstep(0.0, 1.0, radius / abs(viewPos.z - sampleDepth));
            float normalCheck = max(dot(viewNormal, sampleNormal), 0.0);
            
            occlusion += (sampleDepth >= samplePos.z + 0.025 ? 1.0 : 0.0) * rangeCheck * normalCheck;
        }
    }
    
    return 1.0 - (occlusion / 16.0);
}

// Mobile-optimized SSAO with fewer samples
float MobileSSAO(sampler2D depthBuffer, vec2 screenUV, vec3 viewPos, float depth) {
    float occlusion = 0.0;
    float radius = 0.3;
    
    // Reduced sample count for mobile
    vec2 offsets[4] = vec2[](
        vec2(1, 1), vec2(-1, -1),
        vec2(1, -1), vec2(-1, 1)
    );
    
    for (int i = 0; i < 4; i++) {
        vec2 sampleUV = screenUV + offsets[i] * radius * 0.01;
        float sampleDepth = texture(depthBuffer, sampleUV).r;
        
        occlusion += step(sampleDepth - depth, 0.025);
    }
    
    return 1.0 - (occlusion / 4.0);
}
```

### 8.3 Combined Screen-Space Effects

```agsl
// Combined SSAO and SSR
struct ScreenSpaceEffects {
    vec3 reflection;
    float ao;
};

ScreenSpaceEffects CalculateScreenSpaceEffects(sampler2D depthBuffer, sampler2D colorBuffer,
                                                vec2 screenUV, vec3 viewPos, vec3 viewNormal,
                                                float roughness) {
    ScreenSpaceEffects effects;
    
    // Screen-space reflection
    effects.reflection = MobileSSR(colorBuffer, screenUV, viewPos, viewNormal, roughness);
    
    // Screen-space ambient occlusion
    effects.ao = MobileSSAO(depthBuffer, screenUV, viewPos, viewPos.z);
    
    return effects;
}

// Apply screen-space effects to final lighting
vec3 ApplyScreenSpaceEffects(vec3 lighting, ScreenSpaceEffects effects, vec3 albedo, float metallic) {
    vec3 result = lighting;
    
    // Apply ambient occlusion
    result *= effects.ao;
    
    // Blend reflections based on metallic
    result = mix(result, effects.reflection, metallic * 0.5);
    
    return result;
}
```

---

## 9. Ray Tracing Approximations for Real-Time Rendering

### 9.1 Ray Marching

Ray marching is a technique for approximating ray-surface intersections.

```agsl
// Sphere distance function
float SphereSDF(vec3 p, float radius) {
    return length(p) - radius;
}

// Ray marching implementation
float RayMarch(vec3 rayOrigin, vec3 rayDir, float maxDist, float maxSteps) {
    float t = 0.0;
    
    for (int i = 0; i < int(maxSteps); i++) {
        vec3 p = rayOrigin + rayDir * t;
        float d = SphereSDF(p, 1.0);
        
        if (d < 0.001) {
            return t;  // Hit
        }
        
        t += d;
        
        if (t > maxDist) {
            break;  // Miss
        }
    }
    
    return -1.0;  // No hit
}

// Mobile-optimized ray marching
float MobileRayMarch(vec3 rayOrigin, vec3 rayDir, float maxDist) {
    float t = 0.0;
    float maxSteps = 16.0;  // Reduced steps for mobile
    
    for (float i = 0.0; i < maxSteps; i++) {
        vec3 p = rayOrigin + rayDir * t;
        float d = SphereSDF(p, 1.0);
        
        if (d < 0.01) {
            return t;  // Relaxed hit threshold
        }
        
        t += d * 0.8;  // Smaller step size for stability
        
        if (t > maxDist) {
            break;
        }
    }
    
    return -1.0;
}
```

### 9.2 Cone Tracing

Cone tracing approximates ray tracing using cones instead of rays.

```agsl
// Cone tracing for soft shadows
float ConeTraceShadow(vec3 rayOrigin, vec3 rayDir, float coneAngle, float maxDist) {
    float shadow = 1.0;
    float t = 0.01;
    float coneWidth = tan(coneAngle);
    
    while (t < maxDist && shadow > 0.01) {
        float radius = t * coneWidth;
        vec3 p = rayOrigin + rayDir * t;
        float d = SphereSDF(p, 1.0);
        
        if (d < radius) {
            shadow -= (radius - d) / radius;
        }
        
        t += max(d, radius * 0.5);
    }
    
    return max(shadow, 0.0);
}

// Mobile-optimized cone tracing
float MobileConeTrace(vec3 rayOrigin, vec3 rayDir, float maxDist) {
    float shadow = 1.0;
    float t = 0.01;
    float coneAngle = 0.1;  // Fixed angle for mobile
    float coneWidth = tan(coneAngle);
    
    float maxSteps = 8.0;  // Very reduced steps
    
    for (float i = 0.0; i < maxSteps; i++) {
        float radius = t * coneWidth;
        vec3 p = rayOrigin + rayDir * t;
        float d = SphereSDF(p, 1.0);
        
        if (d < radius) {
            shadow -= 0.5;  // Fixed reduction
        }
        
        t += max(d, radius);
    }
    
    return max(shadow, 0.0);
}
```

### 9.3 Ambient Occlusion Approximations

```agsl
// Ray-traced ambient occlusion
float RayTracedAO(vec3 pos, vec3 normal, float radius, int samples) {
    float occlusion = 0.0;
    
    for (int i = 0; i < samples; i++) {
        vec3 sampleDir = normalize(normal + RandomInUnitSphere());
        float hitDist = RayMarch(pos + normal * 0.01, sampleDir, radius, 16.0);
        
        if (hitDist > 0.0) {
            occlusion += 1.0 - smoothstep(0.0, radius, hitDist);
        }
    }
    
    return 1.0 - (occlusion / float(samples));
}

// Precomputed AO lookup
float PrecomputedAO(float depth, vec3 normal, sampler2D aoLUT) {
    vec2 uv = vec2(depth, dot(normal, vec3(0, 1, 0)));
    return texture(aoLUT, uv).r;
}
```

### 9.4 Reflection Approximations

```agsl
// Approximate reflections using environment map
vec3 ApproximateReflection(vec3 viewDir, vec3 normal, float roughness,
                            sampler2D envMap) {
    vec3 reflectDir = reflect(-viewDir, normal);
    float lod = roughness * 6.0;
    
    vec2 uv = SphericalCoords(reflectDir);
    return textureLod(envMap, uv, lod).rgb;
}

// Parallax-corrected reflections
vec3 ParallaxCorrectedReflection(vec3 viewDir, vec3 normal, vec3 worldPos,
                                   vec3 boundsMin, vec3 boundsMax,
                                   sampler2D envMap) {
    vec3 reflectDir = reflect(-viewDir, normal);
    vec3 firstBounce = worldPos + reflectDir * 10.0;
    
    // Parallax correction
    vec3 parallaxDir = firstBounce - boundsMin;
    vec3 maxDir = boundsMax - boundsMin;
    vec3 ratio = parallaxDir / maxDir;
    
    vec3 correctedDir = normalize(reflectDir * ratio);
    
    vec2 uv = SphericalCoords(correctedDir);
    return texture(envMap, uv).rgb;
}
```

---

## 10. AGSL-Specific Lighting Optimizations

### 10.1 AGSL Performance Characteristics

**Key AGSL considerations for mobile:**
- Integrated with Skia rendering pipeline
- Automatic shader compilation and caching
- Runtime uniform updates available
- Direct access to input shader output via `eval()`

### 10.2 AGSL Shader Structure Optimization

```agsl
// Optimized AGSL shader structure
uniform shader input;        // Input from Skia pipeline
uniform float2 resolution;   // Viewport resolution
uniform float time;          // Animation time
uniform float3 cameraPos;    // Camera position
uniform sampler2D albedoMap;
uniform sampler2D normalMap;
uniform sampler2D metallicRoughnessMap;
uniform sampler2D irradianceMap;
uniform sampler2D radianceMap;
uniform sampler2D brdfLUT;

// Material properties
uniform float metallic;
uniform float roughness;
uniform vec3 albedo;

// Lighting
uniform vec3 lightPositions[4];
uniform vec3 lightColors[4];

vec4 main(vec2 coords) {
    // Normalized coordinates
    vec2 uv = coords / resolution;
    
    // Sample input shader
    vec4 inputColor = input.eval(coords);
    
    // Skip processing if fully transparent
    if (inputColor.a < 0.01) {
        return inputColor;
    }
    
    // Calculate PBR lighting
    vec3 normal = DecodeNormal(texture(normalMap, uv).rgb);
    vec3 viewDir = normalize(cameraPos - vec3(uv, 0.0));  // Simplified
    
    vec3 lighting = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        vec3 lightDir = normalize(lightPositions[i] - vec3(uv, 0.0));
        lighting += CalculatePBR(albedo, metallic, roughness, normal, lightDir, viewDir);
        lighting *= lightColors[i];
    }
    
    // Add IBL
    lighting += CalculateIBL(normal, viewDir, albedo, metallic, roughness,
                             irradianceMap, radianceMap, brdfLUT);
    
    return vec4(lighting, inputColor.a);
}
```

### 10.3 Uniform Optimization

```agsl
// Batch uniform updates
void UpdateUniforms(RuntimeShader shader, float time, vec2 resolution) {
    shader.setFloatUniform("time", time);
    shader.setFloatUniform("resolution.x", resolution.x);
    shader.setFloatUniform("resolution.y", resolution.y);
}

// Precompute uniform values
struct UniformCache {
    float time;
    vec2 resolution;
    vec3 cameraPos;
    float metallic;
    float roughness;
    vec3 albedo;
};

UniformCache cacheUniforms(float t, vec2 res, vec3 camPos, float met, float rough, vec3 alb) {
    UniformCache cache;
    cache.time = t;
    cache.resolution = res;
    cache.cameraPos = camPos;
    cache.metallic = met;
    cache.roughness = rough;
    cache.albedo = alb;
    return cache;
}
```

### 10.4 Memory Optimization

```agsl
// Shared uniform buffer
uniform LightingData {
    vec3 lightPositions[4];
    vec3 lightColors[4];
    int lightCount;
} lights;

// Packed material uniforms
uniform MaterialData {
    vec3 albedo;
    float metallic;
    float roughness;
    float padding1;
    float padding2;
} material;

// Reduced texture sampling
vec3 OptimizedSampling(vec2 uv) {
    // Pack albedo and metallicRoughness into single sample
    vec4 albedoSample = texture(albedoMap, uv);
    vec4 mrSample = texture(metallicRoughnessMap, uv);
    
    return albedoSample.rgb;  // Simplified return
}
```

### 10.5 Runtime Shader Compilation

```agsl
// Lazy shader compilation
uniform bool shaderCompiled;
uniform float compileTime;

// Skip expensive calculations during compilation
vec4 main(vec2 coords) {
    if (!shaderCompiled) {
        return vec4(0.0);  // Return black during compilation
    }
    
    // Normal shader execution
    vec2 uv = coords / resolution;
    vec4 inputColor = input.eval(coords);
    
    // PBR calculations
    // ...
    
    return finalColor;
}
```

---

## 11. Multiple Light Source Handling

### 11.1 Forward Lighting

Forward rendering processes each light separately per object.

```agsl
// Forward lighting structure
struct Light {
    vec3 position;
    vec3 color;
    float intensity;
    float radius;
};

// Calculate single light contribution
vec3 CalculateLight(Light light, vec3 worldPos, vec3 normal, vec3 viewDir,
                    vec3 albedo, float metallic, float roughness) {
    vec3 lightDir = normalize(light.position - worldPos);
    float distance = length(light.position - worldPos);
    
    // Distance attenuation
    float attenuation = CalculateAttenuation(distance, light.radius);
    vec3 radiance = light.color * light.intensity * attenuation;
    
    // PBR lighting
    vec3 N = normal;
    vec3 L = lightDir;
    vec3 V = viewDir;
    
    return CalculatePBR(albedo, metallic, roughness, N, L, V) * radiance;
}

// Multiple forward lights
vec3 CalculateForwardLights(Light[4] lights, vec3 worldPos, vec3 normal, vec3 viewDir,
                            vec3 albedo, float metallic, float roughness) {
    vec3 lighting = vec3(0.0);
    
    for (int i = 0; i < 4; i++) {
        lighting += CalculateLight(lights[i], worldPos, normal, viewDir,
                                   albedo, metallic, roughness);
    }
    
    return lighting;
}
```

### 11.2 Deferred Lighting

Deferred lighting separates geometry and lighting passes.

```agsl
// G-Buffer structure
struct GBuffer {
    vec3 albedo;
    vec3 normal;
    float metallic;
    float roughness;
    float depth;
};

// Lighting pass
vec3 CalculateDeferredLighting(GBuffer gbuffer, Light light, vec2 screenUV, vec3 viewDir) {
    vec3 worldPos = ReconstructWorldPos(gbuffer.depth, screenUV);
    vec3 lightDir = normalize(light.position - worldPos);
    float distance = length(light.position - worldPos);
    
    float attenuation = CalculateAttenuation(distance, light.radius);
    vec3 radiance = light.color * light.intensity * attenuation;
    
    return CalculatePBR(gbuffer.albedo, gbuffer.metallic, gbuffer.roughness,
                       gbuffer.normal, lightDir, viewDir) * radiance;
}
```

### 11.3 Tiled/Clustered Lighting

```agsl
// Tile-based lighting
struct TileLightData {
    int lightIndices[32];
    int lightCount;
};

uniform TileLightData tileLights[64];

// Calculate tiled lighting
vec3 CalculateTiledLighting(vec2 screenUV, vec3 worldPos, vec3 normal, vec3 viewDir,
                            vec3 albedo, float metallic, float roughness) {
    // Calculate tile index
    ivec2 tileCoord = ivec2(screenUV * vec2(16.0, 9.0));  // 16x9 tiles
    int tileIndex = tileCoord.y * 16 + tileCoord.x;
    
    vec3 lighting = vec3(0.0);
    TileLightData tileData = tileLights[tileIndex];
    
    for (int i = 0; i < tileData.lightCount; i++) {
        int lightIndex = tileData.lightIndices[i];
        Light light = globalLights[lightIndex];
        
        lighting += CalculateLight(light, worldPos, normal, viewDir,
                                   albedo, metallic, roughness);
    }
    
    return lighting;
}
```

### 11.4 Light Culling

```agsl
// Frustum culling for lights
bool IsLightVisible(Light light, vec3 viewPos, vec3 viewDir, float fov) {
    vec3 lightViewPos = (viewMatrix * vec4(light.position, 1.0)).xyz;
    vec3 lightDir = normalize(lightViewPos);
    
    float angle = acos(dot(lightDir, viewDir));
    return angle < fov * 0.5;
}

// Distance culling
bool IsLightInRange(Light light, vec3 worldPos, float maxDistance) {
    float distance = length(light.position - worldPos);
    return distance < maxDistance;
}

// Combined light culling
bool ShouldRenderLight(Light light, vec3 worldPos, vec3 viewPos, vec3 viewDir, float fov) {
    return IsLightVisible(light, viewPos, viewDir, fov) &&
           IsLightInRange(light, worldPos, light.radius);
}
```

### 11.5 Mobile Light Management

```agsl
// Adaptive light count
uniform int maxLights;  // Set based on device capability

vec3 CalculateAdaptiveLighting(Light[8] lights, vec3 worldPos, vec3 normal, vec3 viewDir,
                                vec3 albedo, float metallic, float roughness) {
    vec3 lighting = vec3(0.0);
    int lightCount = min(maxLights, 8);
    
    for (int i = 0; i < lightCount; i++) {
        if (ShouldRenderLight(lights[i], worldPos, viewPos, viewDir, PI / 3.0)) {
            lighting += CalculateLight(lights[i], worldPos, normal, viewDir,
                                       albedo, metallic, roughness);
        }
    }
    
    return lighting;
}

// Light importance sorting
float CalculateLightImportance(Light light, vec3 worldPos, vec3 normal) {
    vec3 lightDir = normalize(light.position - worldPos);
    float distance = length(light.position - worldPos);
    float NdotL = max(dot(normal, lightDir), 0.0);
    
    return light.intensity * NdotL / (distance * distance);
}
```

---

## 12. Shadow Mapping Techniques

### 12.1 Basic Shadow Mapping

```agsl
// Basic shadow map calculation
float CalculateShadow(sampler2D shadowMap, vec4 shadowCoord, float bias) {
    vec3 projCoords = shadowCoord.xyz / shadowCoord.w;
    projCoords = projCoords * 0.5 + 0.5;
    
    float closestDepth = texture(shadowMap, projCoords.xy).r;
    float currentDepth = projCoords.z;
    
    float shadow = currentDepth - bias > closestDepth ? 1.0 : 0.0;
    
    return shadow;
}

// Mobile-optimized shadow mapping
float MobileShadow(sampler2D shadowMap, vec4 shadowCoord) {
    vec3 projCoords = shadowCoord.xyz / shadowCoord.w;
    projCoords = projCoords * 0.5 + 0.5;
    
    if (projCoords.z > 1.0) {
        return 0.0;  // Outside shadow range
    }
    
    float closestDepth = texture(shadowMap, projCoords.xy).r;
    float bias = 0.005;
    return step(closestDepth + bias, projCoords.z);
}
```

### 12.2 PCF (Percentage-Closer Filtering)

```agsl
// PCF shadow filtering
float CalculateShadowPCF(sampler2D shadowMap, vec4 shadowCoord, int samples) {
    vec3 projCoords = shadowCoord.xyz / shadowCoord.w;
    projCoords = projCoords * 0.5 + 0.5;
    
    float shadow = 0.0;
    vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
    
    for (int x = -samples; x <= samples; x++) {
        for (int y = -samples; y <= samples; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float closestDepth = texture(shadowMap, projCoords.xy + offset).r;
            float currentDepth = projCoords.z;
            shadow += currentDepth > closestDepth ? 1.0 : 0.0;
        }
    }
    
    shadow /= ((float(samples) * 2.0 + 1.0) * (float(samples) * 2.0 + 1.0));
    return shadow;
}

// Mobile PCF with reduced samples
float MobilePCF(sampler2D shadowMap, vec4 shadowCoord) {
    vec3 projCoords = shadowCoord.xyz / shadowCoord.w;
    projCoords = projCoords * 0.5 + 0.5;
    
    float shadow = 0.0;
    vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
    
    // 2x2 kernel for mobile
    for (int x = 0; x <= 1; x++) {
        for (int y = 0; y <= 1; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float closestDepth = texture(shadowMap, projCoords.xy + offset).r;
            shadow += step(closestDepth, projCoords.z);
        }
    }
    
    return shadow * 0.25;
}
```

### 12.3 Cascaded Shadow Maps (CSM)

```agsl
// Cascaded shadow map structure
struct CascadeData {
    mat4 viewProjection;
    float splitDistance;
};

uniform CascadeData cascades[4];

// Select appropriate cascade
int SelectCascade(float distance) {
    for (int i = 0; i < 4; i++) {
        if (distance < cascades[i].splitDistance) {
            return i;
        }
    }
    return 3;  // Fallback to last cascade
}

// Calculate cascaded shadow
float CalculateCascadedShadow(sampler2D[4] shadowMaps, vec3 worldPos, float distance) {
    int cascade = SelectCascade(distance);
    vec4 shadowCoord = cascades[cascade].viewProjection * vec4(worldPos, 1.0);
    
    return MobileShadow(shadowMaps[cascade], shadowCoord);
}

// Mobile-optimized CSM
float MobileCSM(sampler2D[4] shadowMaps, vec3 worldPos, float distance) {
    // Use only 2 cascades for mobile
    int cascade = distance < 10.0 ? 0 : 1;
    vec4 shadowCoord = cascades[cascade].viewProjection * vec4(worldPos, 1.0);
    
    return MobileShadow(shadowMaps[cascade], shadowCoord);
}
```

### 12.4 Soft Shadows

```agsl
// Soft shadow with PCSS
float CalculateSoftShadow(sampler2D shadowMap, vec4 shadowCoord, float lightSize) {
    vec3 projCoords = shadowCoord.xyz / shadowCoord.w;
    projCoords = projCoords * 0.5 + 0.5;
    
    float blockerDepth = FindBlocker(shadowMap, projCoords, lightSize);
    if (blockerDepth < 0.0) return 0.0;  // No blocker
    
    float penumbraWidth = (projCoords.z - blockerDepth) * lightSize / blockerDepth;
    return CalculateShadowPCF(shadowMap, shadowCoord, int(penumbraWidth));
}

// Find blocker depth
float FindBlocker(sampler2D shadowMap, vec3 projCoords, float lightSize) {
    float blockerDepth = 0.0;
    int blockerCount = 0;
    
    vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
    int searchWidth = int(lightSize);
    
    for (int x = -searchWidth; x <= searchWidth; x++) {
        for (int y = -searchWidth; y <= searchWidth; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float depth = texture(shadowMap, projCoords.xy + offset).r;
            
            if (depth < projCoords.z) {
                blockerDepth += depth;
                blockerCount++;
            }
        }
    }
    
    if (blockerCount == 0) return -1.0;
    return blockerDepth / float(blockerCount);
}
```

### 12.5 Shadow Quality Optimization

```agsl
// Adaptive shadow quality
uniform float shadowQuality;  // 0.0 = low, 1.0 = high

float AdaptiveShadow(sampler2D shadowMap, vec4 shadowCoord, vec3 normal, vec3 lightDir) {
    float NdotL = max(dot(normal, lightDir), 0.0);
    
    // Reduce shadow quality at grazing angles
    if (NdotL < 0.1) {
        return 0.0;  // Skip shadow calculation
    }
    
    if (shadowQuality > 0.5) {
        return CalculateShadowPCF(shadowMap, shadowCoord, 2);
    } else {
        return MobileShadow(shadowMap, shadowCoord);
    }
}

// Distance-based shadow quality
float DistanceBasedShadow(sampler2D shadowMap, vec4 shadowCoord, float distance) {
    if (distance > 20.0) {
        return MobileShadow(shadowMap, shadowCoord);  // Low quality
    } else if (distance > 10.0) {
        return MobilePCF(shadowMap, shadowCoord);  // Medium quality
    } else {
        return CalculateShadowPCF(shadowMap, shadowCoord, 2);  // High quality
    }
}
```

---

## Conclusion

This comprehensive research document covers the implementation of physically-based rendering and advanced lighting algorithms specifically optimized for mobile AGSL shaders. The key takeaways are:

### Performance Optimization Strategies
1. **Reduce Texture Sampling**: Use packed textures and LOD control
2. **Minimize Branching**: Use mix() instead of if-else statements
3. **Precompute Values**: Calculate shared terms once and reuse
4. **Adaptive Quality**: Scale quality based on device capabilities
5. **Memory Optimization**: Use half-precision and compressed textures

### Mobile-Specific Considerations
1. **GPU Limitations**: Account for limited computational power and memory bandwidth
2. **AGSL Integration**: Leverage Skia's rendering pipeline and RuntimeShader API
3. **Battery Life**: Balance visual quality with power consumption
4. **Thermal Throttling**: Implement adaptive quality scaling

### Implementation Recommendations
1. **Start Simple**: Implement basic PBR before adding advanced features
2. **Profile Continuously**: Measure performance on target devices
3. **Optimize Iteratively**: Apply optimizations based on profiling data
4. **Fallback Strategies**: Provide quality levels for different device capabilities

### Future Research Directions
1. **Machine Learning Integration**: Use AI for adaptive quality scaling
2. **Vulkan Integration**: Leverage modern GPU capabilities
3. **Compute Shaders**: Offload calculations to compute pipeline
4. **Advanced Approximations**: Develop better ray tracing approximations

This research provides a solid foundation for implementing high-quality PBR rendering on mobile devices using AGSL, balancing visual fidelity with performance constraints.

---

## References

1. Cook, R. L., & Torrance, K. E. (1982). "A Reflectance Model for Computer Graphics"
2. Walter, B., Marschner, S. R., Li, H., & Torrance, K. E. (2007). "Microfacet Models for Refraction through Rough Surfaces"
3. Lagarde, S., & de Rousiers, C. (2014). "Moving Frostbite to Physically Based Rendering"
4. Karis, B. (2013). "Real Shading in Unreal Engine 4"
5. AGSL Documentation: https://developer.android.com/develop/ui/views/graphics/agsl
6. Skia Shading Language: https://skia.org/docs/user/sksl/
7. Qualcomm Adreno GPU Best Practices
8. Mobile GPU Optimization Techniques for Real-Time Rendering

---

**Document Version**: 1.0
**Last Updated**: August 5, 2026
**Research Completed By**: Research Analyst Agent