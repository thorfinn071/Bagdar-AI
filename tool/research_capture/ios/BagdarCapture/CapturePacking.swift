import ARKit
import CoreVideo
import CryptoKit
import Foundation
import simd

enum CaptureFailure: Error {
  case unsupportedBuffer, invalidBuffer, payloadLimit
}

// This value type is used by the recorder, and exercised without an AR camera.
struct NewestOnlySlot<T> {
  private(set) var active = false
  private(set) var pending: T?
  mutating func offer(_ value: T) -> (start: T?, replaced: Bool) {
    if !active { active = true; return (value, false) }
    let replaced = pending != nil
    pending = value
    return (nil, replaced)
  }
  mutating func complete() -> T? {
    let next = pending
    pending = nil
    active = next != nil
    return next
  }
  mutating func discardPending() -> Bool {
    let discarded = pending != nil
    pending = nil
    return discarded
  }
}

struct PackedPlane {
  let width: Int, height: Int, bytesPerPixel: Int, sourceRowStride: Int
  let data: Data

  static func copyRows(base: UnsafeRawPointer, width: Int, height: Int,
                       bytesPerPixel: Int, rowStride: Int) throws -> PackedPlane {
    guard width > 0, height > 0, width <= 4096, height <= 4096,
          (1...4).contains(bytesPerPixel), rowStride >= width * bytesPerPixel else {
      throw CaptureFailure.invalidBuffer
    }
    let rowBytes = width * bytesPerPixel
    var data = Data(count: rowBytes * height)
    data.withUnsafeMutableBytes { dst in
      guard let target = dst.baseAddress else { return }
      for y in 0..<height {
        target.advanced(by: y * rowBytes).copyMemory(
          from: base.advanced(by: y * rowStride), byteCount: rowBytes)
      }
    }
    return PackedPlane(width: width, height: height, bytesPerPixel: bytesPerPixel,
                       sourceRowStride: rowStride, data: data)
  }

  static func copy(_ buffer: CVPixelBuffer, plane: Int?, bytesPerPixel: Int) throws -> PackedPlane {
    guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
      throw CaptureFailure.invalidBuffer
    }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = plane.map { CVPixelBufferGetWidthOfPlane(buffer, $0) } ?? CVPixelBufferGetWidth(buffer)
    let height = plane.map { CVPixelBufferGetHeightOfPlane(buffer, $0) } ?? CVPixelBufferGetHeight(buffer)
    let stride = plane.map { CVPixelBufferGetBytesPerRowOfPlane(buffer, $0) } ?? CVPixelBufferGetBytesPerRow(buffer)
    let address = plane.flatMap { CVPixelBufferGetBaseAddressOfPlane(buffer, $0) }
      ?? (plane == nil ? CVPixelBufferGetBaseAddress(buffer) : nil)
    guard let address else { throw CaptureFailure.invalidBuffer }
    return try copyRows(base: address, width: width, height: height,
                        bytesPerPixel: bytesPerPixel, rowStride: stride)
  }

  static func validity(depth: PackedPlane) -> PackedPlane {
    // Preserve the original depth bits, including NaN. Mask is not confidence.
    var mask = Data(count: depth.width * depth.height)
    depth.data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
      mask.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
        for i in 0..<(depth.width * depth.height) {
          let bits = source.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
          let z = Float(bitPattern: UInt32(littleEndian: bits))
          target[i] = z.isFinite && z > 0 ? UInt8(1) : UInt8(0)
        }
      }
    }
    return PackedPlane(width: depth.width, height: depth.height, bytesPerPixel: 1,
                       sourceRowStride: depth.width, data: mask)
  }
}

func digest(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func jsonData(_ value: Any) throws -> Data {
  try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

func matrixValues(_ m: simd_float4x4) -> [Double] {
  (0..<4).flatMap { c in (0..<4).map { r in Double(m[c][r]) } }
}

func matrixValues(_ m: simd_float3x3) -> [Double] {
  (0..<3).flatMap { c in (0..<3).map { r in Double(m[c][r]) } }
}
