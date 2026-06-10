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
        case "setScreenBrightness":
          guard
            let arguments = call.arguments as? [String: Any],
            let level = arguments["level"] as? Double
          else {
            result(FlutterError(
              code: "invalid_arguments",
              message: "level is required",
              details: nil
            ))
            return
          }
          self?.setScreenBrightness(level: level, result: result)
        case "getScreenBrightness":
          result(self?.screenBrightnessStatus() ?? [
            "ok": true,
            "level": UIScreen.main.brightness,
            "usesSystemDefault": false
          ])
        case "setMediaVolume":
          guard
            let arguments = call.arguments as? [String: Any],
            let level = arguments["level"] as? Double
          else {
            result(FlutterError(
              code: "invalid_arguments",
              message: "level is required",
              details: nil
            ))
            return
          }
          self?.setMediaVolume(level: level, result: result)
        case "getMediaVolume":
          result(self?.mediaVolumeStatus() ?? [
            "ok": true,
            "level": AVAudioSession.sharedInstance().outputVolume,
            "stream": "output",
            "canSet": false
          ])
        case "getAppInfo":
          result(self?.appInfo() ?? [
            "ok": false,
            "error": "app_info_unavailable"
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

  private func setScreenBrightness(level: Double, result: FlutterResult) {
    guard level >= 0.0 && level <= 1.0 else {
      result(FlutterError(
        code: "invalid_brightness_level",
        message: "level must be between 0 and 1",
        details: nil
      ))
      return
    }
    UIScreen.main.brightness = CGFloat(level)
    result(screenBrightnessStatus())
  }

  private func screenBrightnessStatus() -> [String: Any] {
    return [
      "ok": true,
      "level": Double(UIScreen.main.brightness),
      "usesSystemDefault": false
    ]
  }

  private func setMediaVolume(level: Double, result: FlutterResult) {
    guard level >= 0.0 && level <= 1.0 else {
      result(FlutterError(
        code: "invalid_volume_level",
        message: "level must be between 0 and 1",
        details: nil
      ))
      return
    }
    var status = mediaVolumeStatus()
    status["ok"] = false
    status["error"] = "unsupported_on_ios"
    status["userMessage"] = "iOS 不允许 App 通过公开 API 静默设置系统输出音量，请使用设备音量键调整。"
    result(status)
  }

  private func mediaVolumeStatus() -> [String: Any] {
    return [
      "ok": true,
      "level": Double(AVAudioSession.sharedInstance().outputVolume),
      "stream": "output",
      "canSet": false
    ]
  }

  private func appInfo() -> [String: Any] {
    let bundle = Bundle.main
    let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "Phone Agent"
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return [
      "ok": true,
      "platform": "ios",
      "appName": appName,
      "packageName": bundle.bundleIdentifier ?? "",
      "bundleId": bundle.bundleIdentifier ?? "",
      "version": version,
      "buildNumber": buildNumber
    ]
  }
}
