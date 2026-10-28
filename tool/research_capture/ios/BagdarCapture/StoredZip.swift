import Foundation

// Standard ZIP with stored entries, CRC32 and bounded streaming. No third-party
// dependency; paths are relative to the recorder's own immutable directory.
enum StoredZip {
  private static let crcTable: [UInt32] = (0..<256).map { byte in
    var value = UInt32(byte)
    for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0) }
    return value
  }
  private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
  }
  private static func crc(_ data: Data, previous: UInt32) -> UInt32 {
    var value = previous
    for byte in data {
      value = crcTable[Int((value ^ UInt32(byte)) & 0xff)] ^ (value >> 8)
    }
    return value
  }
  static func create(folder: URL, output: URL) throws {
    let manager = FileManager.default
    guard !manager.fileExists(atPath: output.path),
          let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
      throw CaptureFailure.invalidBuffer
    }
    var files: [URL] = []
    for case let file as URL in enumerator {
      let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard properties.isSymbolicLink != true else { throw CaptureFailure.invalidBuffer }
      if properties.isRegularFile == true { files.append(file) }
    }
    guard files.count <= 2500 else { throw CaptureFailure.invalidBuffer }
    guard manager.createFile(atPath: output.path, contents: nil) else { throw CaptureFailure.invalidBuffer }
    var privateOutput = output
    var privacy = URLResourceValues()
    privacy.isExcludedFromBackup = true
    try privateOutput.setResourceValues(privacy)
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    var central = Data(), offset: UInt32 = 0
    for file in files.sorted(by: { $0.path < $1.path }) {
      guard file.path.hasPrefix(folder.path + "/") else { throw CaptureFailure.invalidBuffer }
      let name = Data(file.path.dropFirst(folder.path.count + 1).utf8)
      let input = try FileHandle(forReadingFrom: file)
      defer { try? input.close() }
      var checksum: UInt32 = 0xffffffff, length: UInt32 = 0
      while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
        checksum = crc(data, previous: checksum)
        guard UInt64(length) + UInt64(data.count) <= UInt64(CaptureRecorder.maxBytes) else {
          throw CaptureFailure.payloadLimit
        }
        length += UInt32(data.count)
      }
      checksum ^= 0xffffffff
      var local = Data()
      append(UInt32(0x04034b50), to: &local); append(UInt16(20), to: &local)
      for v in [UInt16(0x0800), 0, 0, 0] { append(v, to: &local) }
      append(checksum, to: &local); append(length, to: &local); append(length, to: &local)
      append(UInt16(name.count), to: &local); append(UInt16(0), to: &local); local.append(name)
      try handle.write(contentsOf: local)
      try input.seek(toOffset: 0)
      while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try handle.write(contentsOf: data) }
      var entry = Data()
      append(UInt32(0x02014b50), to: &entry); append(UInt16(20), to: &entry); append(UInt16(20), to: &entry)
      for v in [UInt16(0x0800), 0, 0, 0] { append(v, to: &entry) }
      append(checksum, to: &entry); append(length, to: &entry); append(length, to: &entry)
      append(UInt16(name.count), to: &entry)
      for _ in 0..<4 { append(UInt16(0), to: &entry) }
      append(UInt32(0), to: &entry); append(offset, to: &entry); entry.append(name)
      central.append(entry); offset += UInt32(local.count) + length
    }
    try handle.write(contentsOf: central)
    var end = Data(); append(UInt32(0x06054b50), to: &end)
    append(UInt16(0), to: &end); append(UInt16(0), to: &end)
    append(UInt16(files.count), to: &end); append(UInt16(files.count), to: &end)
    append(UInt32(central.count), to: &end); append(offset, to: &end); append(UInt16(0), to: &end)
    try handle.write(contentsOf: end); try handle.synchronize()
  }
}
