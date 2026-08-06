package com.bytecats.metanoia.ui.effects.lighting

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import org.intellij.lang.annotations.Language

// Import PBR lighting modifiers
import com.bytecats.metanoia.ui.effects.lighting.DynamicLightingModifiers.applyPBRLighting
import com.bytecats.metanoia.ui.effects.lighting.DynamicLightingModifiers.cinematicLighting

/**
 * PBR Lighting System Integration Examples
 * Demonstrates how to use the advanced PBR lighting system components
 */

@Composable
fun PBRLightingExample() {
    var time by remember { mutableStateOf(0f) }
    var selectedMaterial by remember { mutableStateOf<PBRMaterial>(PBRMaterial.defaultDielectric()) }
    var selectedConfig by remember { mutableStateOf<LightingSystemConfig>(LightingSystemConfig.midRange()) }
    
    // Animate time
    // time = (System.currentTimeMillis() % 10000) / 10000f * 6.28f
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Text(
            text = "PBR Lighting System",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onBackground
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        // Example 1: Default Dielectric Material
        PBRMaterialCard(
            title = "Default Dielectric",
            material = PBRMaterial.defaultDielectric(),
            config = selectedConfig,
            time = time
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        // Example 2: Metallic Material
        PBRMaterialCard(
            title = "Metallic",
            material = PBRMaterial.defaultMetallic(),
            config = selectedConfig,
            time = time
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        // Example 3: Glass Material
        PBRMaterialCard(
            title = "Glass",
            material = PBRMaterial.glass(),
            config = selectedConfig,
            time = time
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        // Example 4: Custom Material
        PBRMaterialCard(
            title = "Custom Emissive",
            material = PBRMaterial.emissive(
                color = Color(1f, 0.8f, 0.4f),
                baseAlbedo = Color(0.6f, 0.6f, 0.6f)
            ),
            config = selectedConfig,
            time = time
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        // Example 5: Dynamic Lighting Manager
        DynamicLightingCard(time = time)
        
        Spacer(modifier = Modifier.height(16.dp))
        
        // Example 6: Cinematic Lighting
        CinematicLightingCard(time = time)
    }
}

@Composable
private fun PBRMaterialCard(
    title: String,
    material: PBRMaterial,
    config: LightingSystemConfig,
    time: Float
) {
    val manager = remember { DynamicLightingManager(config).apply { setupDefaultLighting() } }
    
    Column {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground
        )
        
        Box(
            modifier = Modifier
                .size(200.dp, 150.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Gray)
                .then(
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        Modifier.applyPBRLighting(
                            manager = manager,
                            material = material,
                            time = time,
                            cameraPosition = androidx.compose.ui.geometry.Offset(50f, 50f)
                        )
                    } else {
                        Modifier
                    }
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "PBR Material",
                color = Color.White
            )
        }
        
        // Material properties display
        Text(
            text = "Roughness: ${material.roughness}, Metallic: ${material.metallic}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.7f)
        )
    }
}

@Composable
private fun DynamicLightingCard(time: Float) {
    val config = remember { LightingSystemConfig.midRange() }
    val manager = remember { 
        DynamicLightingManager(config).apply {
            addLight(LightSource.warmLight())
            addLight(LightSource.coolLight())
            addLight(LightSource.defaultDirectionalLight())
        }
    }
    
    Column {
        Text(
            text = "Dynamic Multi-Light",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground
        )
        
        Box(
            modifier = Modifier
                .size(200.dp, 150.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Gray)
                .then(
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        Modifier.applyPBRLighting(
                            manager = manager,
                            material = PBRMaterial.defaultDielectric(),
                            time = time,
                            cameraPosition = androidx.compose.ui.geometry.Offset(50f, 50f)
                        )
                    } else {
                        Modifier
                    }
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "3 Lights",
                color = Color.White
            )
        }
    }
}

@Composable
private fun CinematicLightingCard(time: Float) {
    Column {
        Text(
            text = "Cinematic Lighting",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground
        )
        
        Box(
            modifier = Modifier
                .size(200.dp, 150.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Gray)
                .then(
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        Modifier.cinematicLighting(
                            material = PBRMaterial.defaultDielectric(),
                            time = time
                        )
                    } else {
                        Modifier
                    }
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "Dramatic Setup",
                color = Color.White
            )
        }
    }
}

/**
 * Advanced PBR usage example with animation
 */
@Composable
fun AdvancedPBRExample() {
    var time by remember { mutableStateOf(0f) }
    
    // Create custom material with animation
    val animatedMaterial by remember(time) {
        mutableStateOf(
            PBRMaterial(
                albedo = Color(
                    red = 0.5f + 0.3f * kotlin.math.sin(time),
                    green = 0.5f + 0.3f * kotlin.math.sin(time + 2f),
                    blue = 0.5f + 0.3f * kotlin.math.sin(time + 4f)
                ),
                metallic = 0.3f + 0.2f * kotlin.math.sin(time * 0.5f),
                roughness = 0.4f + 0.2f * kotlin.math.cos(time * 0.3f),
                emissive = Color(
                    red = 0.1f * kotlin.math.max(0f, kotlin.math.sin(time)),
                    green = 0.05f * kotlin.math.max(0f, kotlin.math.sin(time + 1f)),
                    blue = 0.02f
                )
            )
        )
    }
    
    val config = remember { LightingSystemConfig.highEnd() }
    val manager = remember { DynamicLightingManager(config) }
    
    Column(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .then(
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        Modifier.applyPBRLighting(
                            manager = manager,
                            material = animatedMaterial,
                            time = time,
                            cameraPosition = androidx.compose.ui.geometry.Offset(50f, 50f)
                        )
                    } else {
                        Modifier
                    }
                )
        )
    }
}

/**
 * Material showcase with different PBR properties
 */
@Composable
fun MaterialShowcase() {
    val materials = listOf(
        "Plastic" to PBRMaterial.glossyPlastic(Color(0.8f, 0.2f, 0.2f)),
        "Metal" to PBRMaterial.roughMetal(Color(0.7f, 0.7f, 0.7f)),
        "Gold" to PBRMaterial(
            albedo = Color(1f, 0.86f, 0.57f),
            metallic = 1f,
            roughness = 0.3f
        ),
        "Copper" to PBRMaterial(
            albedo = Color(0.95f, 0.64f, 0.54f),
            metallic = 1f,
            roughness = 0.25f
        ),
        "Rubber" to PBRMaterial.matte(Color(0.1f, 0.1f, 0.1f)),
        "Fabric" to PBRMaterial.matte(Color(0.6f, 0.4f, 0.3f))
    )
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text(
            text = "PBR Material Library",
            style = MaterialTheme.typography.headlineMedium
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        materials.forEach { (name, material) ->
            MaterialCard(name, material)
            Spacer(modifier = Modifier.height(12.dp))
        }
    }
}

@Composable
private fun MaterialCard(name: String, material: PBRMaterial) {
    val manager = remember { 
        DynamicLightingManager(LightingSystemConfig.midRange()).apply {
            setupStudioLighting()
        }
    }
    
    Column {
        Text(
            text = name,
            style = MaterialTheme.typography.titleMedium
        )
        
        Box(
            modifier = Modifier
                .size(150.dp, 100.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Gray)
                .then(
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        Modifier.applyPBRLighting(
                            manager = manager,
                            material = material,
                            time = 0f,
                            cameraPosition = androidx.compose.ui.geometry.Offset(50f, 50f)
                        )
                    } else {
                        Modifier
                    }
                )
        )
    }
}

/**
 * Lighting configuration comparison
 */
@Composable
fun LightingConfigComparison() {
    val configs = listOf(
        "Low Quality" to LightingSystemConfig.lowEnd(),
        "Medium Quality" to LightingSystemConfig.midRange(),
        "High Quality" to LightingSystemConfig.highEnd(),
        "Ultra Quality" to LightingSystemConfig.ultra()
    )
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text(
            text = "Quality Presets Comparison",
            style = MaterialTheme.typography.headlineMedium
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        configs.forEach { (name, config) ->
            ConfigCard(name, config)
            Spacer(modifier = Modifier.height(12.dp))
        }
    }
}

@Composable
private fun ConfigCard(name: String, config: LightingSystemConfig) {
    val manager = remember { 
        DynamicLightingManager(config).apply {
            setupDramaticLighting()
        }
    }
    
    Column {
        Text(
            text = name,
            style = MaterialTheme.typography.titleMedium
        )
        
        Box(
            modifier = Modifier
                .size(150.dp, 100.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Gray)
                .then(
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        Modifier.applyPBRLighting(
                            manager = manager,
                            material = PBRMaterial.defaultMetallic(),
                            time = 0f,
                            cameraPosition = androidx.compose.ui.geometry.Offset(50f, 50f)
                        )
                    } else {
                        Modifier
                    }
                )
        )
        
        Text(
            text = "Max Lights: ${config.getEffectiveMaxLights()}, " +
                  "Shadow Res: ${config.getEffectiveShadowResolution()}",
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray
        )
    }
}

@Preview(showBackground = true)
@Composable
fun PBRLightingExamplePreview() {
    PBRLightingExample()
}