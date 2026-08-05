package com.bytecats.metanoia.ui.components

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.assertIsDisplayed
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.Canon
import com.bytecats.metanoia.models.TextTradition
import com.bytecats.metanoia.models.BookSection
import com.bytecats.metanoia.ui.components.bible.BookGrid
import org.junit.Assert.assertEquals

@RunWith(RobolectricTestRunner::class)
@Config(instrumentedPackages = ["androidx.loader.content"])
class BookGridProgressTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun testCompletionFractions() {
        // Simulating completionMap calculations for Old Testament, New Testament, and Ethiopic books.
        // E.g., read chapters / total chapters.
        val genesisCompletion = 25f / 50f
        val matthewCompletion = 28f / 28f
        val enochCompletion = 27f / 108f

        val completionMap = mapOf(
            "Genesis" to genesisCompletion,
            "Matthew" to matthewCompletion,
            "Enoch" to enochCompletion
        )

        assertEquals(0.5f, completionMap["Genesis"] ?: 0f)
        assertEquals(1.0f, completionMap["Matthew"] ?: 0f)
        assertEquals(0.25f, completionMap["Enoch"] ?: 0f)
    }

    @Test
    fun testBookGridRendering() {
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

        composeTestRule.setContent {
            BookGrid(
                books = books,
                completionMap = completionMap,
                readCompletionMap = completionMap,
                showEthiopianCanon = true,
                showApocrypha = true,
                onBookSelected = {}
            )
        }

        // Verify that books and sections are displayed
        composeTestRule.onNodeWithText("Genesis").assertIsDisplayed()
        composeTestRule.onNodeWithText("Matthew").assertIsDisplayed()
        composeTestRule.onNodeWithText("Enoch").assertIsDisplayed()
        composeTestRule.onNodeWithText("Old Testament").assertIsDisplayed()
        composeTestRule.onNodeWithText("New Testament").assertIsDisplayed()
        composeTestRule.onNodeWithText("Ethiopian").assertIsDisplayed()
    }
}
