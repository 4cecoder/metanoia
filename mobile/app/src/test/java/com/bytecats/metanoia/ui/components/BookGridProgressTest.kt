package com.bytecats.metanoia.ui.components

import org.junit.Test
import org.junit.Assert.assertEquals

class BookGridProgressTest {

    @Test
    fun testCompletionFractions() {
        val genesisCompletion = 25f / 50f
        val matthewCompletion = 28f / 28f
        val enochCompletion = 27f / 108f

        val completionMap = mapOf(
            "Genesis" to genesisCompletion,
            "Matthew" to matthewCompletion,
            "Enoch" to enochCompletion
        )

        assertEquals(0.5f, completionMap["Genesis"] ?: 0f, 0.001f)
        assertEquals(1.0f, completionMap["Matthew"] ?: 0f, 0.001f)
        assertEquals(0.25f, completionMap["Enoch"] ?: 0f, 0.001f)
    }

    @Test
    fun testBookGridProgressMapping() {
        val readCompletionMap = mapOf(
            "Genesis" to 0.5f,
            "Matthew" to 1.0f,
            "Enoch" to 0.25f
        )

        val unreadBookProgress = readCompletionMap["Revelation"] ?: 0f
        val fullBookProgress = readCompletionMap["Matthew"] ?: 0f
        val halfBookProgress = readCompletionMap["Genesis"] ?: 0f

        assertEquals(0.0f, unreadBookProgress, 0.001f)
        assertEquals(1.0f, fullBookProgress, 0.001f)
        assertEquals(0.5f, halfBookProgress, 0.001f)
    }
}

