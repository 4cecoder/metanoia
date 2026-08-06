# PBR Lighting System for Android (AGSL)

A comprehensive, mobile-optimized physically-based rendering lighting system for Android using AGSL (Android Graphics Shading Language). This system provides realistic lighting effects with full PBR support, energy conservation, and adaptive quality scaling.

## Features

### Core PBR Implementation
- **Cook-Torrance BRDF**: Full implementation with GGX distribution, Schlick's Fresnel, and Smith geometry functions
- **Energy Conservation**: Ensures physically accurate light interaction
- **Material System**: Complete material properties including albedo, roughness, metallic, emissive, and normal maps
- **Multiple Light Types**: Point, directional, and spot lights with proper attenuation

### Mobile Optimization
- **Adaptive Quality**: Automatic quality adjustment based on device performance
- **Quality Presets**: Pre-configured settings for low, mid, high, and ultra devices
- **Light Culling**: Efficient light management based on distance and view frustum
- **Optimized Shaders**: Mobile-specific shader variants for reduced computational cost
- **Memory Management**: Texture compression, LOD bias, and efficient resource usage

### Advanced Features
- **Image-Based Lighting (IBL)**: Environment map support for realistic reflections
- **Shadow Mapping**: PCF soft shadows with cascaded shadow maps
- **Screen-Space Effects**: Ambient occlusion and reflections
- **Material Blending**: Support for layered and blended materials
- **Real-time Animation**: Dynamic light position updates and material property animation

## Components

### 1. LightingSystemConfig.kt
Configuration system for the entire PBR lighting pipeline.

```kotlin
val config = LightingSystemConfig.highEnd()
```

**Key Features:**
- Quality presets (LOW, MEDIUM, HIGH, ULTRA)
- Mobile optimization levels
- Light and shadow configuration
- IBL and screen-space effects
- Performance tuning parameters

### 2. PBRMaterial.kt
Material property definitions and validation.

```kotlin
val material = PBRMaterial(
    albedo = Color.White,
    metallic = 0.8f,
    roughness = 0.3f,
    emissive = Color.Black,
    normalStrength = 1.0f,
    occlusion = 1.0f,
    opacity = 1.0f
)
```

**Predefined Materials:**
- `defaultDielectric()`: Plastic-like material
- `defaultMetallic()`: Metal-like material
- `glass()`: Transparent glass material
- `mirror()`: Perfect mirror material
- `matte()`: Matte finish material
- `glossyPlastic()`: Glossy plastic material
- `roughMetal()`: Rough metal surface
- `emissive()`: Self-illuminating material

### 3. CookTorranceBRDF.kt
AGSL shader implementations for PBR rendering.

**Shaders Included:**
- `PBR_SHADER`: Full PBR implementation with all features
- `MOBILE_OPTIMIZED_SHADER`: Simplified version for mobile devices
- `BRDF_INTEGRATION_SHADER`: For environment map prefiltering

**Key Functions:**
- `distributionGGX()`: GGX/Trowbridge-Reitz distribution
- `fresnelSchlick()`: Schlick's Fresnel approximation
- `geometrySmith()`: Smith geometry function
- `calculatePBR()`: Complete PBR calculation
- `calculateIBL()`: Image-based lighting

### 4. DynamicLightingManager.kt
Light source management and composition system.

```kotlin
val manager = DynamicLightingManager(config).apply {
    setupDefaultLighting()
    // Add custom lights
    addLight(LightSource.warmLight())
    addLight(LightSource.coolLight())
}
```

**Features:**
- Multiple light source support (up to 8 lights)
- Light culling based on importance
- Real-time light position updates
- Performance tracking and metrics
- Pre-configured lighting setups:
  - `setupDefaultLighting()`: Standard three-point lighting
  - `setupDramaticLighting()`: Dramatic cinematic setup
  - `setupStudioLighting()`: Professional studio setup

### 5. PBRIntegrationExamples.kt
Comprehensive examples demonstrating system usage.

**Examples Include:**
- Material library showcase
- Quality preset comparisons
- Dynamic multi-light setups
- Cinematic lighting configurations
- Animated material properties

## Usage Examples

### Basic PBR Material

```kotlin
@Composable
fun BasicPBRExample() {
    val material = PBRMaterial.defaultMetallic()
    val manager = DynamicLightingManager().apply {
        setupDefaultLighting()
    }
    
    Box(
        modifier = Modifier
            .size(200.dp)
            .then(
                DynamicLightingModifiers.applyPBRLighting(
                    manager = manager,
                    material = material,
                    time = 0f,
                    cameraPosition = Offset(50f, 50f)
                )
            )
    )
}
```

### Custom Material with Animation

```kotlin
@Composable
fun AnimatedMaterialExample() {
    var time by remember { mutableStateOf(0f) }
    
    val animatedMaterial = PBRMaterial(
        albedo = Color(
            red = 0.5f + 0.3f * sin(time),
            green = 0.5f + 0.3f * sin(time + 2f),
            blue = 0.5f + 0.3f * sin(time + 4f)
        ),
        metallic = 0.3f + 0.2f * sin(time * 0.5f),
        roughness = 0.4f + 0.2f * cos(time * 0.3f)
    )
    
    // Apply lighting...
}
```

### Quality-Adaptive Rendering

```kotlin
val config = when (devicePerformance) {
    DevicePerformance.LOW -> LightingSystemConfig.lowEnd()
    DevicePerformance.MEDIUM -> LightingSystemConfig.midRange()
    DevicePerformance.HIGH -> LightingSystemConfig.highEnd()
}

val manager = DynamicLightingManager(config)
```

### Cinematic Lighting Setup

```kotlin
Box(
    modifier = Modifier
        .fillMaxSize()
        .then(DynamicLightingModifiers.cinematicLighting(
            material = PBRMaterial.defaultDielectric(),
            time = time
        ))
)
```

## Performance Optimization

### Mobile Optimization Strategies

1. **Quality Presets**: Use appropriate quality preset for target device
2. **Light Culling**: Enable light culling to reduce shader calculations
3. **LOD Bias**: Increase LOD bias for distant objects
4. **Texture Compression**: Enable texture compression for memory efficiency
5. **Adaptive Quality**: Enable automatic quality adjustment

### Performance Monitoring

```kotlin
val stats = manager.getPerformanceStats()
println("FPS: ${stats fps}")
println("Frame Time: ${stats.frameTimeMs}ms")
println("Active Lights: ${stats.activeLightCount}")
```

## Shader Configuration

### Material Properties (Uniforms)

```agsl
uniform float3 albedo;          // Base color [0-1]
uniform float metallic;         // Metallic property [0-1]
uniform float roughness;        // Roughness property [0.04-1]
uniform float3 emissive;        // Emissive color [0-1]
uniform float normalStrength;   // Normal map strength [0-2]
uniform float occlusion;        // Ambient occlusion [0-1]
uniform float opacity;          // Material opacity [0-1]
```

### Light Properties (Uniforms)

```agsl
uniform int lightCount;                      // Number of active lights
uniform float3 lightPositions[8];            // Light positions
uniform float3 lightColors[8];               // Light colors
uniform float lightIntensities[8];           // Light intensities
uniform int lightTypes[8];                   // Light types (0=point, 1=directional, 2=spot)
uniform float3 lightDirections[8];           // Light directions
uniform float lightSpotAngles[8];            // Spot light angles
```

## Advanced Features

### Material Blending

```kotlin
val baseMaterial = PBRMaterial.defaultDielectric()
val topMaterial = PBRMaterial.glossyPlastic(Color.Red)
val blendedMaterial = baseMaterial.blendWith(topMaterial, 0.5f)
```

### Layered Materials

```kotlin
val layers = listOf(
    MaterialLayer(baseMaterial, 1.0f),
    MaterialLayer(detailMaterial, 0.3f, BlendMode.MULTIPLY),
    MaterialLayer(wearMaterial, 0.2f, BlendMode.ADD)
)
```

### Custom Light Sources

```kotlin
val customLight = LightSource(
    type = LightType.SPOT,
    position = Offset(0.5f, 0.3f),
    color = Color(1f, 0.9f, 0.7f),
    intensity = 1.2f,
    spotAngle = 45f,
    castsShadow = true
)

manager.addLight(customLight)
```

## Best Practices

1. **Use Quality Presets**: Start with preset configurations and adjust as needed
2. **Enable Light Culling**: Always enable light culling for mobile devices
3. **Limit Light Count**: Use the minimum number of lights required
4. **Validate Materials**: Always validate materials after creation
5. **Monitor Performance**: Regularly check performance metrics
6. **Adapt to Device**: Use adaptive quality for varying device capabilities
7. **Texture Optimization**: Use compressed textures and appropriate resolution
8. **Batch Updates**: Group light updates to minimize uniform changes

## Technical Specifications

### Supported Android Versions
- Minimum: Android 13 (API 33) - Required for AGSL RuntimeShader
- Recommended: Android 14+ for best performance

### Performance Targets
- Low-end devices: 30 FPS with reduced quality
- Mid-range devices: 60 FPS with medium quality
- High-end devices: 60 FPS with high/ultra quality

### Memory Limits
- Default max memory: 256MB
- Texture compression enabled by default
- Automatic LOD adjustment for memory management

### Light Limitations
- Maximum lights: 8 (configurable)
- Dynamic lights: Up to 4 for mobile optimization
- Shadow cascades: 1-4 depending on quality setting

## Troubleshooting

### Performance Issues
1. Reduce quality preset
2. Enable mobile optimizations
3. Increase LOD bias
4. Reduce maximum light count
5. Disable expensive features (SSR, high-quality SSAO)

### Visual Artifacts
1. Validate material properties
2. Check normal map strength
3. Verify light positions
4. Ensure proper camera setup
5. Check shadow map resolution

### Compilation Errors
1. Verify Android API level (33+)
2. Check AGSL syntax in shaders
3. Ensure all uniform types match
4. Validate light array indices
5. Check for division by zero in shaders

## Integration with Existing Lighting Effects

The PBR lighting system is designed to integrate seamlessly with the existing `LightingEffects.kt`:

```kotlin
// Combine with existing effects
Box(
    modifier = Modifier
        .realisticShadow( // Existing effect
            lightPosition = Offset(0.5f, 0.3f),
            config = ShadowConfig()
        )
        .then(DynamicLightingModifiers.applyPBRLighting( // New PBR
            manager = manager,
            material = material
        ))
        .reflection( // Existing effect
            config = ReflectionConfig()
        )
)
```

## Future Enhancements

- Vulkan compute shader integration
- Machine learning-based quality scaling
- Advanced ray tracing approximations
- Temporal anti-aliasing
- Screen-space global illumination
- Volumetric lighting support

## References

Based on the research document `docs/research/pbr_lighting_agsl.md` implementing:
- Cook-Torrance BRDF from Cook & Torrance (1982)
- GGX distribution from Walter et al. (2007)
- Mobile optimization techniques from industry best practices
- AGSL-specific optimizations for Android platform

## License

Part of the Metanoia project. See main project license for details.

## Contributing

When contributing to the PBR lighting system:
1. Maintain mobile optimization focus
2. Test on multiple device tiers
3. Benchmark performance changes
4. Update documentation
5. Add examples for new features

---

For detailed implementation information, see the research document at `docs/research/pbr_lighting_agsl.md`.