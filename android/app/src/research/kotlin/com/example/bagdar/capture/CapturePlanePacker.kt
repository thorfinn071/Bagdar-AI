package com.example.bagdar.capture

import java.nio.ByteBuffer

/** Copies actual samples, preserving byte order and the caller's buffer state. */
internal object CapturePlanePacker {
    fun pack(source: ByteBuffer, width: Int, height: Int, rowStride: Int,
        pixelStride: Int, bytesPerPixel: Int): ByteArray {
        require(width in 1..4096 && height in 1..4096 && bytesPerPixel in 1..2)
        require(pixelStride >= bytesPerPixel)
        val rowBytes = (width - 1L) * pixelStride + bytesPerPixel
        require(rowStride >= rowBytes)
        val input = source.duplicate().slice()
        val lastByte = (height - 1L) * rowStride + rowBytes
        require(lastByte <= input.remaining()) { "plane buffer truncated" }
        val packed = ByteArray(width * height * bytesPerPixel)
        var output = 0
        for (y in 0 until height) for (x in 0 until width) {
            val start = y * rowStride + x * pixelStride
            for (byte in 0 until bytesPerPixel) packed[output++] = input.get(start + byte)
        }
        return packed
    }
}
