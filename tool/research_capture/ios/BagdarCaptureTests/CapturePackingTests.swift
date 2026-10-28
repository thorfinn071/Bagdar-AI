import XCTest
@testable import BagdarCapture

final class CapturePackingTests: XCTestCase {
  func testNewestOnlyAdmissionAndStop() {
    var queue = NewestOnlySlot<Int>()
    XCTAssertEqual(queue.offer(1).start, 1)
    XCTAssertFalse(queue.offer(2).replaced)
    XCTAssertTrue(queue.offer(3).replaced)
    XCTAssertEqual(queue.complete(), 3)
    XCTAssertTrue(queue.active)
    _ = queue.offer(4)
    XCTAssertTrue(queue.discardPending())
    XCTAssertNil(queue.complete())
    XCTAssertFalse(queue.active)
  }

  func testPaddedRowsRemainExact() throws {
    let bytes: [UInt8] = [1, 2, 99, 99, 3, 4, 99, 99]
    let packed = try bytes.withUnsafeBytes { raw in
      try PackedPlane.copyRows(base: raw.baseAddress!, width: 2, height: 2,
                               bytesPerPixel: 1, rowStride: 4)
    }
    XCTAssertEqual(Array(packed.data), [1, 2, 3, 4])
    XCTAssertEqual(packed.sourceRowStride, 4)
  }

  func testShortStrideRejected() {
    let bytes: [UInt8] = [1, 2]
    XCTAssertThrowsError(try bytes.withUnsafeBytes { raw in
      try PackedPlane.copyRows(base: raw.baseAddress!, width: 2, height: 1,
                               bytesPerPixel: 4, rowStride: 2)
    })
  }

  func testValidityDoesNotReplaceInvalidDepth() {
    let values: [Float] = [1, 0, -.infinity, .nan, -1]
    let data = values.withUnsafeBytes { Data($0) }
    let plane = PackedPlane(width: 5, height: 1, bytesPerPixel: 4, sourceRowStride: 20, data: data)
    XCTAssertEqual(Array(PackedPlane.validity(depth: plane).data), [1, 0, 0, 0, 0])
    XCTAssertEqual(plane.data, data)
  }

  func testZIPRoundTripHeaderAndCRC() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("capture")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("123456789".utf8).write(to: folder.appendingPathComponent("sample.bin"))
    let zip = root.appendingPathComponent("capture.zip")
    try StoredZip.create(folder: folder, output: zip)
    let data = try Data(contentsOf: zip)
    XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
    XCTAssertEqual(Array(data[14..<18]), [0x26, 0x39, 0xf4, 0xcb])
    XCTAssertNotNil(data.range(of: Data("123456789".utf8)))
    XCTAssertThrowsError(try StoredZip.create(folder: folder, output: zip))
  }
}
