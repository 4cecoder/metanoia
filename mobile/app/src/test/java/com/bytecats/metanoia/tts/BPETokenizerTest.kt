package com.bytecats.metanoia.tts

import org.junit.Assert.assertEquals
import org.junit.Test

class BPETokenizerTest {

    @Test
    fun testTokenSplits() {
        val vocab = mapOf(
            "hello" to 1,
            " " to 2,
            "world" to 3,
            "!" to 4,
            "he" to 5,
            "ll" to 6,
            "o" to 7,
            "<unk>" to 99
        )
        val tokenizer = BPETokenizer.create(vocab)

        val tokens = tokenizer.tokenize("hello world!")
        assertEquals(listOf(1, 2, 3, 4), tokens)
    }

    @Test
    fun testFallbackTextCleaning() {
        val vocab = mapOf(
            "clean" to 10,
            "text" to 11,
            " " to 2,
            "<unk>" to 99
        )
        val tokenizer = BPETokenizer.create(vocab)
        
        // Control character \u0007 (bell) should be stripped, multiple spaces should be compressed
        val messyText = "  clean \u0007 text  "
        val tokens = tokenizer.tokenize(messyText)
        
        assertEquals(listOf(10, 2, 11), tokens)
    }

    @Test
    fun testVocabularyBoundaryChecks() {
        val vocab = mapOf(
            "valid" to 100,
            " " to 2,
            "<unk>" to 99
        )
        val tokenizer = BPETokenizer.create(vocab)
        
        val tokens = tokenizer.tokenize("valid test")
        
        // valid(100), ' '(2), t(99), e(99), s(99), t(99)
        assertEquals(listOf(100, 2, 99, 99, 99, 99), tokens)
    }
}
