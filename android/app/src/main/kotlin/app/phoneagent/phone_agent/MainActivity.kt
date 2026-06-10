package app.phoneagent.phone_agent

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "phone_agent/native_capabilities"
    private var flashlightEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setFlashlight" -> {
                        val enabled = call.argument<Boolean>("enabled")
                        if (enabled == null) {
                            result.error("invalid_arguments", "enabled is required", null)
                            return@setMethodCallHandler
                        }
                        setFlashlight(enabled, result)
                    }
                    "getFlashlightStatus" -> {
                        try {
                            result.success(flashlightStatus())
                        } catch (error: Exception) {
                            result.error("flashlight_failed", error.message, null)
                        }
                    }
                    "setScreenBrightness" -> {
                        val level = call.argument<Double>("level")
                        if (level == null) {
                            result.error("invalid_arguments", "level is required", null)
                            return@setMethodCallHandler
                        }
                        setScreenBrightness(level, result)
                    }
                    "getScreenBrightness" -> result.success(screenBrightnessStatus())
                    "setMediaVolume" -> {
                        val level = call.argument<Double>("level")
                        if (level == null) {
                            result.error("invalid_arguments", "level is required", null)
                            return@setMethodCallHandler
                        }
                        setMediaVolume(level, result)
                    }
                    "getMediaVolume" -> result.success(mediaVolumeStatus())
                    "getAppInfo" -> {
                        try {
                            result.success(appInfo())
                        } catch (error: Exception) {
                            result.error("app_info_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setFlashlight(enabled: Boolean, result: MethodChannel.Result) {
        val cameraId = flashlightCameraId()
        if (cameraId == null) {
            result.error("flashlight_unavailable", "This device has no available flashlight.", null)
            return
        }
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraManager.setTorchMode(cameraId, enabled)
            flashlightEnabled = enabled
            result.success(flashlightStatus(available = true))
        } catch (error: Exception) {
            result.error("flashlight_failed", error.message, null)
        }
    }

    private fun flashlightStatus(available: Boolean? = null): Map<String, Any> {
        val isAvailable = available ?: (flashlightCameraId() != null)
        return mapOf(
            "ok" to true,
            "available" to isAvailable,
            "enabled" to (isAvailable && flashlightEnabled),
        )
    }

    private fun flashlightCameraId(): String? {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        var fallback: String? = null
        for (cameraId in cameraManager.cameraIdList) {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val hasFlash =
                characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            if (!hasFlash) {
                continue
            }
            fallback = fallback ?: cameraId
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                return cameraId
            }
        }
        return fallback
    }

    private fun setScreenBrightness(level: Double, result: MethodChannel.Result) {
        if (level < 0.0 || level > 1.0) {
            result.error("invalid_brightness_level", "level must be between 0 and 1", null)
            return
        }
        val attributes = window.attributes
        attributes.screenBrightness = level.toFloat()
        window.attributes = attributes
        result.success(screenBrightnessStatus(overrideLevel = level))
    }

    private fun screenBrightnessStatus(overrideLevel: Double? = null): Map<String, Any> {
        val windowLevel = overrideLevel ?: window.attributes.screenBrightness.toDouble()
        val usesSystemDefault = windowLevel < 0.0
        val systemLevel = try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (error: Exception) {
            null
        }
        val effectiveLevel = if (usesSystemDefault) systemLevel else windowLevel
        val result = mutableMapOf<String, Any>(
            "ok" to true,
            "usesSystemDefault" to usesSystemDefault,
        )
        if (effectiveLevel != null) {
            result["level"] = effectiveLevel.coerceIn(0.0, 1.0)
        }
        if (systemLevel != null) {
            result["systemLevel"] = systemLevel.coerceIn(0.0, 1.0)
        }
        return result
    }

    private fun setMediaVolume(level: Double, result: MethodChannel.Result) {
        if (level < 0.0 || level > 1.0) {
            result.error("invalid_volume_level", "level must be between 0 and 1", null)
            return
        }
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = (level * maxVolume).toInt().coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        result.success(mediaVolumeStatus())
    }

    private fun mediaVolumeStatus(): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val level = if (maxVolume <= 0) 0.0 else currentVolume.toDouble() / maxVolume.toDouble()
        return mapOf(
            "ok" to true,
            "level" to level.coerceIn(0.0, 1.0),
            "currentVolume" to currentVolume,
            "maxVolume" to maxVolume,
            "stream" to "music",
            "canSet" to true,
        )
    }

    private fun appInfo(): Map<String, Any> {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
        val applicationInfo = packageInfo.applicationInfo ?: this.applicationInfo
        val appName = packageManager.getApplicationLabel(applicationInfo).toString()
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
        return mapOf(
            "ok" to true,
            "platform" to "android",
            "appName" to appName,
            "packageName" to packageName,
            "version" to (packageInfo.versionName ?: ""),
            "buildNumber" to versionCode.toString(),
            "versionCode" to versionCode,
        )
    }
}
