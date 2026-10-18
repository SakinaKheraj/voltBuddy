package com.example.voltbuddy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * VoltBatteryService - Native Android Foreground Service for 24/7 Battery & Charging Tracking.
 *
 * Runs continuously with a low-priority, silent notification.
 * Dynamically registers a BroadcastReceiver for ACTION_BATTERY_CHANGED, ACTION_POWER_CONNECTED,
 * and ACTION_POWER_DISCONNECTED.
 *
 * This ensures that charge sessions (start time/level, end time/level) are recorded
 * in real-time with 0-second latency, even when the Flutter app is completely killed or swiped away.
 */
class VoltBatteryService : Service() {

    companion object {
        private const val TAG = "VoltBuddy.Service"
        const val CHANNEL_ID = "voltbuddy_battery_monitor"
        const val NOTIFICATION_ID = 1001
        const val RECORDS_FILE = "battery_bg_records.json"
        private const val PREFS_NAME = "voltbuddy_battery_prefs"
        private const val PREF_IS_CHARGING = "is_charging"
        private const val PREF_START_PCT = "start_pct"
        private const val PREF_START_DATE = "start_date"
        private const val PREF_START_TIME = "start_time"
        private const val PREF_START_TIMESTAMP = "start_timestamp"
        private const val PREF_PLUGGED_SOURCE = "plugged_source"
    }

    private var batteryReceiver: BroadcastReceiver? = null
    private lateinit var prefs: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "VoltBatteryService onCreate")
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        createNotificationChannel()
        startAsForeground(getInitialNotification())
        registerBatteryReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "VoltBatteryService onStartCommand")
        // Always ensure we are in foreground
        startAsForeground(getInitialNotification())
        // START_STICKY ensures the service restarts if killed by system under severe memory pressure
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "VoltBatteryService onDestroy")
        unregisterBatteryReceiver()
        super.onDestroy()
    }

    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            }
            try {
                startForeground(NOTIFICATION_ID, notification, serviceType)
            } catch (e: Exception) {
                Log.w(TAG, "Failed startForeground with type $serviceType, falling back: ${e.message}")
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VoltBuddy Battery Monitor",
                NotificationManager.IMPORTANCE_LOW // Silent, no sound, no vibration
            ).apply {
                description = "Monitors charging sessions and battery health in real-time"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun getInitialNotification(): Notification {
        return buildNotification("VoltBuddy Battery Guard", "Monitoring battery health actively ⚡")
    }

    private fun buildNotification(title: String, content: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )
        } else null

        val iconRes = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_idle_charging

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateNotification(title: String, content: String) {
        try {
            val notification = buildNotification(title, content)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update notification: ${e.message}")
        }
    }

    private fun registerBatteryReceiver() {
        if (batteryReceiver != null) return

        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                handleBatteryEvent(intent)
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(batteryReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(batteryReceiver, filter)
            }
            Log.d(TAG, "Dynamic BatteryReceiver registered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register BatteryReceiver: ${e.message}", e)
        }
    }

    private fun unregisterBatteryReceiver() {
        batteryReceiver?.let {
            try {
                unregisterReceiver(it)
                Log.d(TAG, "BatteryReceiver unregistered")
            } catch (e: Exception) {
                Log.e(TAG, "Error unregistering receiver: ${e.message}")
            }
            batteryReceiver = null
        }
    }

    private fun handleBatteryEvent(intent: Intent) {
        val action = intent.action ?: return

        // Read battery state from intent
        val rawLevel = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val level = if (rawLevel >= 0 && scale > 0) {
            ((rawLevel * 100.0f) / scale).toInt().coerceIn(0, 100)
        } else {
            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).coerceIn(0, 100)
        }

        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val isPlugged = plugged != 0

        val state = when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING ->
                if (isPlugged) "connectedNotCharging" else "discharging"
            BatteryManager.BATTERY_STATUS_UNKNOWN -> "unknown"
            else -> if (isPlugged) "charging" else "discharging"
        }

        val isChargingNow = isPlugged || state == "charging" || state == "full" || state == "connectedNotCharging"
        val pluggedSource = when {
            plugged and BatteryManager.BATTERY_PLUGGED_AC != 0 -> "AC"
            plugged and BatteryManager.BATTERY_PLUGGED_USB != 0 -> "USB"
            plugged and BatteryManager.BATTERY_PLUGGED_WIRELESS != 0 -> "Wireless"
            plugged and BatteryManager.BATTERY_PLUGGED_DOCK != 0 -> "Dock"
            isChargingNow -> "AC"
            else -> "none"
        }

        val wasCharging = prefs.getBoolean(PREF_IS_CHARGING, false)

        val now = Date()
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)

        val nowIso = isoFormat.format(now)
        val nowDate = dateFormat.format(now)
        val nowTime = timeFormat.format(now)

        Log.d(TAG, "BatteryEvent [$action]: level=$level%, state=$state, isCharging=$isChargingNow, wasCharging=$wasCharging")

        // 1. PLUG-IN DETECTED: transition from false -> true (or ACTION_POWER_CONNECTED)
        if ((isChargingNow && !wasCharging) || action == Intent.ACTION_POWER_CONNECTED) {
            Log.d(TAG, "⚡ CHARGING STARTED at $nowTime, Level: $level% ($pluggedSource)")
            prefs.edit().apply {
                putBoolean(PREF_IS_CHARGING, true)
                putInt(PREF_START_PCT, level)
                putString(PREF_START_DATE, nowDate)
                putString(PREF_START_TIME, nowTime)
                putString(PREF_START_TIMESTAMP, nowIso)
                putString(PREF_PLUGGED_SOURCE, pluggedSource)
                apply()
            }

            updateNotification("⚡ VoltBuddy • Charging ($level%)", "Plugged into $pluggedSource • Target 85% recommended")
        }
        // 2. UNPLUG DETECTED: transition from true -> false (or ACTION_POWER_DISCONNECTED)
        else if ((!isChargingNow && wasCharging) || action == Intent.ACTION_POWER_DISCONNECTED) {
            val startPct = prefs.getInt(PREF_START_PCT, level)
            val startDate = prefs.getString(PREF_START_DATE, nowDate) ?: nowDate
            val startTime = prefs.getString(PREF_START_TIME, nowTime) ?: nowTime
            val startSource = prefs.getString(PREF_PLUGGED_SOURCE, "AC") ?: "AC"

            Log.d(TAG, "🔌 CHARGING ENDED at $nowTime: $startPct% -> $level% ($startDate $startTime -> $nowDate $nowTime)")

            // Save completed charge session record if valid
            if (level > startPct || (level == startPct && level >= 80)) {
                appendChargeSessionRecord(startPct, startDate, startTime, level, nowDate, nowTime, startSource)
            }

            // Reset charging state
            prefs.edit().apply {
                putBoolean(PREF_IS_CHARGING, false)
                remove(PREF_START_PCT)
                remove(PREF_START_DATE)
                remove(PREF_START_TIME)
                remove(PREF_START_TIMESTAMP)
                remove(PREF_PLUGGED_SOURCE)
                apply()
            }

            val gained = level - startPct
            val gainedText = if (gained > 0) "+$gained% gained" else "$level%"
            updateNotification("🔋 VoltBuddy Battery Guard", "Active • Battery $gainedText ($level%)")
        }
        // 3. CONTINUOUS LEVEL UPDATE WHILE CHARGING OR DISCHARGING
        else {
            if (isChargingNow) {
                val startPct = prefs.getInt(PREF_START_PCT, level)
                val gained = (level - startPct).coerceAtLeast(0)
                val statusText = if (level >= 85) {
                    "85% Target Reached! Unplug soon ⚡"
                } else {
                    "Charging ($level%) • +$gained% gained"
                }
                updateNotification("⚡ VoltBuddy • Charging ($level%)", statusText)
            } else {
                updateNotification("🔋 VoltBuddy Battery Guard", "$level% • Battery Protected")
            }
        }
    }

    private fun appendSnapshotRecord(
        timestamp: String,
        level: Int,
        state: String,
        isPlugged: Boolean,
        pluggedSource: String,
        event: String
    ) {
        val record = JSONObject().apply {
            put("type", "snapshot")
            put("timestamp", timestamp)
            put("level", level)
            put("state", state)
            put("isPlugged", isPlugged)
            put("pluggedSource", pluggedSource)
            put("event", event)
        }
        appendRecordToFile(record)
    }

    private fun appendChargeSessionRecord(
        startPct: Int,
        startDate: String,
        startTime: String,
        endPct: Int,
        endDate: String,
        endTime: String,
        source: String
    ) {
        val session = JSONObject().apply {
            put("type", "charge_session")
            put("start_pct", startPct)
            put("start_date", startDate)
            put("start_time", startTime)
            put("end_pct", endPct)
            put("end_date", endDate)
            put("end_time", endTime)
            put("source", source)
        }
        appendRecordToFile(session)
    }

    private fun appendRecordToFile(record: JSONObject) {
        val file = File(filesDir, RECORDS_FILE)
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
            Log.d(TAG, "Appended native record: $record (Total in file: ${array.length()})")
        }
    }
}
