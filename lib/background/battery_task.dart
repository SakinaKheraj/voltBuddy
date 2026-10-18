import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:voltbuddy/data/battery_db.dart';
import 'package:voltbuddy/services/battery_snapshot_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Step 1: Import any records captured by the native
      // PowerConnectionReceiver / BatteryWorker while the app was killed.
      await _importNativeRecordsInBackground();

      // Step 2: Capture a fresh snapshot using the native MethodChannel.
      await collectBatteryData();
    } catch (e) {
      debugPrint('VoltBuddy background task error: $e');
    }
    return Future.value(true);
  });
}

/// Called by Workmanager every ~15 minutes on Android.
/// Uses native MethodChannel instead of battery_plus to avoid
/// plugin initialization issues in background isolates.
Future<void> collectBatteryData() async {
  const channel = MethodChannel('com.example.voltbuddy/battery');

  try {
    final raw = await channel.invokeMapMethod<String, dynamic>(
      'getBatterySnapshot',
    );
    if (raw != null) {
      final record = BatteryRecord(
        timestamp: DateTime.now().toIso8601String(),
        level: ((raw['level'] as num?)?.toInt() ?? 0).clamp(0, 100),
        state: (raw['state'] as String?) ?? 'unknown',
      );

      final db = BatteryDb();
      await db.insertRecord(record);
      await db.processRawRecordsIntoSessions();
      return;
    }
  } catch (e) {
    debugPrint(
      'VoltBuddy: MethodChannel unavailable in background, '
      'native BatteryWorker will handle it. Error: $e',
    );
    // The native BatteryWorker (registered via BootReceiver) writes to
    // the JSON file independently, so data is still captured even if
    // the Flutter MethodChannel is unavailable in this isolate.
  }
}

/// Reads and imports native background records in the background task.
Future<void> _importNativeRecordsInBackground() async {
  try {
    final imported = await BatterySnapshotService.importNativeRecords();
    if (imported > 0) {
      final db = BatteryDb();
      await db.processRawRecordsIntoSessions();
    }
  } catch (e) {
    debugPrint('VoltBuddy: Failed to import native records in bg: $e');
  }
}
