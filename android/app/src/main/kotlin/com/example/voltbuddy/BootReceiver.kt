package com.example.voltbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Re-registers and restarts VoltBatteryService automatically after device reboot.
 *
 * This ensures that 24/7 charging and battery tracking resumes seamlessly
 * without requiring the user to manually open the app after restarting their phone.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "VoltBuddy.BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.d(TAG, "Device rebooted — starting VoltBatteryService")

        try {
            val serviceIntent = Intent(context, VoltBatteryService::class.java)
            ContextCompat.startForegroundService(context, serviceIntent)
            Log.d(TAG, "VoltBatteryService started successfully after boot")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VoltBatteryService after boot: ${e.message}", e)
        }
    }
}
