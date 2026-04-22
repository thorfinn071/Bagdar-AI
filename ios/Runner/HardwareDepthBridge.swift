import ARKit
import Flutter
import Foundation

final class HardwareDepthBridge: NSObject, FlutterStreamHandler, ARSessionDelegate {
  private var mapSize: Int
  private var eventSink: FlutterEventSink?
  private var session: ARSession?
  private var lastTimestamp: TimeInterval = 0
  private var isRunning = false

  init(mapSize: Int = 256) {
    self.mapSize = mapSize
    super.init()
  }

  static func isSupported() -> Bool {
    guard ARWorldTrackingConfiguration.isSupported else { return false }
    if #available(iOS 13.4, *) {
      return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }
    return false
  }

  func startSession(mapSize: Int) -> Bool {
    if isRunning { return true }
    guard HardwareDepthBridge.isSupported() else { return false }
    self.mapSize = mapSize

    let session = ARSession()
    session.delegate = self

    let configuration = ARWorldTrackingConfiguration()
    guard ARWorldTrackingConfiguration.isSupported else { return false }

    if #available(iOS 13.4, *) {
      if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
        configuration.frameSemantics = .smoothedSceneDepth
      } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
        configuration.frameSemantics = .sceneDepth
      } else {
        return false
      }
    } else {
      return false
    }

    configuration.worldAlignment = .gravity
    configuration.planeDetection = []

    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

    self.session = session
    lastTimestamp = 0
    isRunning = true
    return true
  }

  func stopSession() {
    isRunning = false
    session?.pause()
    session?.delegate = nil
    session = nil
    lastTimestamp = 0
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard isRunning else { return }
    guard #available(iOS 13.4, *) else { return }

    let depthFrame = frame.smoothedSceneDepth ?? frame.sceneDepth
    guard let depthFrame else { return }

    let timestamp = frame.timestamp
    guard timestamp != lastTimestamp else { return }
    lastTimestamp = timestamp

    let values = normalizeDepthMap(depthFrame.depthMap)
    let data = values.withUnsafeBytes { Data($0) }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.eventSink?(FlutterStandardTypedData(bytes: data))
    }
  }

  private func normalizeDepthMap(_ depthMap: CVPixelBuffer) -> [Float] {
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let srcWidth = CVPixelBufferGetWidth(depthMap)
    let srcHeight = CVPixelBufferGetHeight(depthMap)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
      return Array(repeating: 0, count: mapSize * mapSize)
    }

    let rowStride = bytesPerRow / MemoryLayout<Float>.stride
    let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
    var values = Array(repeating: Float(0), count: mapSize * mapSize)

    for y in 0..<mapSize {
      let srcY = Int((Float(y) / Float(max(mapSize - 1, 1))) * Float(max(srcHeight - 1, 0)))
        .clamped(to: 0...(srcHeight - 1))
      let rowBase = srcY * rowStride
      for x in 0..<mapSize {
        let srcX = Int((Float(x) / Float(max(mapSize - 1, 1))) * Float(max(srcWidth - 1, 0)))
          .clamped(to: 0...(srcWidth - 1))
        let depthMeters = floatPointer[rowBase + srcX]
        values[y * mapSize + x] = depthMeters.isFinite && depthMeters > 0 ? depthMeters : 0
      }
    }

    return values
  }
}

private extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
