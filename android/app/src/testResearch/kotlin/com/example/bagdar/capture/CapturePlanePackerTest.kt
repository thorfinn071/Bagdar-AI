package com.example.bagdar.capture

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer

class CapturePlanePackerTest {
    @Test fun interleavedChromaAndRowPaddingAreNotCopied() {
        val source = ByteBuffer.wrap(byteArrayOf(1, 99, 2, 98, 97, 96, 3, 95, 4))
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), CapturePlanePacker.pack(source, 2, 2, 6, 2, 1))
    }
    @Test fun depthBytesRetainLittleEndianRepresentation() {
        val source = ByteBuffer.wrap(byteArrayOf(0x34, 0x12, 0x78, 0x56, 99, 99, 0, 0, -1, -1))
        assertArrayEquals(byteArrayOf(0x34, 0x12, 0x78, 0x56, 0, 0, -1, -1),
            CapturePlanePacker.pack(source, 2, 2, 6, 2, 2))
    }
    @Test fun bufferPositionAndLimitRemainUnchanged() {
        val source = ByteBuffer.wrap(byteArrayOf(99, 1, 2, 3, 99)).apply { position(1); limit(4) }
        assertArrayEquals(byteArrayOf(1, 2, 3), CapturePlanePacker.pack(source, 3, 1, 3, 1, 1))
        assertEquals(1, source.position()); assertEquals(4, source.limit())
    }
    @Test(expected = IllegalArgumentException::class) fun truncatedLastSampleIsRejected() {
        CapturePlanePacker.pack(ByteBuffer.allocate(9), 2, 2, 6, 2, 2)
    }
    @Test(expected = IllegalArgumentException::class) fun overlappingRowsAreRejected() {
        CapturePlanePacker.pack(ByteBuffer.allocate(10), 2, 2, 2, 2, 2)
    }
    @Test(expected = IllegalArgumentException::class) fun overlappingDepthSamplesAreRejected() {
        CapturePlanePacker.pack(ByteBuffer.allocate(10), 2, 2, 4, 1, 2)
    }
}
