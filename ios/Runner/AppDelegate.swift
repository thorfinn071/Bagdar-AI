import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var hardwareDepthBridge: HardwareDepthBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let bridge = HardwareDepthBridge()
    hardwareDepthBridge = bridge

    let methodChannel = FlutterMethodChannel(
      name: "bagdar/hardware_depth",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak bridge] call, result in
      guard let bridge else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "isSupported":
        result(HardwareDepthBridge.isSupported())
      case "startSession":
        let mapSize = (call.arguments as? [String: Any])?["mapSize"] as? Int ?? 256
        result(bridge.startSession(mapSize: mapSize))
      case "stopSession":
        bridge.stopSession()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: "bagdar/hardware_depth_frames",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(bridge)
  }
}
