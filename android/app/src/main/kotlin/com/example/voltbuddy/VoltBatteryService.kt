package com.example.voltbuddy

import android.app.KeyguardManager
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
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.voltbuddy.StudyEvents.putAll
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
        // Phase 2 interaction-study flags (see StudyEvents)
        private const val PREF_NUDGE_LOGGED = "unplug_nudge_logged"
        private const val PREF_SCREEN_ON_LOGGED = "screen_on_after_nudge_logged"
        private const val PREF_UNLOCK_LOGGED = "unlock_after_nudge_logged"
        private const val PREF_HEARTBEAT_DATE = "study_heartbeat_date"
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
        StudyEvents.append(this, "native_service_started") {
            putAll(StudyEvents.deviceStatus(this@VoltBatteryService))
        }
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
        StudyEvents.append(this, "native_service_stopped")
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
        // Explicit intent (rather than the launcher intent) so a tap on the
        // notification is delivered to a running activity via onNewIntent and
        // can be told apart from a launcher open.
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_LAUNCH_SOURCE, "notification")
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

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
                when (intent.action) {
                    Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> handleScreenEvent(intent.action!!)
                    else -> handleBatteryEvent(intent)
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            // Phase 2: only acted on during a charge, after the 85% notification
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
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
        val tempTenthsC = batteryTempTenthsC(intent)
        maybeLogHeartbeat(now, nowDate, level, state)

        Log.d(TAG, "BatteryEvent [$action]: level=$level%, state=$state, isCharging=$isChargingNow, wasCharging=$wasCharging")

        // 1. PLUG-IN DETECTED: transition from false -> true (or ACTION_POWER_CONNECTED)
        if ((isChargingNow && !wasCharging) || action == Intent.ACTION_POWER_CONNECTED) {
            Log.d(TAG, "⚡ CHARGING STARTED at $nowTime, Level: $level% ($pluggedSource)")
            if (!wasCharging) {
                appendStudyEvent("native_power_connected", now, level, state, true, tempTenthsC) {
                    put("plugged_source", pluggedSource)
                }
            }
            prefs.edit().apply {
                putBoolean(PREF_NUDGE_LOGGED, false)
                putBoolean(PREF_SCREEN_ON_LOGGED, false)
                putBoolean(PREF_UNLOCK_LOGGED, false)
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
            if (wasCharging) {
                appendStudyEvent("native_power_disconnected", now, level, state, false, tempTenthsC) {
                    put("start_pct", startPct)
                    put("start_ts", prefs.getString(PREF_START_TIMESTAMP, null) ?: JSONObject.NULL)
                    put("nudge_posted", prefs.getBoolean(PREF_NUDGE_LOGGED, false))
                }
            }

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
                putBoolean(PREF_NUDGE_LOGGED, false)
                putBoolean(PREF_SCREEN_ON_LOGGED, false)
                putBoolean(PREF_UNLOCK_LOGGED, false)
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
                    if (!prefs.getBoolean(PREF_NUDGE_LOGGED, false)) {
                        prefs.edit().putBoolean(PREF_NUDGE_LOGGED, true).apply()
                        appendStudyEvent("native_unplug_nudge_posted", now, level, state, true, tempTenthsC) {
                            put("start_pct", startPct)
                            // Was the phone in use when the notification was posted?
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                            put("screen_on", pm.isInteractive)
                            put("locked", km.isKeyguardLocked)
                        }
                    }
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

    /** Records a Phase 2 interaction-study event with the battery state. */
    private fun appendStudyEvent(
        event: String,
        at: Date,
        level: Int,
        state: String,
        isCharging: Boolean,
        tempTenthsC: Int,
        extra: JSONObject.() -> Unit = {}
    ) {
        StudyEvents.append(this, event, at.time) {
            put("level", level)
            put("state", state)
            put("is_charging", isCharging)
            put("temp_c", if (tempTenthsC >= 0) tempTenthsC / 10.0 else JSONObject.NULL)
            extra()
        }
    }

    /** Battery temperature in tenths of °C, or -1 if unknown. */
    private fun batteryTempTenthsC(intent: Intent): Int {
        val fromIntent = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
        if (fromIntent >= 0) return fromIntent
        // ACTION_POWER_CONNECTED/DISCONNECTED carry no battery extras.
        val sticky = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
    }

    /**
     * Once per calendar day, records that the service is alive along with the
     * notification and battery-optimisation settings. Lets analysis tell "no
     * charging that day" apart from "tracking was not running".
     */
    private fun maybeLogHeartbeat(now: Date, today: String, level: Int, state: String) {
        if (prefs.getString(PREF_HEARTBEAT_DATE, null) == today) return
        prefs.edit().putString(PREF_HEARTBEAT_DATE, today).apply()
        StudyEvents.append(this, "native_heartbeat", now.time) {
            put("level", level)
            put("state", state)
            putAll(StudyEvents.deviceStatus(this@VoltBatteryService))
        }
    }

    /**
     * Screen-on / unlock, recorded only during a charge after the 85%
     * notification was posted, and only the first of each per charge. This is
     * the evidence for whether the participant could have seen the nudge; no
     * other phone use is recorded.
     */
    private fun handleScreenEvent(action: String) {
        if (!prefs.getBoolean(PREF_IS_CHARGING, false) ||
            !prefs.getBoolean(PREF_NUDGE_LOGGED, false)
        ) return
        val (flag, event) = if (action == Intent.ACTION_SCREEN_ON) {
            PREF_SCREEN_ON_LOGGED to "native_screen_on_after_nudge"
        } else {
            PREF_UNLOCK_LOGGED to "native_unlock_after_nudge"
        }
        if (prefs.getBoolean(flag, false)) return
        prefs.edit().putBoolean(flag, true).apply()
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        StudyEvents.append(this, event) {
            put("level", bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY))
            put("is_charging", true)
        }
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
