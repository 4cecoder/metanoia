# Advanced Graphics Effects System - Core Architecture

## Overview

The core modular architecture for the advanced graphics effects system provides a production-ready framework for managing, composing, and optimizing visual effects in the Metanoia app. This system integrates seamlessly with existing effects like `ParallaxEffects.kt` and `LightingEffects.kt`.

## Architecture Components

### 1. EffectsPipeline.kt - Core Pipeline Orchestrator

The central orchestrator for the entire effects system, managing:
- **Effect Composition**: Coordinates multiple effects in a unified pipeline
- **Order Management**: Ensures proper rendering order with priority-based sorting
- **Pass Coordination**: Manages render passes and their execution
- **Resource Lifecycle**: Handles creation, caching, and cleanup of graphics resources

**Key Features:**
- State-based pipeline management (IDLE, INITIALIZING, READY, RENDERING, ERROR, SHUTTING_DOWN)
- Real-time render statistics tracking (FPS, frame time, memory usage, GPU usage)
- Automatic dependency resolution and effect reordering
- Coroutine-based async operations for non-blocking performance

**Usage Example:**
```kotlin
val pipeline = EffectsPipeline(context, qualityManager)
pipeline.initialize()

// Add effects to pipeline
val parallaxHandle = pipeline.addEffect(
    effect = ParallaxEffectWrapper(ParallaxConfig()),
    priority = EffectPriority.NORMAL
)

// Apply effects to Compose modifier
val modifier = pipeline.applyEffects(baseModifier, frameTime = deltaTime)
```

### 2. EffectRegistry.kt - Effect Management System

Dynamic registration and discovery system for effects:
- **Dynamic Registration**: Register custom effects at runtime
- **Auto-Discovery**: Automatic discovery of built-in and plugin effects
- **Dependency Management**: Validates and resolves effect dependencies
- **Lifecycle Callbacks**: Notifications for effect lifecycle events

**Key Features:**
- Thread-safe effect registration with mutex protection
- Built-in effect support (parallax, lighting, shadow, reflection, glassmorphism, cyberpunk)
- Circular dependency detection and validation
- Resource requirement validation (memory, GPU capabilities)
- Extensible listener system for lifecycle events

**Usage Example:**
```kotlin
val registry = EffectRegistry(context)
registry.initialize()

// Register custom effect
val factory = CustomEffectFactory()
val metadata = EffectMetadata(
    id = "custom_effect",
    name = "Custom Effect",
    version = "1.0.0",
    description = "My custom visual effect",
    category = EffectCategory.CUSTOM,
    dependencies = emptySet(),
    minApiLevel = 21,
    resourceRequirements = ResourceRequirements(memoryMb = 8f, gpuRequired = false)
)

registry.registerEffect("custom_effect", factory, metadata)

// Create effect instance
val effect = registry.createEffect("custom_effect")
```

### 3. EffectComposer.kt - Effect Composition System

Advanced composition engine for combining multiple effects:
- **Multi-Effect Composition**: Layer multiple effects with sophisticated blending
- **Blending Modes**: Support for 16+ blend modes (Normal, Multiply, Screen, Overlay, etc.)
- **Pass Management**: Organize effects into render passes with pre/post operations
- **Effect Chaining**: Chain multiple compositions together

**Key Features:**
- Composition-based effect management (up to 16 layers per composition)
- Z-index based layer ordering
- Configurable opacity and blend modes per layer
- Pass-based rendering with pre/post processing
- Composition caching and optimization

**Usage Example:**
```kotlin
val composer = EffectComposer(pipeline)

// Create composition
composer.createComposition("main_composition", CompositionConfig())

// Add effect layers
composer.addLayer(
    compositionId = "main_composition",
    effect = ParallaxEffectWrapper(),
    config = parallaxConfig,
    blendMode = BlendMode.NORMAL
)

composer.addLayer(
    compositionId = "main_composition",
    effect = LightingEffectWrapper(),
    config = lightingConfig,
    blendMode = BlendMode.ADD
)

// Apply composition
val modifier = composer.applyComposition(baseModifier, "main_composition", time)
```

### 4. GraphicsQualityManager.kt - Quality Presets & Performance

Performance optimization system with dynamic quality adjustment:
- **Quality Presets**: Low, Medium, High, Ultra with configurable parameters
- **Dynamic Adjustment**: Automatic quality adjustment based on performance metrics
- **Performance Monitoring**: Real-time FPS, memory, GPU, CPU, thermal monitoring
- **Device Capability Matching**: Auto-detect and match device capabilities

**Key Features:**
- Automatic device capability detection (GPU, CPU, memory, display)
- Adaptive quality adjustment based on performance metrics
- Thermal state monitoring and throttling
- Quality-specific effect filtering (e.g., disable shadows on low-end devices)
- Performance statistics and reporting

**Quality Presets:**

| Feature | Low | Medium | High | Ultra |
|---------|-----|--------|------|-------|
| Max Effects | 3 | 6 | 10 | 16 |
| Texture Resolution | 512px | 1024px | 2048px | 4096px |
| Shadows | ❌ | ✅ | ✅ | ✅ |
| Lighting | ❌ | ✅ | ✅ | ✅ |
| Reflections | ❌ | ❌ | ✅ | ✅ |
| Target FPS | 30 | 45 | 60 | 60 |
| Max Memory | 100MB | 200MB | 400MB | 800MB |

**Usage Example:**
```kotlin
val qualityManager = GraphicsQualityManager(context)
qualityManager.initialize()

// Set quality manually
qualityManager.setQuality(GraphicsQuality.HIGH)

// Enable adaptive quality
qualityManager.setAdaptiveQualityEnabled(true)

// Check if effect should be applied
if (qualityManager.shouldApplyEffect(effect)) {
    // Apply effect
}

// Get performance metrics
val metrics = qualityManager.performanceMetrics.value
Log.d("Performance", "FPS: ${metrics.fps}, Memory: ${metrics.memoryUsedMb}MB")
```

## Integration with Existing Effects

### ParallaxEffects Integration

The system provides seamless integration with existing `ParallaxEffects.kt`:

```kotlin
// Wrap existing parallax effect
val parallaxEffect = ParallaxEffectWrapper(
    ParallaxConfig(depth = 2f, intensity = 0.7f)
)

// Add to pipeline
pipeline.addEffect(parallaxEffect, EffectPriority.NORMAL)

// Use in composition
composer.addLayer(
    compositionId = "main",
    effect = parallaxEffect,
    config = parallaxEffect.defaultConfig(),
    blendMode = BlendMode.NORMAL
)
```

### LightingEffects Integration

Full support for existing `LightingEffects.kt`:

```kotlin
// Wrap existing lighting effect
val lightingEffect = LightingEffectWrapper(
    LightSource(
        position = Offset(0.5f, 0.3f),
        intensity = 1f,
        color = Color.White
    )
)

// Add to pipeline
pipeline.addEffect(lightingEffect, EffectPriority.HIGH)

// Use in composition
composer.addLayer(
    compositionId = "main",
    effect = lightingEffect,
    config = lightingEffect.defaultConfig(),
    blendMode = BlendMode.ADD
)
```

### ShadowEffects Integration

Support for shadow effects:

```kotlin
// Wrap existing shadow effect
val shadowEffect = ShadowEffectWrapper(
    ShadowConfig(
        blurRadius = 16f,
        opacity = 0.3f,
        offset = Offset(4f, 8f)
    )
)

// Add to pipeline
pipeline.addEffect(shadowEffect, EffectPriority.HIGH)
```

## Advanced Features

### Effect Dependencies

Effects can declare dependencies for proper ordering:

```kotlin
class MyEffect : Effect {
    override val dependencies = setOf(ParallaxEffectWrapper::class)
    
    // Effect implementation
}
```

### Custom Effect Creation

Create custom effects by implementing the `Effect` interface:

```kotlin
class CustomEffect : Effect {
    override val name = "custom_effect"
    override val version = "1.0.0"
    override val dependencies = emptySet<KClass<out Effect>>()
    
    override fun apply(
        modifier: Modifier,
        config: EffectConfig,
        time: Float
    ): Modifier {
        return modifier.graphicsLayer {
            // Apply effect logic
            alpha = config.intensity
        }
    }
    
    override fun defaultConfig(): EffectConfig = object : EffectConfig {
        override val enabled = true
        override val intensity = 1f
    }
}
```

### Performance Monitoring

Monitor system performance in real-time:

```kotlin
// Collect performance metrics
val metrics = qualityManager.performanceMetrics.value

// Access various metrics
Log.d("Performance", """
    FPS: ${metrics.fps}
    Frame Time: ${metrics.frameTimeMs}ms
    Memory: ${metrics.memoryUsedMb}MB / ${metrics.memoryTotalMb}MB
    GPU Usage: ${metrics.gpuUsage * 100}%
    CPU Usage: ${metrics.cpuUsage * 100}%
    Thermal State: ${metrics.thermalState}
""".trimIndent())
```

### Pipeline State Management

Monitor and manage pipeline state:

```kotlin
// Check pipeline state
when (pipeline.pipelineState.value) {
    PipelineState.READY -> {
        // Safe to apply effects
        val modifier = pipeline.applyEffects(baseModifier)
    }
    PipelineState.ERROR -> {
        // Handle error state
        Log.e("Pipeline", "Pipeline in error state")
    }
    else -> {
        // Other states
    }
}

// Get pipeline info
val info = pipeline.getPipelineInfo()
Log.d("Pipeline", """
    State: ${info.state}
    Active Effects: ${info.activeEffectCount}
    Quality: ${info.qualityLevel}
    FPS: ${info.statistics.fps}
""".trimIndent())
```

## Error Handling

Comprehensive error handling throughout the system:

```kotlin
// Safe effect registration
val result = registry.registerEffect(
    effectId = "my_effect",
    factory = MyEffectFactory(),
    metadata = metadata
)

result.onSuccess {
    Log.i("Registry", "Effect registered successfully")
}.onFailure { error ->
    Log.e("Registry", "Failed to register effect", error)
}

// Safe composition creation
val compositionResult = composer.createComposition("my_composition")
compositionResult.onSuccess { id ->
    Log.i("Composer", "Composition created: $id")
}.onFailure { error ->
    Log.e("Composer", "Failed to create composition", error)
}
```

## Performance Considerations

### Memory Management

- Automatic resource caching and cleanup
- Quality-based memory limits (100MB-800MB)
- Efficient render node pooling
- Memory pressure detection and adaptation

### GPU Optimization

- Device capability detection
- Quality-based effect filtering
- GPU usage monitoring
- Thermal throttling support

### CPU Optimization

- Coroutine-based async operations
- Efficient render pass batching
- Frame time budgeting
- Adaptive quality adjustment

## Best Practices

1. **Initialize Early**: Initialize pipeline and quality manager during app startup
2. **Use Adaptive Quality**: Enable adaptive quality for automatic performance optimization
3. **Monitor Performance**: Regularly check performance metrics and adjust accordingly
4. **Handle Errors**: Always handle Result types for safe error management
5. **Clean Up**: Release pipeline resources when no longer needed

```kotlin
// In your Activity/ViewModel
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    
    // Initialize effects system
    lifecycleScope.launch {
        pipeline.initialize()
        qualityManager.initialize()
        qualityManager.setAdaptiveQualityEnabled(true)
    }
}

override fun onDestroy() {
    lifecycleScope.launch {
        pipeline.release()
        qualityManager.shutdown()
    }
    super.onDestroy()
}
```

## Troubleshooting

### Effects Not Applying

1. Check if pipeline is in READY state
2. Verify effects are registered and enabled
3. Ensure device meets minimum API requirements
4. Check if quality settings allow the effect

### Performance Issues

1. Enable adaptive quality adjustment
2. Monitor performance metrics
3. Reduce number of active effects
4. Lower quality preset
5. Check for memory leaks

### Crashes on Low-End Devices

1. Set initial quality to LOW
2. Disable shader-based effects
3. Reduce texture resolution
4. Limit number of concurrent effects
5. Enable performance monitoring

## API Requirements

- **Minimum SDK**: 21 (Android 5.0)
- **Recommended SDK**: 33+ (Android 13) for full shader support
- **GPU**: OpenGL ES 2.0+ recommended
- **Memory**: Minimum 2GB RAM recommended

## Future Enhancements

- [ ] Compute shader support for better performance
- [ ] Material You integration
- [ ] Advanced post-processing effects
- [ ] Custom shader pipeline
- [ ] VR/AR effects support
- [ ] ML-based effect optimization
- [ ] Cloud-based effect downloading
- [ ] Effect marketplace integration

## Contributing

When adding new effects:

1. Implement the `Effect` interface
2. Create appropriate configuration classes
3. Register with the EffectRegistry
4. Add unit tests
5. Update documentation
6. Test on multiple device tiers

## License

Part of the Metanoia project. See main project license for details.