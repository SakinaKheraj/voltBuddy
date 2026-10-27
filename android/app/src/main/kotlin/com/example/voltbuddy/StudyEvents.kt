package com.example.voltbuddy

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Phase 2 interaction-study events recorded on the native side (even while the
 * Flutter app is closed). Kept in a separate file from
 * [VoltBatteryService.RECORDS_FILE] so the existing charge-session import is
 * unaffected; read and cleared by MainActivity.getAndClearNativeEvents.
 */
object StudyEvents {
    private const val TAG = "VoltBuddy.StudyEvents"
    const val EVENTS_FILE = "voltbuddy_native_events.json"

    fun append(
        context: Context,
        event: String,
        tsMs: Long = System.currentTimeMillis(),
        props: JSONObject.() -> Unit = {}
    ) {
        try {
            // Off in the Google Play build: nothing would ever read the file.
            if (!context.resources.getBoolean(R.bool.study_events_enabled)) return
            val record = JSONObject().apply {
                put("event", event)
                put("ts_ms", tsMs)
                put("app_version", appVersion(context))
                props()
            }
            val file = File(context.filesDir, EVENTS_FILE)
            synchronized(EVENTS_FILE) {
                val array = if (file.exists()) {
                    try { JSONArray(file.readText()) } catch (e: Exception) { JSONArray() }
                } else {
                    JSONArray()
                }
                array.put(record)
                file.writeText(array.toString())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to append study event $event: ${e.message}")
        }
    }

    private var cachedVersion: String? = null

    /** Version of the app that recorded the event, e.g. "2.2.1+6" (same format as Dart). */
    private fun appVersion(context: Context): String {
        cachedVersion?.let { return it }
        val version = try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName}+$code"
        } catch (e: Exception) {
            "unknown"
        }
        cachedVersion = version
        return version
    }

    /**
     * Settings that decide whether the study can work on this phone: if
     * notifications are off the 85% notification never appears, and if the app
     * is battery-optimised or restricted the background service can be killed.
     */
    fun deviceStatus(context: Context): Map<String, Any?> {
        val status = mutableMapOf<String, Any?>()
        try {
            status["notifications_enabled"] =
                NotificationManagerCompat.from(context).areNotificationsEnabled()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = context.getSystemService(NotificationManager::class.java)
                    ?.getNotificationChannel(VoltBatteryService.CHANNEL_ID)
                status["monitor_channel_enabled"] =
                    channel?.let { it.importance != NotificationManager.IMPORTANCE_NONE }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                status["battery_unrestricted"] =
                    pm.isIgnoringBatteryOptimizations(context.packageName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val am = context.getSystemService(ActivityManager::class.java)
                status["background_restricted"] = am?.isBackgroundRestricted
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read device status: ${e.message}")
        }
        return status
    }

    fun JSONObject.putAll(values: Map<String, Any?>) {
        for ((key, value) in values) put(key, value ?: JSONObject.NULL)
    }
}
