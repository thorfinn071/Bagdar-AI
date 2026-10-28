import ARKit
import CoreVideo
import Darwin
import Foundation
import UIKit

final class CaptureRecorder: NSObject, ARSessionDelegate {
  static let version = "1.0.0"
  static let poseConvention = "arkit_world_right_up_negative_z_forward_column_major"
  static let maxBytes = 512 * 1024 * 1024
  static let limits: [String: Any] = ["maxFrames": 300, "maxDurationNs": 10_000_000_000,
                                    "maxPayloadBytes": maxBytes]
  var onStatus: ((String, URL?, Bool) -> Void)?
  private let stateQueue = DispatchQueue(label: "bagdar.capture.state")
  private let writerQueue = DispatchQueue(label: "bagdar.capture.writer", qos: .utility)
  private var session: ARSession?
  private var timer: DispatchSourceTimer?
  private var slot = NewestOnlySlot<Incoming>()
  private var recording = false, stopping = false
  private var folder: URL?
  private var rowsHandle: FileHandle?
  private var recordingID = "", orientation = "portrait"
  private var started: UInt64 = 0, received = 0, saved = 0, payloadBytes = 0
  private var drops: [String: Int] = [:]
  private var finalStatus = "complete", stopReason = "user_stop"
  private var lastSourceTimestamp: TimeInterval = -1

  private struct Incoming {
    let frame: ARFrame
    let frameID: Int
    let received: UInt64
    let orientation: String
  }

  func setOrientation(_ value: String) {
    stateQueue.async { self.orientation = value }
  }

  func start(consentConfirmed: Bool) {
    stateQueue.async {
      guard !self.recording && !self.stopping && !self.slot.active else { return }
      guard consentConfirmed, ARWorldTrackingConfiguration.isSupported,
            ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
        self.notify("ARKit sceneDepth unavailable, or consent not confirmed.")
        return
      }
      do {
        self.recordingID = "capture-" + UUID().uuidString.lowercased()
        let documents = try FileManager.default.url(for: .documentDirectory,
          in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = documents.appendingPathComponent(self.recordingID, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw CaptureFailure.invalidBuffer }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("payloads"),
                                                withIntermediateDirectories: true)
        var privacy = URLResourceValues()
        privacy.isExcludedFromBackup = true
        try folder.setResourceValues(privacy)
        let rows = folder.appendingPathComponent("frames.jsonl")
        guard FileManager.default.createFile(atPath: rows.path, contents: nil) else {
          throw CaptureFailure.invalidBuffer
        }
        self.rowsHandle = try FileHandle(forWritingTo: rows)
        self.folder = folder
        self.started = DispatchTime.now().uptimeNanoseconds
        self.received = 0; self.saved = 0; self.payloadBytes = 0; self.drops = [:]
        self.lastSourceTimestamp = -1; self.slot = NewestOnlySlot<Incoming>()
        self.finalStatus = "complete"; self.stopReason = "user_stop"
        self.recording = true; self.stopping = false
        let session = ARSession()
        session.delegate = self
        session.delegateQueue = self.stateQueue
        self.session = session
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        config.worldAlignment = .gravity
        config.planeDetection = []
        config.sceneReconstruction = []
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        let timer = DispatchSource.makeTimerSource(queue: self.stateQueue)
        timer.schedule(deadline: .now() + 10)
        timer.setEventHandler { [weak self] in self?.stopOnQueue(reason: "duration_limit") }
        self.timer = timer
        timer.resume()
        self.notify("Recording " + self.recordingID, ready: false)
      } catch {
        self.recording = false
        self.session?.pause(); self.session = nil
        try? self.rowsHandle?.close(); self.rowsHandle = nil
        self.notify("Start failed: \(error)")
      }
    }
  }

  func stop(reason: String = "user_stop", failed: Bool = false) {
    stateQueue.async { self.stopOnQueue(reason: reason, failed: failed) }
  }

  private func stopOnQueue(reason: String, failed: Bool = false) {
    guard recording || stopping else { return }
    if failed { finalStatus = "failed" }
    guard !stopping else { return }
    recording = false; stopping = true; stopReason = reason
    timer?.cancel(); timer = nil
    session?.pause(); session?.delegate = nil; session = nil
    if slot.discardPending() { drops["stopped_pending", default: 0] += 1 }
    if !slot.active { finalize() }
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard recording else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    guard now - started < 10_000_000_000 else {
      stopOnQueue(reason: "duration_limit"); return
    }
    guard frame.timestamp.isFinite && frame.timestamp >= 0 && frame.timestamp > lastSourceTimestamp else {
      stopOnQueue(reason: "source_clock_rollback_or_duplicate", failed: true); return
    }
    lastSourceTimestamp = frame.timestamp
    received += 1
    let incoming = Incoming(frame: frame, frameID: received, received: now, orientation: orientation)
    let offered = slot.offer(incoming)
    if offered.replaced { drops["superseded_pending", default: 0] += 1 }
    if let next = offered.start { write(next) }
  }

  func sessionWasInterrupted(_ session: ARSession) {
    stopOnQueue(reason: "session_interrupted", failed: true)
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    stopOnQueue(reason: "session_error: \(error)", failed: true)
  }

  private func write(_ incoming: Incoming) {
    guard let folder else { return }
    let index = saved, bytesSoFar = payloadBytes, id = recordingID
    writerQueue.async {
      let result: Result<([String: Any], Int), Error> = Result {
        try autoreleasepool {
          try self.pack(incoming, folder: folder, index: index, bytesSoFar: bytesSoFar, sessionID: id)
        }
      }
      self.stateQueue.async {
        switch result {
        case .success(let (row, bytes)):
          do {
            var line = try jsonData(row); line.append(0x0a)
            try self.rowsHandle?.write(contentsOf: line)
            self.saved += 1; self.payloadBytes += bytes
          } catch {
            self.drops["write_error", default: 0] += 1
            self.stopOnQueue(reason: "metadata_write_error", failed: true)
          }
        case .failure(let error):
          self.drops["pack_or_write_rejected", default: 0] += 1
          let limit: Bool
          if let failure = error as? CaptureFailure, case .payloadLimit = failure {
            limit = true
          } else { limit = false }
          self.stopOnQueue(reason: limit ? "payload_limit" : "\(error)", failed: !limit)
        }
        if self.saved >= 300 { self.stopOnQueue(reason: "frame_limit") }
        if self.payloadBytes >= Self.maxBytes { self.stopOnQueue(reason: "payload_limit") }
        if let next = self.slot.complete(), self.recording {
          self.write(next)
        } else if self.stopping {
          self.finalize()
        }
      }
    }
  }

  private func pack(_ incoming: Incoming, folder: URL, index: Int, bytesSoFar: Int,
                    sessionID: String) throws -> ([String: Any], Int) {
    let frame = incoming.frame
    let rgb = frame.capturedImage
    let pixelFormat = CVPixelBufferGetPixelFormatType(rgb)
    guard (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
          CVPixelBufferGetPlaneCount(rgb) == 2 else { throw CaptureFailure.unsupportedBuffer }
    var images: [(String, String, Int, Int, [PackedPlane])] = []
    images.append(("rgb", "apple_ycbcr_biplanar_native", CVPixelBufferGetWidth(rgb),
                   CVPixelBufferGetHeight(rgb), [try PackedPlane.copy(rgb, plane: 0, bytesPerPixel: 1),
                                                try PackedPlane.copy(rgb, plane: 1, bytesPerPixel: 2)]))
    if let depth = frame.sceneDepth {
      guard CVPixelBufferGetPixelFormatType(depth.depthMap) == kCVPixelFormatType_DepthFloat32 else {
        throw CaptureFailure.unsupportedBuffer
      }
      let plane = try PackedPlane.copy(depth.depthMap, plane: nil, bytesPerPixel: 4)
      images.append(("depth", "float32_little_endian_camera_axis_metres_sdk_estimate",
                     plane.width, plane.height, [plane]))
      images.append(("validity", "uint8_finite_positive_depth_0_or_1",
                     plane.width, plane.height, [PackedPlane.validity(depth: plane)]))
      if let confidence = depth.confidenceMap {
        guard CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else {
          throw CaptureFailure.unsupportedBuffer
        }
        let conf = try PackedPlane.copy(confidence, plane: nil, bytesPerPixel: 1)
        guard conf.width == plane.width && conf.height == plane.height else { throw CaptureFailure.invalidBuffer }
        images.append(("confidence", "uint8_arkit_low0_medium1_high2", conf.width, conf.height, [conf]))
      }
    }
    let size = images.reduce(0) { $0 + $1.4.reduce(0) { $0 + $1.data.count } }
    guard bytesSoFar + size <= Self.maxBytes else { throw CaptureFailure.payloadLimit }
    let sourceUs = Int64((frame.timestamp * 1_000_000).rounded(.down))
    var row: [String: Any] = ["frameIndex": index, "frameId": incoming.frameID,
      "sessionId": sessionID, "sessionGeneration": 1,
      "sourceTimestampSeconds": frame.timestamp,
      "sourceTimestampBits": String(format: "%016llx", frame.timestamp.bitPattern),
      "sourceTimestampUs": sourceUs, "receivedUptimeNs": incoming.received,
      "poseConvention": Self.poseConvention, "cameraTransform": matrixValues(frame.camera.transform),
      "intrinsics": matrixValues(frame.camera.intrinsics),
      "imageResolution": [CVPixelBufferGetWidth(rgb), CVPixelBufferGetHeight(rgb)],
      "orientation": incoming.orientation, "trackingState": "notAvailable",
      "trackingReason": "notAvailable", "rgb": NSNull(), "depth": NSNull(),
      "confidence": NSNull(), "validity": NSNull(), "rgbPixelFormat": pixelFormat,
      "rgbColorRange": pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? "full" : "video",
      "rgbYCbCrMatrix": CVBufferGetAttachment(rgb, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue()
        as? String ?? "unspecified"]
    switch frame.camera.trackingState {
    case .normal: row["trackingState"] = "normal"; row["trackingReason"] = "normal"
    case .notAvailable: break
    case .limited(let reason): row["trackingState"] = "limited"; row["trackingReason"] = String(describing: reason)
    }
    for (kind, encoding, width, height, planes) in images {
      var descriptors: [[String: Any]] = []
      for (planeIndex, plane) in planes.enumerated() {
        let path = "payloads/\(incoming.frameID)-\(kind)-\(planeIndex).bin"
        try plane.data.write(to: folder.appendingPathComponent(path), options: .withoutOverwriting)
        descriptors.append(["path": path, "sha256": digest(plane.data), "byteLength": plane.data.count,
          "width": plane.width, "height": plane.height, "bytesPerPixel": plane.bytesPerPixel,
          "sourceRowStride": plane.sourceRowStride, "packing": "row_major_samples_without_padding"])
      }
      row[kind] = ["frameId": incoming.frameID, "sourceTimestampUs": sourceUs,
                   "encoding": encoding, "width": width, "height": height, "planes": descriptors]
    }
    row["payloadsReadyUptimeNs"] = DispatchTime.now().uptimeNanoseconds
    return (row, size)
  }

  private func finalize() {
    guard stopping, !slot.active, let folder else { return }
    defer { stopping = false }
    do {
      try rowsHandle?.synchronize(); try rowsHandle?.close(); rowsHandle = nil
      let rows = try Data(contentsOf: folder.appendingPathComponent("frames.jsonl"))
      if saved == 0 { finalStatus = "failed" }
      var manifest: [String: Any] = ["format": "bagdar-arkit-capture-v1", "schemaVersion": 1,
        "recordingId": recordingID, "sessionId": recordingID, "source": "recorded",
        "consentConfirmed": true, "deviceModel": Self.machineModel(),
        "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        "recorderVersion": Self.version,
        "recorderSourceId": Bundle.main.object(forInfoDictionaryKey: "BagdarCaptureSourceId") as? String ?? "unfrozen-development",
        "cameraOwner": "native_arkit_only", "flutterEngineCreated": false,
        "depthMode": "ARKIT_SCENE_DEPTH_ESTIMATE", "poseConvention": Self.poseConvention,
        "sourceTimestampDomain": "arkit_frame_seconds_unverified", "receiveTimestampDomain": "dispatch_uptime_ns",
        "startedUptimeNs": started, "stoppedUptimeNs": DispatchTime.now().uptimeNanoseconds,
        "recordingStatus": finalStatus, "stopReason": stopReason, "frameCount": saved,
        "receivedFrames": received, "droppedFrames": drops, "payloadBytes": payloadBytes,
        "frames": ["path": "frames.jsonl", "sha256": digest(rows), "byteLength": rows.count]]
      for (key, value) in Self.limits { manifest[key] = value }
      for key in ["physicalAlignmentValidated", "metricErrorBoundsValidated", "floorReferenceValidated",
                  "clockBindingValidated", "bodyVolumeCoverageEstablished", "safetyReplayReady",
                  "ordinaryCameraWired", "promotionAllowed"] { manifest[key] = false }
      try jsonData(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
      notify("\(recordingID): \(finalStatus), \(saved) saved, \(received-saved) dropped. \(stopReason)", folder: folder)
    } catch {
      try? rowsHandle?.close(); rowsHandle = nil
      notify("Partial recording retained: \(error)", folder: folder)
    }
  }

  private func notify(_ message: String, folder: URL? = nil, ready: Bool = true) {
    DispatchQueue.main.async { self.onStatus?(message, folder, ready) }
  }

  private static func machineModel() -> String {
    var system = utsname(); uname(&system)
    let capacity = MemoryLayout.size(ofValue: system.machine)
    return withUnsafePointer(to: &system.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
        String(cString: $0)
      }
    }
  }
}
