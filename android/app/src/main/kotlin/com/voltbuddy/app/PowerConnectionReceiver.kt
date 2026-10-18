package com.voltbuddy.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native BroadcastReceiver that captures power-connect and power-disconnect
 * events even when the Flutter app is completely killed.
 *
 * On Android 8.0+ (API 26+), implicit broadcast receivers declared in the
 * manifest for ACTION_POWER_CONNECTED/DISCONNECTED are restricted.
 * Therefore this receiver serves as a belt-and-suspenders approach:
 * - On pre-O devices, it fires directly from the manifest declaration.
 * - On O+ devices, we also schedule OneTimeWorkRequests with charging
 *   constraints from [BootReceiver] to complement this receiver.
 *
 * It writes lightweight JSON records to a shared file that the Dart side
 * imports when the app is next opened (or when a WorkManager task runs).
 */
class PowerConnectionReceiver : BroadcastReceiver() {

    companion object {
        const val RECORDS_FILE = "battery_bg_records.json"
        private const val TAG = "VoltBuddy.PowerRx"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        // Handle power-connected / power-disconnected
        if (action != Intent.ACTION_POWER_CONNECTED &&
            action != Intent.ACTION_POWER_DISCONNECTED
        ) return

        Log.d(TAG, "Power event received: $action")

        try {
            val record = captureBatterySnapshot(context, action)
            appendRecordToFile(context, record)
            Log.d(TAG, "Recorded: level=${record.optInt("level")}, state=${record.optString("state")}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to capture battery snapshot", e)
        }
    }

    private fun captureBatterySnapshot(context: Context, triggerAction: String): JSONObject {
        val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

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

        val event = if (triggerAction == Intent.ACTION_POWER_CONNECTED) "power_connected" else "power_disconnected"

        return JSONObject().apply {
            put("timestamp", timestamp)
            put("level", level)
            put("state", state)
            put("isPlugged", isPlugged)
            put("pluggedSource", pluggedSource)
            put("temperatureTenthsC", temperature)
            put("voltageMv", voltage)
            put("event", event)
        }
    }

    /**
     * Append a record to the JSON array stored in [RECORDS_FILE].
     * Thread-safe via synchronized block on the file path.
     */
    private fun appendRecordToFile(context: Context, record: JSONObject) {
        val file = File(context.filesDir, RECORDS_FILE)

        synchronized(RECORDS_FILE) {
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
