package com.example.voltbuddy

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A native Android WorkManager [Worker] that captures a battery snapshot
 * and writes it to the shared JSON file. This is used by [BootReceiver]
 * as a fallback to ensure data collection continues even when the Flutter
 * engine is not running.
 *
 * The flutter_workmanager plugin's own callback dispatcher handles the
 * Dart-side periodic task separately. This native worker acts as a
 * safety net that always works regardless of Flutter engine state.
 */
class BatteryWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    companion object {
        private const val TAG = "VoltBuddy.BatteryWorker"
    }

    override fun doWork(): Result {
        return try {
            val record = captureBatterySnapshot()
            appendRecordToFile(record)
            Log.d(TAG, "Battery snapshot captured: level=${record.optInt("level")}, state=${record.optString("state")}")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to capture battery snapshot", e)
            Result.retry()
        }
    }

    private fun captureBatterySnapshot(): JSONObject {
        val batteryIntent = applicationContext.registerReceiver(
            null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        val batteryManager = applicationContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

        val rawLevel = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val level = if (rawLevel >= 0 && scale > 0) {
            ((rawLevel * 100.0f) / scale).toInt().coerceIn(0, 100)
        } else {
            batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).coerceIn(0, 100)
        }

        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = batteryIntent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
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

        val temperature = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val voltage = batteryIntent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1

        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        val timestamp = isoFormat.format(Date())

        return JSONObject().apply {
            put("timestamp", timestamp)
            put("level", level)
            put("state", state)
            put("isPlugged", isPlugged)
            put("pluggedSource", pluggedSource)
            put("temperatureTenthsC", temperature)
            put("voltageMv", voltage)
            put("event", "periodic_check")
        }
    }

    private fun appendRecordToFile(record: JSONObject) {
        val file = File(applicationContext.filesDir, PowerConnectionReceiver.RECORDS_FILE)

        synchronized(PowerConnectionReceiver.RECORDS_FILE) {
            val array = if (file.exists()) {
                try {
                    JSONArray(file.readText())
                } catch (e: Exception) {
                    JSONArray()
                }
            } else {
                JSONArray()
            }

            array.put(record)
            file.writeText(array.toString())
        }
    }
}
