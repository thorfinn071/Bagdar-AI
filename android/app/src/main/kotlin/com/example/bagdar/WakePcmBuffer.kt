package com.example.bagdar

/** Four seconds of volatile PCM. Leading silence cannot permanently overflow it. */
class WakePcmBuffer(private val capacity: Int = 64000) {
    private val samples = ShortArray(capacity)
    private var next = 0
    private var size = 0
    fun append(source: ShortArray, count: Int) {
        require(count in 0..source.size)
        for (index in 0 until count) {
            samples[next] = source[index]
            next = (next + 1) % capacity
            size = minOf(size + 1, capacity)
        }
    }
    fun clear() { next = 0; size = 0 }
    fun pcm16Bytes(): ByteArray {
        val result = ByteArray(size * 2)
        val first = (next - size + capacity) % capacity
        for (index in 0 until size) {
            val value = samples[(first + index) % capacity].toInt()
            result[index * 2] = (value and 255).toByte()
            result[index * 2 + 1] = ((value shr 8) and 255).toByte()
        }
        return result
    }
}
