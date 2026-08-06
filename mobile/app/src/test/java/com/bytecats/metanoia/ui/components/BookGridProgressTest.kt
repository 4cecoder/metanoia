package com.bytecats.metanoia.ui.components

import org.junit.Test
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.Canon
import com.bytecats.metanoia.models.TextTradition
import com.bytecats.metanoia.models.BookSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

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
    fun testBookGridDataFilter() {
        val books = listOf(
            BibleBook(
                name = "Genesis",
                chapters = 50,
                testament = "Old",
                isApocrypha = false,
                canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
                textTradition = TextTradition.Masoretic,
                section = BookSection.Pentateuch
            ),
            BibleBook(
                name = "Matthew",
                chapters = 28,
                testament = "New",
                isApocrypha = false,
                canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
                textTradition = TextTradition.NewTestament,
                section = BookSection.Gospels
            ),
            BibleBook(
                name = "Enoch",
                chapters = 108,
                testament = "Eth",
                isApocrypha = true,
                canons = setOf(Canon.Ethiopian),
                textTradition = TextTradition.Ethiopic,
                section = BookSection.EthiopianCanon
            )
        )

        val completionMap = mapOf(
            "Genesis" to 0.5f,
            "Matthew" to 1.0f,
            "Enoch" to 0.25f
        )

        assertEquals(3, books.size)
        assertTrue(books.any { it.name == "Genesis" && completionMap[it.name] == 0.5f })
        assertTrue(books.any { it.name == "Matthew" && completionMap[it.name] == 1.0f })
        assertTrue(books.any { it.name == "Enoch" && completionMap[it.name] == 0.25f })
    }
}
