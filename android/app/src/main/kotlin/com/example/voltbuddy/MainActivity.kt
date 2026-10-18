package com.example.voltbuddy

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.File

class MainActivity : FlutterActivity() {
    private val batteryChannel = "com.example.voltbuddy/battery"

    companion object {
        private const val TAG = "VoltBuddy.MainActivity"
        private const val NOTIFICATION_PERMISSION_CODE = 101
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatterySnapshot" -> result.success(getBatterySnapshot())
                    "getAndClearNativeRecords" -> result.success(getAndClearNativeRecords())
                    "getDeviceInfo" -> result.success(getDeviceInfo())
                    "startBatteryService" -> {
                        startVoltBatteryService()
                        result.success(true)
                    }
                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryOptimizationExemption()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Start 24/7 Foreground Battery Service on app launch
        startVoltBatteryService()

        // Request notification permission on Android 13+ (API 33+)
        requestNotificationPermissionIfNeeded()
    }

    private fun startVoltBatteryService() {
        try {
            val serviceIntent = Intent(this, VoltBatteryService::class.java)
            ContextCompat.startForegroundService(this, serviceIntent)
            Log.d(TAG, "VoltBatteryService started successfully from MainActivity")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VoltBatteryService: ${e.message}", e)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_CODE
                )
            }
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not open direct battery optimization intent, opening general settings: ${e.message}")
                try {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    startActivity(intent)
                } catch (_: Exception) {}
            }
        }
    }

    /**
     * Reads all records written by [VoltBatteryService], returns them as a List<Map>,
     * and clears the file.
     */
    private fun getAndClearNativeRecords(): List<Map<String, Any?>> {
        val file = File(filesDir, VoltBatteryService.RECORDS_FILE)
        if (!file.exists()) return emptyList()

        val records = mutableListOf<Map<String, Any?>>()

        synchronized(VoltBatteryService.RECORDS_FILE) {
            try {
                val array = JSONArray(file.readText())
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val map = mutableMapOf<String, Any?>()
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        map[key] = obj.opt(key)
                    }
                    records.add(map)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading records file: ${e.message}")
            }

            // Clear the file after reading
            try {
                file.delete()
            } catch (_: Exception) {}
        }

        Log.d(TAG, "getAndClearNativeRecords returning ${records.size} records to Dart")
        return records
    }

    private fun getBatterySnapshot(): Map<String, Any?> {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryManager = getSystemService(BATTERY_SERVICE) as BatteryManager

        val rawLevel = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val level = if (rawLevel >= 0 && scale > 0) {
            ((rawLevel * 100.0f) / scale).toInt()
        } else {
            batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        }

        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val isPlugged = plugged != 0
        val state = when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING ->
                if (isPlugged) "connectedNotCharging" else "discharging"
            BatteryManager.BATTERY_STATUS_UNKNOWN -> "unknown"
            else -> "unknown"
        }

        val pluggedSource = when {
            plugged and BatteryManager.BATTERY_PLUGGED_AC != 0 -> "ac"
            plugged and BatteryManager.BATTERY_PLUGGED_USB != 0 -> "usb"
            plugged and BatteryManager.BATTERY_PLUGGED_WIRELESS != 0 -> "wireless"
            plugged and BatteryManager.BATTERY_PLUGGED_DOCK != 0 -> "dock"
            else -> "none"
        }

        return mapOf(
            "level" to level.coerceIn(0, 100),
            "state" to state,
            "isPlugged" to isPlugged,
            "pluggedSource" to pluggedSource,
            "temperatureTenthsC" to (intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1),
            "voltageMv" to (intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1)
        )
    }

    /**
     * Returns device hardware and software info using [android.os.Build].
     */
    private fun getDeviceInfo(): Map<String, Any?> {
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "brand" to Build.BRAND,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "hardware" to Build.HARDWARE,
            "display" to Build.DISPLAY
        )
    }
}
