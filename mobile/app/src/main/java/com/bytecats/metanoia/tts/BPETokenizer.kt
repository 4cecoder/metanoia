package com.bytecats.metanoia.tts

/**
 * Byte Pair Encoding (BPE) Tokenizer.
 *
 * This is a clean-room implementation of BPE tokenization for Qwen3-TTS.
 * It handles text tokenization without external dependencies.
 */
class BPETokenizer(
    private val merges: List<Pair<String, String>>,
    private val vocab: Map<String, Int>
) {
    companion object {
        // Special tokens
        const val PAD_TOKEN = "<pad>"
        const val EOS_TOKEN = "<|endoftext|>"
        const val BOS_TOKEN = "<|startoftext|>"
        const val UNK_TOKEN = "<unk>"
        
        /**
         * Create a basic BPE tokenizer from vocabulary.
         */
        fun create(vocab: Map<String, Int>): BPETokenizer {
            val merges = mutableListOf<Pair<String, String>>()
            
            // Basic character-level merges (simplified)
            vocab.keys.filter { it.length == 1 }.forEach { c ->
                vocab.keys.filter { it.startsWith(c) && it.length == 2 }.forEach { bigram ->
                    merges.add(Pair(c, bigram.substring(1)))
                }
            }
            
            return BPETokenizer(merges, vocab)
        }
    }
    
    private val cache = mutableMapOf<String, List<Int>>()
    
    /**
     * Tokenize text into token IDs.
     */
    fun tokenize(text: String): List<Int> {
        val cacheKey = text
        cache[cacheKey]?.let { return it }
        
        // Convert to lowercase (common for TTS)
        val normalized = text.lowercase()
        
        // Basic tokenization (character-based with bigram merging)
        val tokens = mutableListOf<Int>()
        var i = 0
        
        while (i < normalized.length) {
            var matched = false
            
            // Try to match longest possible token
            for (len in minOf(8, normalized.length - i) downTo 1) {
                val substr = normalized.substring(i, i + len)
                val tokenId = vocab[substr]
                
                if (tokenId != null) {
                    tokens.add(tokenId)
                    i += len
                    matched = true
                    break
                }
            }
            
            if (!matched) {
                // Unknown character, use UNK token
                vocab[UNK_TOKEN]?.let { tokens.add(it) }
                i++
            }
        }
        
        cache[cacheKey] = tokens
        return tokens
    }
    
    /**
     * Convert token IDs back to text.
     */
    fun detokenize(tokenIds: List<Int>): String {
        val idToToken = vocab.entries.associate { it.value to it.key }
        
        return tokenIds.mapNotNull { id ->
            idToToken[id]?.replace(BOS_TOKEN, "")
                ?.replace(EOS_TOKEN, "")
                ?.replace(PAD_TOKEN, "")
                ?.replace(UNK_TOKEN, "")
        }.joinToString("")
    }
    
    /**
     * Get vocabulary size.
     */
    fun vocabSize(): Int = vocab.size
}