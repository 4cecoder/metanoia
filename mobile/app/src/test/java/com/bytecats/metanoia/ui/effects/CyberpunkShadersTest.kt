package com.bytecats.metanoia.ui.effects

import org.junit.Assert.assertTrue
import org.junit.Test

class CyberpunkShadersTest {

    @Test
    fun testHudShaderContainsRequiredUniforms() {
        val shader = CyberpunkShaders.HUD_PROJECTION_SHADER
        assertTrue("HUD shader should define uniform resolution", shader.contains("uniform float2 resolution;"))
        assertTrue("HUD shader should define uniform time", shader.contains("uniform float time;"))
        assertTrue("HUD shader should define uniform baseColor", shader.contains("uniform half4 baseColor;"))
    }

    @Test
    fun testAuraShaderContainsRequiredUniforms() {
        val shader = CyberpunkShaders.GLOW_AURA_SHADER
        assertTrue("Aura shader should define uniform resolution", shader.contains("uniform float2 resolution;"))
        assertTrue("Aura shader should define uniform time", shader.contains("uniform float time;"))
        assertTrue("Aura shader should define uniform auraColor", shader.contains("uniform half4 auraColor;"))
    }
}
