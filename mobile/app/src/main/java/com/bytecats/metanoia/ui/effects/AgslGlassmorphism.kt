package com.bytecats.metanoia.ui.effects

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import org.intellij.lang.annotations.Language

@Language("AGSL")
const val LIQUID_GLASS_SHADER = """
    uniform shader composable;
    uniform float2 u_resolution;
    uniform float u_time;
    uniform float u_aberration;

    half4 main(float2 fragCoord) {
        float2 uv = fragCoord / u_resolution;
        
        // Liquid wave displacement offset
        float wave = sin(uv.x * 12.0 + u_time * 2.0) * cos(uv.y * 12.0 + u_time * 1.5) * 0.008;
        
        // Chromatic aberration (RGB shift)
        half4 colorR = composable.eval(fragCoord + float2(wave + u_aberration, wave));
        half4 colorG = composable.eval(fragCoord + float2(wave, wave));
        half4 colorB = composable.eval(fragCoord + float2(wave - u_aberration, wave));
        
        // Tokyo Night ambient tint
        half3 tint = half3(0.48, 0.63, 0.97) * 0.12; // #7aa2f7
        
        return half4(colorR.r + tint.r, colorG.g + tint.g, colorB.b + tint.b, colorG.a);
    }
"""

/**
 * Applies an AGSL (Android Graphics Shader Language) liquid glassmorphism shader effect
 * on Android 13+ (API 33+), with graceful fallback for earlier Android versions.
 */
fun Modifier.agslLiquidGlass(
    time: Float,
    resolutionX: Float,
    resolutionY: Float,
    aberration: Float = 4f
): Modifier = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    this.graphicsLayer {
        val shader = RuntimeShader(LIQUID_GLASS_SHADER)
        shader.setFloatUniform("u_resolution", resolutionX.coerceAtLeast(1f), resolutionY.coerceAtLeast(1f))
        shader.setFloatUniform("u_time", time)
        shader.setFloatUniform("u_aberration", aberration)
        renderEffect = RenderEffect.createRuntimeShaderEffect(shader, "composable").asComposeRenderEffect()
    }
} else {
    this
}
