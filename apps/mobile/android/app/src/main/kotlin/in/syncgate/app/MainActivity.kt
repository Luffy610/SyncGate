package `in`.syncgate.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and answers the `in.syncgate.app/platform` channel used
 * by `sg_platform`: screen pinning (lock task mode) for the gate kiosk, and the
 * hardware check from the setup wizard. It is a FlutterFragmentActivity because
 * the biometric prompt (local_auth) needs one.
 */
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPinned" -> result.success(isPinned())
                    "startPinning" -> {
                        // Shows the system "Screen pinned" prompt; the user confirms it.
                        startLockTask()
                        result.success(null)
                    }
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                        result.success(null)
                    }
                    "deviceInfo" -> result.success(deviceInfo())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isPinned(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }

    /** Front-camera megapixels, total memory in GB, and the Android version. */
    private fun deviceInfo(): Map<String, Any> {
        val memory = ActivityManager.MemoryInfo()
        (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        return mapOf(
            "cameraMegapixels" to frontCameraMegapixels(),
            // totalMem reports slightly under the marketing figure, so round up.
            "memoryGb" to Math.ceil(memory.totalMem / BYTES_PER_GB).toInt(),
            "system" to "Android ${Build.VERSION.RELEASE}",
        )
    }

    private fun frontCameraMegapixels(): Int {
        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        for (id in manager.cameraIdList) {
            val characteristics = manager.getCameraCharacteristics(id)
            if (characteristics.get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_FRONT
            ) {
                val size = characteristics.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
                if (size != null) {
                    return Math.round(size.width.toLong() * size.height / 1_000_000.0).toInt()
                }
            }
        }
        return 0
    }

    private companion object {
        const val CHANNEL = "in.syncgate.app/platform"
        const val BYTES_PER_GB = 1024.0 * 1024.0 * 1024.0
    }
}
