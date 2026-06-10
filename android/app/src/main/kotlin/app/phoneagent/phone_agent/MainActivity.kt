package app.phoneagent.phone_agent

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
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
}
