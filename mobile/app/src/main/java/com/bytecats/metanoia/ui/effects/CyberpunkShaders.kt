package com.bytecats.metanoia.ui.effects

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import org.intellij.lang.annotations.Language

object CyberpunkShaders {

    @Language("AGSL")
    const val HUD_PROJECTION_SHADER = """
        uniform float2 resolution;
        uniform float time;
        layout(color) uniform half4 baseColor;
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            
            // Subtle scanlines
            float scanline = sin(uv.y * 800.0 - time * 5.0) * 0.03;
            
            // Subtle projection grid
            float2 gridUv = uv * 30.0;
            float gridLineX = abs(fract(gridUv.x) - 0.5) < 0.02 ? 0.05 : 0.0;
            float gridLineY = abs(fract(gridUv.y) - 0.5) < 0.02 ? 0.05 : 0.0;
            float grid = max(gridLineX, gridLineY);
            
            // Tokyo Night Palette mixing
            half3 color = baseColor.rgb;
            color += half3(0.0, 0.1, 0.2) * half(grid);
            color -= half3(half(scanline));
            
            // Chromatic aberration at edges
            float dist = distance(uv, float2(0.5, 0.5));
            float vignette = smoothstep(0.8, 0.2, dist);
            color *= half(vignette * 0.9 + 0.1);
            
            return half4(color, baseColor.a);
        }
    """

    @Language("AGSL")
    const val GLOW_AURA_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float time;
        layout(color) uniform half4 auraColor;
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            float2 center = float2(0.5, 0.5);
            float dist = distance(uv, center);
            
            float pulse = 0.5 + 0.5 * sin(time * 3.0);
            float intensity = 1.0 - smoothstep(0.0, 0.8 + 0.2 * pulse, dist);
            half4 aura = half4(auraColor.rgb * half(intensity), auraColor.a * half(intensity * 0.5));
            return orig + aura;
        }
    """
}

fun Modifier.cyberpunkHudBackground(time: Float, baseColor: Color = Color(0xFF1A1B26)): Modifier {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        return this.drawWithCache {
            val shader = RuntimeShader(CyberpunkShaders.HUD_PROJECTION_SHADER)
            shader.setFloatUniform("resolution", size.width, size.height)
            shader.setFloatUniform("time", time)
            shader.setColorUniform("baseColor", android.graphics.Color.valueOf(baseColor.red, baseColor.green, baseColor.blue, baseColor.alpha).toArgb())
            val brush = ShaderBrush(shader)
            onDrawBehind {
                drawRect(brush)
            }
        }
    }
    return this
}

fun Modifier.cyberpunkGlowAura(time: Float, auraColor: Color = Color(0xFF7AA2F7)): Modifier {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        return this.graphicsLayer {
            val shader = RuntimeShader(CyberpunkShaders.GLOW_AURA_SHADER)
            shader.setFloatUniform("resolution", size.width, size.height)
            shader.setFloatUniform("time", time)
            shader.setColorUniform("auraColor", android.graphics.Color.valueOf(auraColor.red, auraColor.green, auraColor.blue, auraColor.alpha).toArgb())
            renderEffect = RenderEffect.createRuntimeShaderEffect(shader, "composable").asComposeRenderEffect()
        }
    }
    return this
}
