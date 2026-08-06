# Real-Time Fluid Physics for Mobile AGSL Shaders

## Research Document

**Date:** 2025-08-05
**Subject:** Comprehensive Research on Mobile-Optimized Fluid Simulation for Android Graphics Shading Language
**Target Platform:** Android 13+ (API Level 33+)

---

## Executive Summary

This document provides comprehensive research on implementing real-time fluid physics simulations using Android Graphics Shading Language (AGSL) for mobile platforms. The research covers Navier-Stokes equations, mobile-optimized techniques, performance considerations, and practical implementation strategies for GPU-accelerated fluid simulation in the Android ecosystem.

Key findings indicate that fluid simulation on mobile GPUs is achievable with careful optimization, proper use of semi-Lagrangian methods, and leveraging AGSL's strengths while working within its limitations.

---

## 1. Navier-Stokes Equations for Real-Time Simulation

### 1.1 Mathematical Foundation

The Navier-Stokes equations describe the motion of viscous fluid substances. For real-time simulation, we typically solve the **incompressible** formulation:

#### Continuity Equation (Incompressibility)
```
∇ · u = 0
```

Where `u` is the velocity field. This equation ensures fluid cannot be compressed.

#### Momentum Equation
```
∂u/∂t + (u · ∇)u = -(1/ρ)∇p + ν∇²u + f
```

Breaking down each term:

- **∂u/∂t**: Rate of velocity change over time
- **(u · ∇)u**: Advection (fluid carrying itself along)
- **-(1/ρ)∇p**: Pressure forces
- **ν∇²u**: Viscosity/diffusion (internal friction)
- **f**: External forces (gravity, user input)

### 1.2 Operator Splitting Approach

For real-time implementation, we use **operator splitting** to break the complex equations into manageable steps:

#### Simulation Pipeline (Per Frame)
```pseudocode
function simulateFrame(velocity, dye):
    // 1. Advect velocity and dye along the flow
    velocity = advect(velocity, velocity, dt)
    dye = advect(dye, velocity, dt)
    
    // 2. Apply diffusion (optional for fast fluids)
    velocity = diffuse(velocity, viscosity, dt)
    
    // 3. Add external forces
    velocity = addExternalForces(velocity, userInput, dt)
    
    // 4. Enforce incompressibility through pressure projection
    velocity = project(velocity)
    
    // 5. Optional: Add vorticity confinement for turbulence
    velocity = confineVorticity(velocity)
    
    return velocity, dye
```

This splitting allows each physical phenomenon to be solved independently, making GPU implementation feasible.

---

## 2. Mobile-Optimized Fluid Simulation Techniques

### 2.1 Resolution Strategy

Mobile devices have limited GPU memory and bandwidth compared to desktop systems:

```kotlin
data class SimulationResolution(
    val physicsResolution: Size = Size(128f, 128f),  // Low res for physics
    val visualResolution: Size = Size(512f, 512f),   // Medium res for visuals
    val displayResolution: Size = Size(1080f, 1920f) // Full resolution for display
)
```

**Rationale:**
- Physics at 128×128 provides enough resolution for realistic behavior
- Visuals at 512×512 balance quality and performance
- Display at screen resolution ensures sharp rendering
- Upsampling from physics to visual resolution happens during rendering

### 2.2 Semi-Lagrangian Stability

The **semi-Lagrangian method** provides unconditional stability, crucial for mobile where frame rates vary:

```
For each grid point, trace backward along velocity field:
p_source = p_current - v × Δt
```

This backward tracing eliminates gaps and ensures numerical stability even with large timesteps.

### 2.3 Implicit vs. Explicit Methods

**Explicit Methods** (calculating future values from current values):
- Simple to implement
- Conditionally stable (requires small timesteps)
- Prone to instability on mobile with variable frame rates

**Implicit Methods** (calculating current values as function of future values):
- Unconditionally stable
- Requires solving equation systems
- Better suited for mobile implementation

Our implementation uses implicit methods for both diffusion and pressure projection.

---

## 3. Pressure Projection and Diffusion Methods

### 3.1 Pressure Projection (Helmholtz-Hodge Decomposition)

Pressure projection enforces incompressibility by removing divergent components from the velocity field:

#### Mathematical Foundation
```
Velocity Field = Divergence-Free Component + Pressure Gradient Component

We want to find the divergence-free part:
u_divergence_free = u - ∇p
```

Where `p` is the pressure field that makes the velocity divergence-free.

#### Implementation Steps
```pseudocode
function project(velocity):
    // Step 1: Compute divergence of velocity field
    divergence = computeDivergence(velocity)
    
    // Step 2: Solve Poisson equation for pressure
    // ∇²p = divergence
    pressure = solvePoisson(divergence)
    
    // Step 3: Subtract pressure gradient from velocity
    velocity = subtractGradient(velocity, pressure)
    
    return velocity
```

### 3.2 Poisson Equation Solvers

#### Jacobi Iteration (Recommended for Mobile)

Simple, parallelizable, and well-suited for GPU implementation:

```
p[i,j]^(k+1) = (p[i+1,j]^k + p[i-1,j]^k + p[i,j+1]^k + p[i,j-1]^k - div[i,j]) / 4
```

**AGSL Implementation:**
```agsl
uniform shader uPressure;
uniform sampler2D uDivergence;
uniform vec2 uTexelSize;

vec4 main(vec2 coords) {
    // Sample neighboring pressures
    float pL = texture(uPressure, coords + vec2(-uTexelSize.x, 0.0)).r;
    float pR = texture(uPressure, coords + vec2(uTexelSize.x, 0.0)).r;
    float pB = texture(uPressure, coords + vec2(-0.0, -uTexelSize.y)).r;
    float pT = texture(uPressure, coords + vec2(0.0, uTexelSize.y)).r;
    
    // Sample divergence
    float div = texture(uDivergence, coords).r;
    
    // One Jacobi iteration
    float pressure = (pL + pR + pB + pT - div) * 0.25;
    
    return vec4(pressure, 0.0, 0.0, 1.0);
}
```

**Mobile Optimization:**
- 10-20 iterations for low quality (30 FPS on budget devices)
- 20-30 iterations for medium quality (60 FPS on mid-range devices)
- 30-40 iterations for high quality (60 FPS on flagship devices)

#### Alternative Solvers (Not Recommended for Mobile)

**Gauss-Seidel:** Faster convergence (2x), but requires sequential access, making GPU implementation inefficient.

**Multigrid:** Excellent convergence, but complex implementation and memory requirements unsuitable for mobile.

**Successive Overrelaxation:** Improved convergence, but requires careful tuning of relaxation parameter.

### 3.3 Implicit Diffusion

Unlike explicit diffusion which can explode, implicit diffusion is unconditionally stable:

#### Mathematical Formulation
```
d_new = (d_old + α * dt * ∑neighbors(d)) / (1 + 4 * α * dt)
```

Where:
- `d_old` is the previous frame's density
- `α` is the diffusion coefficient
- `dt` is the timestep

#### Implementation
```agsl
uniform sampler2D uQuantity;
uniform sampler2D uQuantityPrev;
uniform float uDiffusion;
uniform float uDt;
uniform vec2 uTexelSize;

vec4 main(vec2 coords) {
    float q = texture(uQuantityPrev, coords).r;
    
    // Sample neighbors
    float qL = texture(uQuantity, coords + vec2(-uTexelSize.x, 0.0)).r;
    float qR = texture(uQuantity, coords + vec2(uTexelSize.x, 0.0)).r;
    float qB = texture(uQuantity, coords + vec2(0.0, -uTexelSize.y)).r;
    float qT = texture(uQuantity, coords + vec2(0.0, uTexelSize.y)).r;
    
    float sum = qL + qR + qB + qT;
    float alpha = uDiffusion * uDt;
    
    // Implicit diffusion formula
    float result = (q + alpha * sum) / (1.0 + 4.0 * alpha);
    
    return vec4(result, 0.0, 0.0, 1.0);
}
```

**Mobile Consideration:** For visual effects, diffusion can often be skipped entirely, as numerical diffusion from advection provides sufficient smoothing.

---

## 4. Advection Algorithms for Mobile GPUs

### 4.1 Semi-Lagrangian Advection

The semi-Lagrangian method is the gold standard for real-time fluid simulation due to its unconditional stability and GPU-friendly memory access pattern.

#### Algorithm Overview

```
For each destination pixel:
1. Sample velocity at current position
2. Trace backward: sourcePos = currentPos - velocity × timestep
3. Sample quantity at sourcePos (with interpolation)
4. Write to destination
```

#### AGSL Implementation

```agsl
uniform sampler2D uQuantity;      // Quantity to advect (dye, velocity)
uniform sampler2D uVelocity;      // Velocity field
uniform float uDt;                // Timestep
uniform vec2 uTexelSize;          // Size of one texel in UV space
uniform float uDissipation;       // Optional dissipation factor

vec4 main(vec2 coords) {
    // Sample velocity at current position
    vec2 velocity = texture(uVelocity, coords).rg;
    
    // Convert velocity to UV space
    vec2 velocityUV = velocity * uTexelSize;
    
    // Trace backward in time
    vec2 sourceUV = coords - velocityUV * uDt;
    
    // Clamp to texture boundaries
    sourceUV = clamp(sourceUV, 0.0, 1.0);
    
    // Sample quantity at source position (linear interpolation)
    vec4 quantity = texture(uQuantity, sourceUV);
    
    // Apply optional dissipation
    quantity *= (1.0 - uDissipation);
    
    return quantity;
}
```

### 4.2 Enhanced Advection Techniques

#### MacCormack Scheme

For higher accuracy with minimal performance cost:

```agsl
vec4 main(vec2 coords) {
    vec2 velocity = texture(uVelocity, coords).rg;
    vec2 velocityUV = velocity * uTexelSize;
    
    // Forward semi-Lagrangian step
    vec2 forwardUV = coords + velocityUV * uDt;
    vec4 forwardSample = texture(uQuantity, clamp(forwardUV, 0.0, 1.0));
    
    // Backward semi-Lagrangian step
    vec2 backwardUV = coords - velocityUV * uDt;
    vec4 backwardSample = texture(uQuantity, clamp(backwardUV, 0.0, 1.0));
    
    // MacCormack correction
    vec4 current = texture(uQuantity, coords);
    vec4 corrected = current + 0.5 * (forwardSample - backwardSample);
    
    // Apply limiter to prevent oscillations
    float minQ = min(min(current, forwardSample), backwardSample);
    float maxQ = max(max(current, forwardSample), backwardSample);
    
    corrected.r = clamp(corrected.r, minQ, maxQ);
    
    // Apply dissipation
    corrected *= (1.0 - uDissipation);
    
    return corrected;
}
```

**Trade-off:** 2x texture lookups for improved accuracy. Use only for flagship devices.

#### BFECC (Back and Forth Error Compensation and Correction)

Even higher accuracy, but significantly more expensive:

```agsl
vec4 main(vec2 coords) {
    vec2 velocity = texture(uVelocity, coords).rg;
    vec2 velocityUV = velocity * uTexelSize;
    
    // Standard semi-Lagrangian
    vec2 pos1 = coords - velocityUV * uDt;
    vec4 q1 = texture(uQuantity, clamp(pos1, 0.0, 1.0));
    
    // Error correction
    vec2 vel2 = texture(uVelocity, clamp(pos1, 0.0, 1.0)).rg * uTexelSize;
    vec2 pos2 = pos1 + vel2 * uDt;
    vec4 q2 = texture(uQuantity, clamp(pos2, 0.0, 1.0));
    
    vec4 error = q2 - q1;
    vec4 current = texture(uQuantity, coords);
    vec4 advected = q1 - 0.5 * error;
    
    // Apply limiter and dissipation
    advected.r = clamp(advected.r, 0.0, 1.0);
    advected *= (1.0 - uDissipation);
    
    return advected;
}
```

**Use Case:** Desktop-quality fluid on high-end devices. Avoid on mobile.

### 4.3 Texture Sampling Optimization

```agsl
// Optimized texture sampling with cache considerations
vec4 sampleQuantity(sampler2D tex, vec2 uv) {
    // Use built-in texture() with LINEAR filtering
    // Mobile GPUs have dedicated texture cache
    return texture(tex, uv);
}

// Manual interpolation (slower, but sometimes necessary)
vec4 manualBilinear(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec2 texCoord = uv / texelSize - 0.5;
    vec2 i = floor(texCoord);
    vec2 f = fract(texCoord);
    
    vec4 a = texture(tex, (i + vec2(0.5, 0.5)) * texelSize);
    vec4 b = texture(tex, (i + vec2(1.5, 0.5)) * texelSize);
    vec4 c = texture(tex, (i + vec2(0.5, 1.5)) * texelSize);
    vec4 d = texture(tex, (i + vec2(1.5, 1.5)) * texelSize);
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
```

**Recommendation:** Always use built-in `texture()` with `GL_LINEAR` filtering for optimal performance on mobile GPUs.

---

## 5. Boundary Condition Handling

### 5.1 Domain Boundaries

The simulation domain has four edges where special conditions apply:

#### No-Slip Velocity Boundary Condition
```
u_wall = -u_neighbor
```

This reflection ensures the average velocity at the boundary is zero.

#### Neumann Pressure Boundary Condition
```
∂p/∂n = 0 → p_wall = p_neighbor
```

Zero pressure gradient normal to the wall.

### 5.2 AGSL Implementation

```agsl
uniform sampler2D uField;
uniform vec2 uTexelSize;
uniform int uBoundaryMode; // 0=interior, 1=top, 2=bottom, 3=left, 4=right

vec4 applyBoundaryConditions(vec2 coords, vec4 value) {
    float isBoundary = 0.0;
    
    // Detect boundary pixels
    if (uBoundaryMode == 1 && coords.y > 1.0 - uTexelSize.y) isBoundary = 1.0;
    if (uBoundaryMode == 2 && coords.y < uTexelSize.y) isBoundary = 1.0;
    if (uBoundaryMode == 3 && coords.x < uTexelSize.x) isBoundary = 1.0;
    if (uBoundaryMode == 4 && coords.x > 1.0 - uTexelSize.x) isBoundary = 1.0;
    
    if (isBoundary > 0.5) {
        // No-slip for velocity: reflect
        if (uBoundaryMode == 1 || uBoundaryMode == 2) {
            value.g = -value.g; // Flip y-velocity
        } else {
            value.r = -value.r; // Flip x-velocity
        }
        
        // Neumann for pressure: copy from neighbor
        if (uBoundaryMode == 1) {
            value.r = texture(uField, coords - vec2(0.0, uTexelSize.y)).r;
        } else if (uBoundaryMode == 2) {
            value.r = texture(uField, coords + vec2(0.0, uTexelSize.y)).r;
        } else if (uBoundaryMode == 3) {
            value.r = texture(uField, coords + vec2(uTexelSize.x, 0.0)).r;
        } else {
            value.r = texture(uField, coords - vec2(uTexelSize.x, 0.0)).r;
        }
    }
    
    return value;
}

vec4 main(vec2 coords) {
    vec4 value = texture(uField, coords);
    return applyBoundaryConditions(coords, value);
}
```

### 5.3 Arbitrary Boundaries (Obstacles)

For complex boundaries within the simulation domain:

#### Binary Mask Approach
```agsl
uniform sampler2D uField;
uniform sampler2D uObstacleMask; // 1.0 = obstacle, 0.0 = fluid
uniform vec2 uTexelSize;

vec4 handleArbitraryBoundaries(vec2 coords) {
    float isObstacle = texture(uObstacleMask, coords).r;
    
    if (isObstacle > 0.5) {
        // Inside obstacle: enforce zero velocity
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    
    vec4 value = texture(uField, coords);
    
    // Check neighbors for boundary conditions
    vec4 neighborL = texture(uField, coords + vec2(-uTexelSize.x, 0.0));
    vec4 neighborR = texture(uField, coords + vec2(uTexelSize.x, 0.0));
    vec4 neighborB = texture(uField, coords + vec2(0.0, -uTexelSize.y));
    vec4 neighborT = texture(uField, coords + vec2(0.0, uTexelSize.y));
    
    float obsL = texture(uObstacleMask, coords + vec2(-uTexelSize.x, 0.0)).r;
    float obsR = texture(uObstacleMask, coords + vec2(uTexelSize.x, 0.0)).r;
    float obsB = texture(uObstacleMask, coords + vec2(0.0, -uTexelSize.y)).r;
    float obsT = texture(uObstacleMask, coords + vec2(0.0, uTexelSize.y)).r;
    
    // Reflect velocity at obstacle boundaries
    if (obsL > 0.5) value.r = -value.r;
    if (obsR > 0.5) value.r = -value.r;
    if (obsB > 0.5) value.g = -value.g;
    if (obsT > 0.5) value.g = -value.g;
    
    return value;
}

vec4 main(vec2 coords) {
    return handleArbitraryBoundaries(coords);
}
```

### 5.4 Performance Considerations

For mobile performance, consider these optimizations:

1. **Pre-computed boundaries:** Generate boundary conditions once and store in a texture
2. **Reduced resolution:** Handle boundaries at lower resolution than the main simulation
3. **Simplified obstacles:** Use rectangular obstacles instead of arbitrary shapes
4. **Boundary batch processing:** Process all boundary pixels in a single shader pass

---

## 6. Performance Optimization Techniques

### 6.1 Mobile GPU Architecture Considerations

#### Tile-Based Deferred Rendering (TBDR)

Most mobile GPUs use TBDR architecture, which has specific optimization requirements:

**Advantages:**
- Hidden surface removal eliminates overdraw
- On-chip tile memory reduces bandwidth
- Efficient blending operations

**Optimizations:**
- Minimize render target switching
- Avoid complex branching within shaders
- Use texture formats that match tile memory layout

#### Memory Bandwidth Bottleneck

Mobile GPUs are severely bandwidth-limited:

```
Theoretical Bandwidth Calculation:
- Mid-range mobile: ~25 GB/s
- Flagship mobile: ~50 GB/s
- Desktop GPU: ~500+ GB/s
```

**Strategies:**
- Reduce texture resolution
- Use half-float textures instead of full float
- Minimize texture fetches per fragment
- Cache frequently accessed data

### 6.2 Texture Format Optimization

#### Half-Float Textures (Recommended)

```kotlin
val textureFormat = ImageInfo.ColorType.RGBA_F16
val colorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
```

**Benefits:**
- 16-bit precision (vs 32-bit full float)
- 2x memory reduction
- Sufficient accuracy for visual fluid simulation
- Better cache utilization

**Trade-offs:**
- Reduced numerical accuracy
- Potential precision issues with very small/large values
- May cause minor visual artifacts

#### Integer Texture with Remapping (Alternative)

If half-float not supported:

```agsl
// Remap [-0.5, 0.5] to [0, 1] for storage
vec4 packVelocity(vec2 velocity) {
    return vec4(velocity + 0.5, 0.0, 1.0);
}

// Unmap [0, 1] to [-0.5, 0.5] for computation
vec2 unpackVelocity(vec4 packed) {
    return packed.rg - 0.5;
}
```

**Benefits:**
- Works on all devices
- Lower memory bandwidth

**Trade-offs:**
- Extra arithmetic in shaders
- Reduced dynamic range
- More complex implementation

### 6.3 Shader Optimization

#### Reduce Texture Fetches

```agsl
// BAD: Multiple texture fetches for same data
vec4 main(vec2 coords) {
    vec4 a = texture(uTexture, coords);
    vec4 b = texture(uTexture, coords); // Duplicate fetch!
    return a + b;
}

// GOOD: Single fetch, reuse result
vec4 main(vec2 coords) {
    vec4 data = texture(uTexture, coords);
    return data + data;
}
```

#### Avoid Complex Branching

```agsl
// BAD: Dynamic branching causes divergence
vec4 main(vec2 coords) {
    float value = texture(uTexture, coords).r;
    if (value > 0.5) {
        return vec4(1.0, 0.0, 0.0, 1.0);
    } else {
        return vec4(0.0, 0.0, 1.0, 1.0);
    }
}

// GOOD: Use mix() for conditional selection
vec4 main(vec2 coords) {
    float value = texture(uTexture, coords).r;
    vec4 red = vec4(1.0, 0.0, 0.0, 1.0);
    vec4 blue = vec4(0.0, 0.0, 1.0, 1.0);
    return mix(blue, red, step(0.5, value));
}
```

#### Use Built-in Functions

```agsl
// BAD: Manual square root approximation
float manualSqrt(float x) {
    return x * 0.5; // Terrible approximation!
}

// GOOD: Use built-in sqrt()
float goodSqrt(float x) {
    return sqrt(x);
}
```

### 6.4 Framebuffer Object (FBO) Optimization

```kotlin
data class FluidFBOs(
    // Double-buffered ping-pong setup
    val velocityRead: ImageBitmap,
    val velocityWrite: ImageBitmap,
    val dyeRead: ImageBitmap,
    val dyeWrite: ImageBitmap,
    val pressure: ImageBitmap,
    val divergence: ImageBitmap
)

class FluidSimulation(private val resolution: Int) {
    private val fbos = createFBOs(resolution)
    
    fun swapPingPong() {
        // Efficient swap using object references
        val tempVelocity = fbos.velocityRead
        fbos.velocityRead = fbos.velocityWrite
        fbos.velocityWrite = tempVelocity
        
        val tempDye = fbos.dyeRead
        fbos.dyeRead = fbos.dyeWrite
        fbos.dyeWrite = tempDye
    }
}
```

### 6.5 Iteration Budgeting

Adaptive quality based on device capabilities:

```kotlin
enum class QualityLevel(val iterations: Int) {
    LOW(10),      // Budget devices, 30 FPS
    MEDIUM(20),   // Mid-range devices, 60 FPS
    HIGH(30),     // Flagship devices, 60 FPS
    ULTRA(40)     // High-end flagships, 60 FPS with visual effects
}

class PerformanceManager(private val context: Context) {
    fun determineQuality(): QualityLevel {
        val gl = (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
            .deviceConfigurationInfo.glEsVersion
        
        return when {
            gl >= 0x30000 -> QualityLevel.HIGH
            gl >= 0x20000 -> QualityLevel.MEDIUM
            else -> QualityLevel.LOW
        }
    }
}
```

### 6.6 Resolution Scaling

Dynamic resolution adjustment based on performance:

```kotlin
class AdaptiveResolution(
    private val minResolution: Int = 64,
    private val maxResolution: Int = 256,
    private val targetFPS: Float = 60f
) {
    private var currentResolution = maxResolution
    private var frameTimeBuffer = mutableListOf<Float>()
    
    fun updateResolution(measuredFPS: Float): Int {
        frameTimeBuffer.add(1000f / measuredFPS)
        if (frameTimeBuffer.size > 30) frameTimeBuffer.removeAt(0)
        
        val avgFPS = 1000f / frameTimeBuffer.average()
        
        currentResolution = when {
            avgFPS < targetFPS * 0.8f -> max(minResolution, currentResolution - 16)
            avgFPS > targetFPS * 1.2f -> min(maxResolution, currentResolution + 16)
            else -> currentResolution
        }
        
        return currentResolution
    }
}
```

---

## 7. Memory-Efficient Data Structures

### 7.1 Structure of Arrays (SoA) vs Array of Structures (AoS)

#### Array of Structures (AoS) - Not Recommended
```
struct Cell {
    vec2 velocity;
    float density;
    float pressure;
};

Cell grid[128][128]; // Poor cache locality
```

#### Structure of Arrays (SoA) - Recommended
```kotlin
data class FluidGrid(
    val velocityTexture: ImageBitmap,    // RG channels: velocity
    val densityTexture: ImageBitmap,     // R channel: density
    val pressureTexture: ImageBitmap,    // R channel: pressure
    val divergenceTexture: ImageBitmap   // R channel: divergence
)
```

**Benefits:**
- Better cache locality
- Enables selective updates
- More flexible data access patterns
- Reduces memory bandwidth

### 7.2 Texture Channel Packing

Pack multiple quantities into single texture:

```agsl
// R: Density, G: Velocity X, B: Velocity Y, A: Pressure
uniform sampler2D uPackedTexture;

vec4 main(vec2 coords) {
    vec4 data = texture(uPackedTexture, coords);
    
    float density = data.r;
    vec2 velocity = data.gb;
    float pressure = data.a;
    
    // Process...
    
    // Pack back
    return vec4(density, velocity, pressure);
}
```

**Benefits:**
- Reduces texture count
- Improves cache coherence
- Simpler render passes

**Trade-offs:**
- Less flexible access patterns
- Potential precision loss
- More complex shader code

### 7.3 Memory Layout Considerations

#### Texture Wrap Mode

```agsl
// Set texture parameters for optimal access
// (Handled in Android code)
textureSampler.setWrapMode(TextureWrapMode.CLAMP_TO_EDGE)
```

**Rationale:** Prevents boundary wrapping artifacts and ensures consistent behavior at edges.

#### Mipmapping

```agsl
// Disable mipmapping for simulation textures
// (Handled in Android code)
textureSampler.setMinMagFilter(FilterMode.NEAREST)
```

**Rationale:** Simulation textures don't benefit from mipmapping and mipmaps waste memory.

### 7.4 Ping-Pong Buffer Management

```kotlin
class PingPongBuffer<T : Any>(private val create: () -> T) {
    private val buffers = Array(2) { create() }
    private var readIndex = 0
    private var writeIndex = 1
    
    val read: T get() = buffers[readIndex]
    val write: T get() = buffers[writeIndex]
    
    fun swap() {
        readIndex = (readIndex + 1) % 2
        writeIndex = (writeIndex + 1) % 2
    }
    
    fun resize(newSize: Int) {
        buffers[0] = create()
        buffers[1] = create()
    }
}
```

### 7.5 Memory Budgeting

```kotlin
data class MemoryBudget(
    val totalGPUMemoryMB: Float,
    val physicsResolution: Int,
    val visualResolution: Int
) {
    val physicsMemoryMB: Float
        get() = physicsResolution * physicsResolution * 4 * 4 / (1024f * 1024f) // 4 channels, 4 bytes
    
    val visualMemoryMB: Float
        get() = visualResolution * visualResolution * 4 * 4 / (1024f * 1024f)
    
    val totalEstimatedMB: Float
        get() = physicsMemoryMB + visualMemoryMB
    
    val fitsInBudget: Boolean
        get() = totalEstimatedMB < totalGPUMemoryMB * 0.8f // Use 80% of available
}

class MemoryManager(private val context: Context) {
    fun getGPUMemoryBudget(): MemoryBudget {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        
        // Estimate 25% of total RAM for GPU
        val gpuMemoryMB = (memInfo.totalMem * 0.25) / (1024f * 1024f)
        
        return MemoryBudget(
            totalGPUMemoryMB = gpuMemoryMB,
            physicsResolution = 128,
            visualResolution = 512
        )
    }
}
```

---

## 8. AGSL-Specific Considerations and Limitations

### 8.1 AGSL Language Features

AGSL is based on SkSL (Skia Shading Language) and is **nearly identical to GLSL ES 1.0**, with some key differences:

#### Similarities with GLSL ES 1.0
- Basic vector types: `vec2`, `vec3`, `vec4`
- Matrix types: `mat2`, `mat3`, `mat4`
- Built-in functions: `texture()`, `mix()`, `clamp()`, etc.
- Uniform variables for constants
- Fragment shader main() function

#### Key Differences

**No compute shaders:** AGSL only supports fragment shaders
```agsl
// ✅ AGSL: Fragment shader
uniform shader input;
vec4 main(vec2 coords) {
    return input.eval(coords);
}

// ❌ NOT SUPPORTED: Compute shader
// layout(local_size_x = 1) in;
// void main() { ... }
```

**Input/output via uniform sampler:**
```agsl
// AGSL-specific syntax
uniform shader inputShader;  // SkSL-style uniform shader
vec4 main(vec2 coords) {
    return inputShader.eval(coords);  // eval() instead of texture()
}
```

### 8.2 RuntimeShader Integration

```kotlin
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
class FluidEffectView(context: Context) : View(context) {
    private val fluidShader = RuntimeShader("""
        uniform shader input;
        uniform float2 uResolution;
        uniform float uTime;
        
        vec4 main(vec2 coords) {
            // Fluid simulation code here
            vec2 uv = coords / uResolution;
            
            // Sample input
            vec4 color = input.eval(coords);
            
            // Apply fluid effect
            // ...
            
            return color;
        }
    """)
    
    init {
        // Set uniforms
        fluidShader.setFloatUniform("uTime", 0f)
        
        // Create render effect
        val effect = RenderEffect.createRuntimeShaderEffect(
            fluidShader, "input"
        )
        setRenderEffect(effect)
    }
    
    override fun onDraw(canvas: Canvas) {
        // Update time
        fluidShader.setFloatUniform("uTime", System.currentTimeMillis() / 1000f)
        
        // Draw content
        super.onDraw(canvas)
    }
}
```

### 8.3 Android Compose Integration

```kotlin
@Composable
fun FluidEffect(modifier: Modifier = Modifier) {
    val shader = remember {
        RuntimeShader("""
            uniform shader content;
            uniform float2 uResolution;
            uniform float uTime;
            
            vec4 main(vec2 coords) {
                vec2 uv = coords / uResolution;
                
                // Create procedural fluid
                vec2 velocity = vec2(
                    sin(uv.y * 10.0 + uTime),
                    cos(uv.x * 10.0 + uTime)
                ) * 0.01;
                
                // Advect
                vec2 sourceUV = coords - velocity * 100.0;
                vec4 color = content.eval(clamp(sourceUV, 0.0, 1.0));
                
                return color;
            }
        """)
    }
    
    val density = LocalDensity.current
    val size = with(density) { DpSize(400.dp, 400.dp).toSize() }
    
    shader.setFloatUniform("uResolution", size.width, size.height)
    
    Box(
        modifier = modifier
            .size(400.dp)
            .graphicsLayer {
                renderEffect = RenderEffect.createRuntimeShaderEffect(
                    shader, "content"
                )
            }
            .drawWithContent {
                drawContent() // This becomes the 'content' uniform
            }
    )
}
```

### 8.4 Limitations and Workarounds

#### No Compute Shaders

**Problem:** AGSL doesn't support compute shaders, which are ideal for fluid simulation.

**Workaround:** Use fragment shaders with ping-pong buffers:

```kotlin
class FragmentShaderSimulation(
    private val context: Context,
    private val resolution: Int
) {
    private val shaders = mapOf(
        "advect" to createShader("advect.agsl"),
        "diffuse" to createShader("diffuse.agsl"),
        "project" to createShader("project.agsl"),
        "divergence" to createShader("divergence.agsl"),
        "gradient" to createShader("gradient.agsl")
    )
    
    private val fbos = createPingPongFBOs(resolution)
    private val renderer = FragmentShaderRenderer(context)
    
    fun simulate() {
        // Advect velocity
        renderer.render(shaders["advect"]!!, fbos.velocityRead, fbos.velocityWrite)
        fbos.swapVelocity()
        
        // Advect dye
        renderer.render(shaders["advect"]!!, fbos.dyeRead, fbos.dyeWrite)
        fbos.swapDye()
        
        // Compute divergence
        renderer.render(shaders["divergence"]!!, fbos.velocityRead, fbos.divergence)
        
        // Solve pressure
        repeat(20) {
            renderer.render(shaders["project"]!!, fbos.pressure, fbos.divergence)
        }
        
        // Subtract gradient
        renderer.render(shaders["gradient"]!!, fbos.velocityRead, fbos.pressure)
        renderer.render(shaders["gradient"]!!, fbos.velocityWrite, fbos.pressure)
        fbos.swapVelocity()
    }
}
```

#### Limited Texture Format Support

**Problem:** Not all texture formats are supported on all devices.

**Workaround:** Capability detection and fallback:

```kotlin
class TextureFormatManager(private val context: Context) {
    fun getBestTextureFormat(): ImageInfo {
        val egl = EGL14.eglGetCurrentContext()
        
        // Try half-float first
        if (supportsHalfFloat()) {
            return ImageInfo(
                width = 512, height = 512,
                colorType = ImageInfo.ColorType.RGBA_F16,
                alphaType = ImageInfo.AlphaType.PREMUL
            )
        }
        
        // Fall back to integer with remapping
        return ImageInfo(
            width = 512, height = 512,
            colorType = ImageInfo.ColorType.RGB_8888,
            alphaType = ImageInfo.AlphaType.OPAQUE
        )
    }
    
    private fun supportsHalfFloat(): Boolean {
        // Check device capabilities
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.deviceConfigurationInfo.reqGlEsVersion >= 0x30000
    }
}
```

#### Performance Variability

**Problem:** AGSL performance varies significantly across devices.

**Workaround:** Adaptive quality and feature detection:

```kotlin
class AdaptiveFluidSimulation(
    private val context: Context
) {
    private val deviceProfile = detectDeviceProfile()
    
    fun getSimulationConfig(): SimulationConfig {
        return when (deviceProfile.tier) {
            DeviceTier.FLAGSHIP -> SimulationConfig(
                resolution = 256,
                iterations = 40,
                enableVorticity = true,
                enableBloom = true
            )
            DeviceTier.MID_RANGE -> SimulationConfig(
                resolution = 128,
                iterations = 20,
                enableVorticity = false,
                enableBloom = false
            )
            DeviceTier.BUDGET -> SimulationConfig(
                resolution = 64,
                iterations = 10,
                enableVorticity = false,
                enableBloom = false
            )
        }
    }
    
    private fun detectDeviceProfile(): DeviceProfile {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(memInfo)
        
        val glVersion = manager.deviceConfigurationInfo.reqGlEsVersion
        val ramMB = memInfo.totalMem / (1024 * 1024)
        
        return DeviceProfile(
            tier = when {
                ramMB > 6000 && glVersion >= 0x30000 -> DeviceTier.FLAGSHIP
                ramMB > 3000 && glVersion >= 0x20000 -> DeviceTier.MID_RANGE
                else -> DeviceTier.BUDGET
            },
            ramMB = ramMB,
            glVersion = glVersion
        )
    }
}
```

### 8.5 Debugging and Profiling

```kotlin
class FluidProfiler {
    private val timings = mutableMapOf<String, MutableList<Long>>()
    
    fun startTimer(name: String): Long {
        return System.nanoTime()
    }
    
    fun endTimer(name: String, startTime: Long) {
        val elapsed = System.nanoTime() - startTime
        timings.getOrPut(name) { mutableListOf() }.add(elapsed)
    }
    
    fun getAverageTime(name: String): Float {
        val times = timings[name] ?: return 0f
        return if (times.isNotEmpty()) {
            times.average().toFloat() / 1_000_000f // Convert to ms
        } else 0f
    }
    
    fun report() {
        timings.forEach { (name, times) ->
            val avg = getAverageTime(name)
            val max = times.maxOrNull()?.let { it / 1_000_000f } ?: 0f
            val min = times.minOrNull()?.let { it / 1_000_000f } ?: 0f
            
            Log.d("FluidProfiler", "$name: avg=${avg}ms, min=${min}ms, max=${max}ms, n=${times.size}")
        }
    }
}
```

---

## 9. Integration Patterns with Compose Graphics

### 9.1 Basic RuntimeShader Integration

```kotlin
@Composable
fun FluidSimulationView(
    modifier: Modifier = Modifier,
    simulation: FluidSimulation = rememberFluidSimulation()
) {
    val shader = remember(simulation.shaderCode) {
        RuntimeShader(simulation.shaderCode)
    }
    
    val density = LocalDensity.current
    val size = with(density) { DpSize(400.dp, 400.dp).toSize() }
    
    // Update shader uniforms
    LaunchedEffect(simulation) {
        while (true) {
            simulation.update()
            shader.setFloatUniform("uTime", System.currentTimeMillis() / 1000f)
            delay(16) // ~60 FPS
        }
    }
    
    Box(
        modifier = modifier
            .size(400.dp)
            .graphicsLayer {
                renderEffect = RenderEffect.createRuntimeShaderEffect(
                    shader, "input"
                )
            }
            .drawWithContent {
                // Draw simulation textures to canvas
                simulation.renderToCanvas(drawContext.canvas)
            }
    )
}
```

### 9.2 Interactive Fluid with User Input

```kotlin
@Composable
fun InteractiveFluid(
    modifier: Modifier = Modifier,
    onFluidInteraction: (x: Float, y: Float, dx: Float, dy: Float) -> Unit = { _, _, _, _ -> }
) {
    val simulation = rememberFluidSimulation()
    var pointerPosition by remember { mutableStateOf(Offset.Zero) }
    var previousPosition by remember { mutableStateOf(Offset.Zero) }
    
    val density = LocalDensity.current
    
    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    val size = size
                    val x = change.position.x / size.width
                    val y = change.position.y / size.height
                    
                    val dx = dragAmount.x / size.width
                    val dy = dragAmount.y / size.height
                    
                    // Inject user input into simulation
                    simulation.addForce(x, y, dx * 10f, dy * 10f)
                    simulation.addDye(x, y, 1.0f)
                    
                    change.consume()
                }
            }
            .graphicsLayer {
                renderEffect = simulation.renderEffect
            }
            .drawWithContent {
                simulation.render(this)
            }
    )
}
```

### 9.3 Multi-Pass Rendering Pipeline

```kotlin
@Composable
fun MultiPassFluidEffect(
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val simulation = remember { FluidSimulation(context) }
    
    // Define render passes
    val passes = remember {
        listOf(
            RenderPass("advect", simulation.advectShader),
            RenderPass("diffuse", simulation.diffuseShader),
            RenderPass("project", simulation.projectShader),
            RenderPass("display", simulation.displayShader)
        )
    }
    
    LaunchedEffect(Unit) {
        while (true) {
            // Execute all passes
            passes.forEach { pass ->
                simulation.executePass(pass)
            }
            
            delay(16)
        }
    }
    
    Box(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer {
                // Apply final display shader
                renderEffect = RenderEffect.createRuntimeShaderEffect(
                    simulation.displayShader, "input"
                )
            }
    )
}
```

### 9.4 Texture Management in Compose

```kotlin
@Composable
fun FluidTextureManager(
    resolution: Int = 128,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    
    // Create textures on first composition
    val textures = remember(resolution) {
        FluidTextures(context, resolution)
    }
    
    // Cleanup on disposal
    DisposableEffect(textures) {
        onDispose {
            textures.release()
        }
    }
    
    // Animation loop
    val coroutineScope = rememberCoroutineScope()
    
    LaunchedEffect(Unit) {
        while (true) {
            // Update simulation
            updateSimulation(textures)
            
            // Invalidate for redraw
            coroutineScope.launch {
                // Trigger recomposition
            }
            
            delay(16)
        }
    }
    
    // Render
    Canvas(
        modifier = modifier.fillMaxSize()
    ) {
        // Draw from textures
        drawImage(textures.outputImage)
    }
}

class FluidTextures(private val context: Context, resolution: Int) {
    val velocityTexture = createTexture(resolution, ColorType.RGBA_F16)
    val pressureTexture = createTexture(resolution, ColorType.RGBA_F16)
    val dyeTexture = createTexture(resolution, ColorType.RGBA_F16)
    val outputImage = ImageBitmap(resolution, resolution)
    
    private fun createTexture(resolution: Int, colorType: ColorType): ImageBitmap {
        return ImageBitmap(
            width = resolution,
            height = resolution,
            config = ImageBitmapConfig(
                colorType = colorType,
                alphaType = AlphaType.PREMUL
            )
        )
    }
    
    fun release() {
        // Cleanup native resources
    }
}
```

### 9.5 State Management and Persistence

```kotlin
@Composable
fun rememberFluidSimulation(): FluidSimulation {
    val context = LocalContext.current
    return remember { FluidSimulation(context) }
}

class FluidSimulationState(
    var isRunning: Boolean = true,
    var quality: QualityLevel = QualityLevel.MEDIUM,
    var showVelocity: Boolean = false,
    var showPressure: Boolean = false
)

@Composable
fun FluidSimulationControlPanel(
    state: FluidSimulationState,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Play/Pause
        Button(
            onClick = { state.isRunning = !state.isRunning }
        ) {
            Text(if (state.isRunning) "Pause" else "Play")
        }
        
        // Quality selector
        Text("Quality:")
        Row {
            QualityLevel.values().forEach { quality ->
                FilterChip(
                    selected = state.quality == quality,
                    onClick = { state.quality = quality },
                    label = { Text(quality.name) }
                )
            }
        }
        
        // Visualization toggles
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(
                checked = state.showVelocity,
                onCheckedChange = { state.showVelocity = it }
            )
            Text("Show Velocity")
        }
        
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(
                checked = state.showPressure,
                onCheckedChange = { state.showPressure = it }
            )
            Text("Show Pressure")
        }
    }
}
```

---

## 10. Quality vs Performance Trade-offs

### 10.1 Resolution Impact

```
Memory Usage vs Resolution:
64×64:    16 KB per texture
128×128:  64 KB per texture
256×256:  256 KB per texture
512×512:  1 MB per texture
1024×1024: 4 MB per texture

Performance vs Resolution:
64×64:    ~1ms per pass
128×128:  ~4ms per pass
256×256:  ~16ms per pass
512×512:  ~64ms per pass
1024×1024: ~256ms per pass
```

### 10.2 Iteration Count Impact

```
Pressure Solver Accuracy vs Iterations:
5 iterations:  ~60% accuracy, very fast
10 iterations: ~80% accuracy, fast
20 iterations: ~90% accuracy, balanced
30 iterations: ~95% accuracy, slower
40 iterations: ~98% accuracy, very slow

Performance Impact (128×128 grid):
5 iterations:  ~2ms
10 iterations: ~4ms
20 iterations: ~8ms
30 iterations: ~12ms
40 iterations: ~16ms
```

### 10.3 Feature Toggle Matrix

| Feature | Performance Cost | Visual Impact | Recommendation |
|---------|------------------|---------------|----------------|
| Vorticity Confinement | +30% | +High detail | Flagship only |
| MacCormack Advection | +50% | +Sharpness | Mid-range+ |
| BFECC Advection | +100% | ++Sharpness | Flagship only |
| Bloom Effect | +40% | +Atmosphere | Optional |
| Caustics | +60% | +Realism | Desktop only |
| Reflection | +80% | +Depth | Desktop only |
| Diffusion | +20% | +Smoothness | Low quality only |

### 10.4 Adaptive Quality Presets

```kotlin
data class QualityPreset(
    val name: String,
    val physicsResolution: Int,
    val visualResolution: Int,
    val pressureIterations: Int,
    val advectionMethod: AdvectionMethod,
    val enableVorticity: Boolean,
    val enableBloom: Boolean,
    val targetFPS: Int
)

enum class AdvectionMethod {
    SEMI_LAGRANGIAN,    // Basic, fast
    MACCORMACK,         // Better, slower
    BFECC              // Best, very slow
}

val PRESETS = listOf(
    QualityPreset(
        name = "Budget",
        physicsResolution = 64,
        visualResolution = 256,
        pressureIterations = 10,
        advectionMethod = AdvectionMethod.SEMI_LAGRANGIAN,
        enableVorticity = false,
        enableBloom = false,
        targetFPS = 30
    ),
    QualityPreset(
        name = "Balanced",
        physicsResolution = 128,
        visualResolution = 512,
        pressureIterations = 20,
        advectionMethod = AdvectionMethod.SEMI_LAGRANGIAN,
        enableVorticity = false,
        enableBloom = false,
        targetFPS = 60
    ),
    QualityPreset(
        name = "High Quality",
        physicsResolution = 256,
        visualResolution = 1024,
        pressureIterations = 30,
        advectionMethod = AdvectionMethod.MACCORMACK,
        enableVorticity = true,
        enableBloom = true,
        targetFPS = 60
    ),
    QualityPreset(
        name = "Ultra",
        physicsResolution = 512,
        visualResolution = 2048,
        pressureIterations = 40,
        advectionMethod = AdvectionMethod.BFECC,
        enableVorticity = true,
        enableBloom = true,
        targetFPS = 60
    )
)
```

### 10.5 Performance Monitoring

```kotlin
class FluidPerformanceMonitor {
    private val frameTimes = mutableListOf<Long>()
    private val passTimings = mutableMapOf<String, MutableList<Long>>()
    
    fun startFrame() {
        frameTimeStart = System.nanoTime()
    }
    
    fun endFrame() {
        val frameTime = System.nanoTime() - frameTimeStart
        frameTimes.add(frameTime)
        if (frameTimes.size > 60) frameTimes.removeAt(0)
    }
    
    fun startPass(name: String) {
        passTimings.getOrPut(name) { mutableListOf() }
            .add(System.nanoTime())
    }
    
    fun endPass(name: String) {
        val timings = passTimings[name] ?: return
        val startTime = timings.removeAt(timings.size - 1)
        timings.add(System.nanoTime() - startTime)
    }
    
    fun getReport(): PerformanceReport {
        val avgFrameTime = frameTimes.average()
        val avgFPS = 1_000_000_000.0 / avgFrameTime
        
        val passBreakdown = passTimings.mapValues { (_, timings) ->
            PerformancePass(
                name = it.key,
                avgTimeMs = timings.average() / 1_000_000.0,
                maxTimeMs = timings.maxOrNull()?.let { it / 1_000_000.0 } ?: 0.0,
                minTimeMs = timings.minOrNull()?.let { it / 1_000_000.0 } ?: 0.0
            )
        }
        
        return PerformanceReport(
            avgFPS = avgFPS,
            avgFrameTimeMs = avgFrameTime / 1_000_000.0,
            passBreakdown = passBreakdown,
            droppedFrames = frameTimes.count { it > 33_333_333L } // >30ms
        )
    }
}

data class PerformanceReport(
    val avgFPS: Double,
    val avgFrameTimeMs: Double,
    val passBreakdown: Map<String, PerformancePass>,
    val droppedFrames: Int
)

data class PerformancePass(
    val name: String,
    val avgTimeMs: Double,
    val maxTimeMs: Double,
    val minTimeMs: Double
)
```

### 10.6 Automatic Quality Adjustment

```kotlin
class AdaptiveQualityController(
    private val targetFPS: Float = 60f,
    private val minFPS: Float = 30f
) {
    private var currentPresetIndex = 1
    private val performanceBuffer = mutableListOf<Float>()
    
    fun update(measuredFPS: Float): QualityPreset {
        performanceBuffer.add(measuredFPS)
        if (performanceBuffer.size > 30) performanceBuffer.removeAt(0)
        
        val avgFPS = performanceBuffer.average()
        
        currentPresetIndex = when {
            avgFPS < minFPS -> max(0, currentPresetIndex - 1)
            avgFPS > targetFPS * 1.1f -> min(PRESETS.size - 1, currentPresetIndex + 1)
            else -> currentPresetIndex
        }
        
        return PRESETS[currentPresetIndex]
    }
}
```

---

## 11. Implementation Recommendations

### 11.1 Recommended Setup

```kotlin
class FluidSimulation(
    private val context: Context,
    private val preset: QualityPreset = PRESETS[1]
) {
    // Physics resolution
    private val physicsResolution = preset.physicsResolution
    
    // Visual resolution
    private val visualResolution = preset.visualResolution
    
    // Create textures
    private val velocityTexture = createTexture(physicsResolution, ColorType.RGBA_F16)
    private val pressureTexture = createTexture(physicsResolution, ColorType.RGBA_F16)
    private val divergenceTexture = createTexture(physicsResolution, ColorType.RGBA_F16)
    private val dyeTexture = createTexture(visualResolution, ColorType.RGBA_F16)
    
    // Create shaders
    private val advectShader = createAdvectShader()
    private val projectShader = createProjectShader()
    private val divergenceShader = createDivergenceShader()
    private val gradientShader = createGradientShader()
    private val displayShader = createDisplayShader()
    
    // Performance monitoring
    private val profiler = FluidPerformanceMonitor()
    
    fun update() {
        profiler.startFrame()
        
        // 1. Advect velocity
        profiler.startPass("advect_velocity")
        executeShader(advectShader, velocityTexture, velocityTexture)
        profiler.endPass("advect_velocity")
        
        // 2. Advect dye
        profiler.startPass("advect_dye")
        executeShader(advectShader, dyeTexture, velocityTexture)
        profiler.endPass("advect_dye")
        
        // 3. Compute divergence
        profiler.startPass("divergence")
        executeShader(divergenceShader, divergenceTexture, velocityTexture)
        profiler.endPass("divergence")
        
        // 4. Solve pressure
        profiler.startPass("pressure_solve")
        repeat(preset.pressureIterations) {
            executeShader(projectShader, pressureTexture, divergenceTexture)
        }
        profiler.endPass("pressure_solve")
        
        // 5. Subtract gradient
        profiler.startPass("gradient")
        executeShader(gradientShader, velocityTexture, pressureTexture)
        profiler.endPass("gradient")
        
        profiler.endFrame()
    }
    
    fun getPerformanceReport(): PerformanceReport {
        return profiler.getReport()
    }
}
```

### 11.2 Best Practices

1. **Always use half-float textures** when available for better memory efficiency
2. **Implement adaptive quality** to maintain consistent frame rates
3. **Profile extensively** on target devices before shipping
4. **Cache shader compilation** results to avoid runtime compilation
5. **Use texture atlases** to reduce draw calls
6. **Minimize state changes** between render passes
7. **Batch uniform updates** to reduce driver overhead
8. **Pre-allocate memory** to avoid runtime allocations
9. **Use object pools** for frequently created objects
10. **Implement fallbacks** for devices with limited capabilities

### 11.3 Common Pitfalls

1. **Using full-float textures** when half-float is sufficient
2. **Too many pressure iterations** causing performance issues
3. **Not handling boundary conditions** leading to artifacts
4. **Incorrect texture sampling** causing visual glitches
5. **Memory leaks** from unreleased textures
6. **Synchronization issues** between CPU and GPU
7. **Not scaling resolution** based on device capabilities
8. **Over-optimizing** too early in development
9. **Ignoring thermal throttling** on mobile devices
10. **Not testing on actual devices** (emulators don't reflect real performance)

### 11.4 Testing Recommendations

```kotlin
class FluidSimulationTest {
    @Test
    fun testBasicSimulation() {
        val simulation = FluidSimulation(context)
        
        // Run for several frames
        repeat(100) {
            simulation.update()
        }
        
        // Verify simulation is stable
        val report = simulation.getPerformanceReport()
        assertTrue(report.avgFPS > 20f)
        assertEquals(0, report.droppedFrames)
    }
    
    @Test
    fun testBoundaryConditions() {
        val simulation = FluidSimulation(context)
        
        // Add force at boundary
        simulation.addForce(0.5f, 0.0f, 0.1f, 0.0f)
        
        // Update and verify boundary handling
        simulation.update()
        
        // Velocity at boundary should be reflected
        val boundaryVelocity = simulation.getVelocity(0.5f, 0.01f)
        assertEquals(0.0f, boundaryVelocity.y, 0.001f)
    }
    
    @Test
    fun testMemoryUsage() {
        val initialMemory = getMemoryUsage()
        
        val simulation = FluidSimulation(context)
        repeat(1000) { simulation.update() }
        
        val finalMemory = getMemoryUsage()
        
        // Memory should not grow significantly
        assertTrue(finalMemory - initialMemory < 10_000_000) // 10MB
    }
}
```

---

## 12. References and Further Reading

### Academic Papers

1. **Stam, Jos. "Stable Fluids."** SIGGRAPH 1999.
   - Seminal paper introducing stable fluid simulation
   - Foundation for most real-time implementations

2. **Harris, Mark J. "Fast Fluid Dynamics Simulation on the GPU."** GPU Gems Chapter 38, 2004.
   - First comprehensive GPU implementation guide
   - Still relevant for mobile optimization

3. **Bridson, Robert. "Fluid Simulation for Computer Graphics."** A K Peters/CRC Press, 2008.
   - Comprehensive textbook on fluid simulation
   - Covers both theory and implementation

4. **Fedkiw, Ronald, et al. "Visual Simulation of Smoke."** SIGGRAPH 2001.
   - Focus on visual effects and smoke simulation
   - Introduces vorticity confinement

### Online Resources

1. **shahriyarshahrabi.medium.com** - Gentle introduction to fluid simulation
   - Excellent practical implementation guide
   - GPU-focused with code examples

2. **marvyn.com/blog/fluid-simulation.html** - Understanding Fluid Simulation
   - Clear mathematical explanations
   - GPU implementation details

3. **ostefani.dev/tech-notes/webgl-fluid-advection** - WebGL Fluid Simulation series
   - Modern GPU implementation techniques
   - Advection and pressure solving focus

4. **shaders.skia.org** - SkSL/AGSL shader examples
   - Official Skia shader playground
   - AGSL syntax reference and examples

### Android-Specific

1. **Android Developers Documentation - AGSL Overview**
   - Official AGSL documentation
   - RuntimeShader API reference

2. **Chet Haase - "AGSL: Made in the Shade(r)"**
   - Introduction to AGSL and RuntimeShader
   - Practical Android examples

3. **Skia Documentation - SkSL**
   - SkSL language reference
   - AGSL is based on SkSL

### Mobile Optimization

1. **Arm Mali GPU Optimization Guide**
   - Mobile GPU architecture insights
   - Performance optimization techniques

2. **Qualcomm Adreno GPU Optimization**
   - Adreno-specific optimizations
   - Texture format recommendations

3. **Android Performance Patterns**
   - General Android performance guidelines
   - Memory and battery optimization

---

## Conclusion

Real-time fluid simulation on mobile devices using AGSL is achievable with careful optimization and proper understanding of both the physics and the platform constraints. The semi-Lagrangian method combined with implicit pressure projection provides a stable foundation that can be scaled from budget devices to flagships through adaptive quality systems.

Key success factors include:

1. **Resolution management** - Use low resolution for physics, higher for visuals
2. **Texture format optimization** - Prefer half-float textures
3. **Adaptive quality** - Adjust features based on device capabilities
4. **Efficient solvers** - Jacobi iteration provides good balance of accuracy and performance
5. **Memory efficiency** - Use structure-of-arrays and ping-pong buffers
6. **AGSL integration** - Leverage RuntimeShader with Compose for modern UI

With these techniques, developers can create engaging, interactive fluid effects that perform well across the diverse Android device ecosystem while maintaining visual quality and user experience.

---

## Appendix: Complete Shader Examples

### A.1 Complete Advection Shader

```agsl
uniform sampler2D uQuantity;
uniform sampler2D uVelocity;
uniform float uDt;
uniform vec2 uTexelSize;
uniform float uDissipation;
uniform int uAdvectionMethod; // 0=semi-lagrangian, 1=maccormack

vec2 sampleVelocity(vec2 coords) {
    vec2 vel = texture(uVelocity, coords).rg;
    // Remap from [0,1] to actual velocity range if needed
    return (vel - 0.5) * 2.0; // Assuming velocity stored in [-0.5,0.5]
}

vec4 semiLagrangianAdvection(vec2 coords) {
    vec2 velocity = sampleVelocity(coords);
    vec2 velocityUV = velocity * uTexelSize;
    
    vec2 sourceUV = coords - velocityUV * uDt;
    sourceUV = clamp(sourceUV, 0.0, 1.0);
    
    vec4 quantity = texture(uQuantity, sourceUV);
    quantity *= (1.0 - uDissipation);
    
    return quantity;
}

vec4 maccormackAdvection(vec2 coords) {
    vec2 velocity = sampleVelocity(coords);
    vec2 velocityUV = velocity * uTexelSize;
    
    // Forward step
    vec2 forwardUV = coords + velocityUV * uDt;
    vec4 qForward = texture(uQuantity, clamp(forwardUV, 0.0, 1.0));
    
    // Backward step
    vec2 backwardUV = coords - velocityUV * uDt;
    vec4 qBackward = texture(uQuantity, clamp(backwardUV, 0.0, 1.0));
    
    // Current
    vec4 qCurrent = texture(uQuantity, coords);
    
    // MacCormack correction
    vec4 corrected = qCurrent + 0.5 * (qForward - qBackward);
    
    // Limiter
    float minQ = min(min(qCurrent.r, qForward.r), qBackward.r);
    float maxQ = max(max(qCurrent.r, qForward.r), qBackward.r);
    corrected.r = clamp(corrected.r, minQ, maxQ);
    
    corrected *= (1.0 - uDissipation);
    
    return corrected;
}

vec4 main(vec2 coords) {
    if (uAdvectionMethod == 0) {
        return semiLagrangianAdvection(coords);
    } else {
        return maccormackAdvection(coords);
    }
}
```

### A.2 Complete Pressure Projection Shader

```agsl
uniform sampler2D uPressure;
uniform sampler2D uDivergence;
uniform vec2 uTexelSize;
uniform int uIteration; // Current iteration number

vec4 jacobiIteration(vec2 coords) {
    // Sample neighbors
    float pL = texture(uPressure, coords + vec2(-uTexelSize.x, 0.0)).r;
    float pR = texture(uPressure, coords + vec2(uTexelSize.x, 0.0)).r;
    float pB = texture(uPressure, coords + vec2(0.0, -uTexelSize.y)).r;
    float pT = texture(uPressure, coords + vec2(0.0, uTexelSize.y)).r;
    
    // Sample divergence
    float div = texture(uDivergence, coords).r;
    
    // Jacobi iteration
    float pressure = (pL + pR + pB + pT - div) * 0.25;
    
    return vec4(pressure, 0.0, 0.0, 1.0);
}

vec4 main(vec2 coords) {
    return jacobiIteration(coords);
}
```

### A.3 Complete Display Shader

```agsl
uniform sampler2D uDye;
uniform sampler2D uVelocity;
uniform sampler2D uPressure;
uniform vec2 uResolution;
uniform float uTime;
uniform int uVisualizationMode; // 0=dye, 1=velocity, 2=pressure

vec3 heatMap(float value) {
    // Blue to red heatmap
    vec3 color;
    color.r = smoothstep(0.0, 1.0, value);
    color.g = smoothstep(0.5, 0.5, value) * smoothstep(0.5, 0.5, 1.0 - value);
    color.b = smoothstep(0.0, 1.0, 1.0 - value);
    return color;
}

vec4 visualizeDye(vec2 coords) {
    vec4 dye = texture(uDye, coords);
    // Add some fake lighting
    vec2 velocity = texture(uVelocity, coords).rg;
    float lighting = dot(normalize(velocity), vec3(0.5, 0.5, 1.0).xy);
    dye.rgb += lighting * 0.1;
    return dye;
}

vec4 visualizeVelocity(vec2 coords) {
    vec2 velocity = texture(uVelocity, coords).rg;
    float speed = length(velocity);
    vec3 color = heatMap(speed * 10.0);
    return vec4(color, 1.0);
}

vec4 visualizePressure(vec2 coords) {
    float pressure = texture(uPressure, coords).r;
    // Normalize pressure for visualization
    float normalized = (pressure + 1.0) / 2.0;
    vec3 color = heatMap(normalized);
    return vec4(color, 1.0);
}

vec4 main(vec2 coords) {
    vec2 uv = coords / uResolution;
    
    switch (uVisualizationMode) {
        case 0: return visualizeDye(uv);
        case 1: return visualizeVelocity(uv);
        case 2: return visualizePressure(uv);
        default: return visualizeDye(uv);
    }
}
```

---

*End of Document*