package com.bytecats.metanoia.ui.components.bible

import com.bytecats.metanoia.ui.components.bible.hasHebrewChars
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VerseItemTest {

    // Genesis 1:1 in Hebrew (BHS/WLC) — bereshit bara elohim...
    private val GENESIS_1_1_HEBREW = "\u05d1\u05bc\u05b0\u05e8\u05b5\u05d0\u05e9\u05c1\u05b4\u05d9\u05ea \u05d1\u05bc\u05b8\u05e8\u05b8\u05d0 \u05d0\u05b1\u05dc\u05b9\u05d4\u05b4\u05d9\u05dd \u05d0\u05b5\u05ea \u05d4\u05b7\u05e9\u05bc\u05b8\u05de\u05b7\u05d9\u05b4\u05dd \u05d5\u05b0\u05d0\u05b5\u05ea \u05d4\u05b8\u05d0\u05b8\u05e8\u05b6\u05e5"

    private val GENESIS_1_1_ENGLISH = "In the beginning God created the heavens and the earth."

    @Test
    fun hasHebrewChars_detectsHebrewGenesis1_1() {
        assertTrue("Genesis 1:1 in Hebrew should be detected as Hebrew", hasHebrewChars(GENESIS_1_1_HEBREW))
    }

    @Test
    fun hasHebrewChars_rejectsEnglishGenesis1_1() {
        assertFalse("English NKJV text should NOT be detected as Hebrew", hasHebrewChars(GENESIS_1_1_ENGLISH))
    }

    @Test
    fun hasHebrewChars_detectsSingleHebrewLetter() {
        assertTrue("Single Hebrew letter alef should be detected", hasHebrewChars("\u05d0"))
    }

    @Test
    fun hasHebrewChars_rejectsEmptyString() {
        assertFalse("Empty string should not be detected as Hebrew", hasHebrewChars(""))
    }

    @Test
    fun hasHebrewChars_rejectsPlainAscii() {
        assertFalse("Plain ASCII text should not be detected as Hebrew", hasHebrewChars("Hello world"))
    }

    @Test
    fun hasHebrewChars_detectsHebrewWithPunctuation() {
        assertTrue("Hebrew with English punctuation should still be detected", hasHebrewChars("\u05d1\u05bc\u05b0\u05e8\u05b5\u05d0\u05e9\u05c1\u05b4\u05d9\u05ea."))
    }

    @Test
    fun hasHebrewChars_detectsHebrewPresentationForms() {
        // Hebrew presentation forms (U+FB1D-FB4F) — e.g. U+FB2F for alef-lamed ligature
        assertTrue("Hebrew presentation form should be detected", hasHebrewChars("\uFB2F"))
    }
}
