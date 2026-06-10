import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "phone_agent/native_capabilities"
  private var flashlightEnabled = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "setFlashlight":
          guard
            let arguments = call.arguments as? [String: Any],
            let enabled = arguments["enabled"] as? Bool
          else {
            result(FlutterError(
              code: "invalid_arguments",
              message: "enabled is required",
              details: nil
            ))
            return
          }
          self?.setFlashlight(enabled: enabled, result: result)
        case "getFlashlightStatus":
          result(self?.flashlightStatus() ?? [
            "ok": true,
            "available": false,
            "enabled": false
          ])
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setFlashlight(enabled: Bool, result: FlutterResult) {
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
      result(FlutterError(
        code: "flashlight_unavailable",
        message: "This device has no available flashlight.",
        details: nil
      ))
      return
    }
    do {
      try device.lockForConfiguration()
      defer {
        device.unlockForConfiguration()
      }
      if enabled {
        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      } else {
        device.torchMode = .off
      }
      flashlightEnabled = enabled
      result(flashlightStatus(available: true))
    } catch {
      result(FlutterError(
        code: "flashlight_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func flashlightStatus(available: Bool? = nil) -> [String: Any] {
    let isAvailable = available ?? (AVCaptureDevice.default(for: .video)?.hasTorch ?? false)
    return [
      "ok": true,
      "available": isAvailable,
      "enabled": isAvailable && flashlightEnabled
    ]
  }
}
