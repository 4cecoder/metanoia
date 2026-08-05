package com.bytecats.metanoia.tts

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * GGUF File Format Parser.
 *
 * GGUF (GPT-Generated Unified Format) is the binary format used by llama.cpp
 * for storing model weights. This is a clean-room implementation that parses
 * the format as documented in the GGUF specification.
 *
 * Structure:
 * - Header: Magic, version, tensor count, metadata KV pairs
 * - Tensor Metadata: Name, shape, type, offset
 * - Weights: Raw tensor data
 */
class GGUFReader(private val file: File) {
    private val raf = RandomAccessFile(file, "r")
    
    companion object {
        // GGUF magic: "GGUF"
        private val MAGIC = byteArrayOf(0x47, 0x47, 0x55, 0x46)
        
        // GGUF types
        const val UINT8 = 0u
        const val INT8 = 1u
        const val UINT16 = 2u
        const val INT16 = 3u
        const val UINT32 = 4u
        const val INT32 = 5u
        const val FLOAT32 = 6u
        const val BOOL = 7u
        const val STRING = 8u
        const val ARRAY = 9u
        const val UINT64 = 10u
        const val INT64 = 11u
        const val FLOAT64 = 12u
        
        // Qwen3-TTS specific keys
        const val KEY_GENERAL_ARCHITECTURE = "general.architecture"
        const val KEY_GENERAL_QUANTIZATION = "general.quantization_version"
        const val KEY_TOKENIZER_MODEL = "tokenizer.ggml.model"
        const val KEY_TOKENIZER_LIST = "tokenizer.ggml.tokens"
        const val KEY_TOKENIZER_MERGES = "tokenizer.ggml.merges"
    }
    
    // Header information
    var version: UInt = 0u
        private set
    var tensorCount: UInt = 0u
        private set
    var metadataKvCount: UInt = 0u
        private set
    
    // Metadata KV pairs
    private val metadata = mutableMapOf<String, Any>()
    
    // Tensor information
    data class TensorInfo(
        val name: String,
        val nDims: UInt,
        val shape: List<ULong>,
        val type: UInt,
        val offset: ULong
    )
    private val tensors = mutableListOf<TensorInfo>()
    
    init {
        parseHeader()
        parseMetadata()
        parseTensorInfo()
    }
    
    private fun parseHeader() {
        val headerBytes = ByteArray(12)
        try {
            raf.readFully(headerBytes)
        } catch (e: Exception) {
            throw IllegalArgumentException("Failed to read GGUF header: file too short", e)
        }
        
        // Check magic
        if (!headerBytes.sliceArray(0..3).contentEquals(MAGIC)) {
            throw IllegalArgumentException("Invalid GGUF file: magic mismatch")
        }
        
        // Read version
        version = ByteBuffer.wrap(headerBytes, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int.toUInt()
        
        // Read tensor count
        tensorCount = ByteBuffer.wrap(headerBytes, 8, 4).order(ByteOrder.LITTLE_ENDIAN).int.toUInt()
        
        // Read metadata KV count
        val kvBytes = ByteArray(4)
        try {
            raf.readFully(kvBytes)
        } catch (e: Exception) {
            throw IllegalArgumentException("Failed to read metadata KV count: file too short", e)
        }
        metadataKvCount = ByteBuffer.wrap(kvBytes).order(ByteOrder.LITTLE_ENDIAN).int.toUInt()
    }
    
    private fun parseMetadata() {
        repeat(metadataKvCount.toInt()) {
            val key = readString()
            val type = readValueType()
            val value = readValue(type)
            metadata[key] = value
        }
    }
    
    private fun parseTensorInfo() {
        repeat(tensorCount.toInt()) {
            val name = readString()
            val nDims = readUInt32()
            val shape = List(nDims.toInt()) { readUInt64() }
            val type = readUInt32()
            val offset = readUInt64()
            
            tensors.add(TensorInfo(name, nDims, shape, type, offset))
        }
    }
    
    private fun readString(): String {
        try {
            val length = readUInt64().toLong()
            if (length > Int.MAX_VALUE) {
                throw IllegalArgumentException("String length too large: $length")
            }
            if (length < 0) {
                throw IllegalArgumentException("Negative string length: $length")
            }
            val bytes = ByteArray(length.toInt())
            raf.readFully(bytes)
            return String(bytes, Charsets.UTF_8)
        } catch (e: Exception) {
            throw IllegalArgumentException("Failed to read string: ${e.message}", e)
        }
    }
    
    private fun readValueType(): UInt = readUInt32()
    
    private fun readValue(type: UInt): Any {
        return when (type) {
            UINT8 -> readUInt8()
            INT8 -> readInt8()
            UINT16 -> readUInt16()
            INT16 -> readInt16()
            UINT32 -> readUInt32()
            INT32 -> readInt32()
            FLOAT32 -> readFloat32()
            BOOL -> readUInt8() != 0u
            STRING -> readString()
            ARRAY -> readArray()
            UINT64 -> readUInt64()
            INT64 -> readInt64()
            FLOAT64 -> readFloat64()
            else -> throw IllegalArgumentException("Unknown GGUF type: $type")
        }
    }
    
    private fun readArray(): List<Any> {
        val type = readUInt32()
        val length = readUInt64().toInt()
        return List(length) { readValue(type) }
    }
    
    private fun readUInt8(): UInt = raf.readUnsignedByte().toUInt()
    private fun readInt8(): Int = raf.readByte().toInt()
    private fun readUInt16(): UInt = raf.readUnsignedShort().toUInt()
    private fun readInt16(): Int = raf.readShort().toInt()
    private fun readUInt32(): UInt = raf.readInt().toUInt()
    private fun readInt32(): Int = raf.readInt()
    private fun readUInt64(): ULong = raf.readLong().toULong()
    private fun readInt64(): Long = raf.readLong()
    private fun readFloat32(): Float = raf.readFloat()
    private fun readFloat64(): Double = raf.readDouble()
    
    /**
     * Get metadata value by key.
     */
    fun getMetadata(key: String): Any? = metadata[key]
    
    /**
     * Get metadata value as string.
     */
    fun getMetadataString(key: String): String? {
        return (metadata[key] as? String)
    }
    
    /**
     * Get metadata value as int.
     */
    fun getMetadataInt(key: String): Int? {
        return when (val v = metadata[key]) {
            is Int -> v
            is UInt -> v.toInt()
            is Long -> v.toInt()
            is ULong -> v.toLong().toInt()
            else -> null
        }
    }
    
    /**
     * Get all tensor names.
     */
    fun getTensorNames(): List<String> = tensors.map { it.name }
    
    /**
     * Get tensor info by name.
     */
    fun getTensorInfo(name: String): TensorInfo? {
        return tensors.find { it.name == name }
    }
    
    /**
     * Load tensor data by name.
     */
    fun loadTensor(name: String): FloatArray? {
        val info = getTensorInfo(name) ?: return null
        
        // Seek to tensor offset
        raf.seek(info.offset.toLong())
        
        // Calculate total elements
        val totalElements = info.shape.fold(1UL) { acc, dim -> acc * dim }.toLong()
        
        // Read based on type
        return when (info.type) {
            FLOAT32 -> {
                val bytes = ByteArray(totalElements.toInt() * 4)
                raf.readFully(bytes)
                val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                FloatArray(totalElements.toInt()) { buffer.float }
            }
            else -> {
                // For quantized types, we'd need dequantization
                // This is a simplified implementation
                null
            }
        }
    }
    
    fun close() {
        raf.close()
    }
}