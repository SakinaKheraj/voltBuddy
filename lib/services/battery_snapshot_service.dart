import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:voltbuddy/data/battery_db.dart';
import 'package:voltbuddy/models/simulation_models.dart';

class BatterySnapshot {
  final int level;
  final String state;
  final bool isPlugged;
  final String pluggedSource;
  final int? temperatureTenthsC;
  final int? voltageMv;

  const BatterySnapshot({
    required this.level,
    required this.state,
    required this.isPlugged,
    required this.pluggedSource,
    this.temperatureTenthsC,
    this.voltageMv,
  });

  bool get isChargeSessionState =>
      isPlugged ||
      state == 'charging' ||
      state == 'full' ||
      state == 'connectedNotCharging';
}

class BatterySnapshotService {
  static const MethodChannel _channel =
      MethodChannel('com.example.voltbuddy/battery');

  static final Battery _fallbackBattery = Battery();

  static Future<BatterySnapshot> current() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>(
          'getBatterySnapshot',
        );
        if (raw != null) {
          final state = (raw['state'] as String?) ?? 'unknown';
          final isPlugged = raw['isPlugged'] as bool? ??
              state == 'charging' ||
                  state == 'full' ||
                  state == 'connectedNotCharging';

          return BatterySnapshot(
            level: ((raw['level'] as num?)?.toInt() ?? 0).clamp(0, 100),
            state: state,
            isPlugged: isPlugged,
            pluggedSource: (raw['pluggedSource'] as String?) ?? 'unknown',
            temperatureTenthsC: (raw['temperatureTenthsC'] as num?)?.toInt(),
            voltageMv: (raw['voltageMv'] as num?)?.toInt(),
          );
        }
      } catch (_) {
        // Fall back to battery_plus for non-standard Android runtimes.
      }
    }

    final level = await _fallbackBattery.batteryLevel;
    final batteryState = await _fallbackBattery.batteryState;
    final state = batteryState.toString().split('.').last;
    final isPlugged = batteryState == BatteryState.charging ||
        batteryState == BatteryState.full ||
        batteryState == BatteryState.connectedNotCharging;

    return BatterySnapshot(
      level: level.clamp(0, 100),
      state: state,
      isPlugged: isPlugged,
      pluggedSource: isPlugged ? 'unknown' : 'none',
    );
  }

  /// Starts the 24/7 native Foreground Service.
  static Future<bool> startBatteryService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startBatteryService');
      return ok ?? false;
    } catch (e) {
      debugPrint('VoltBuddy: Failed to start battery service: $e');
      return false;
    }
  }

  /// Prompts the user to exempt VoltBuddy from battery optimizations (Unrestricted mode).
  static Future<bool> requestBatteryOptimizationExemption() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'requestBatteryOptimizationExemption',
      );
      return ok ?? false;
    } catch (e) {
      debugPrint('VoltBuddy: Failed to request battery optimization: $e');
      return false;
    }
  }

  /// Imports battery records and complete charge sessions captured by
  /// the native [VoltBatteryService] while the app was closed.
  ///
  /// Returns the number of items imported into the SQLite database.
  static Future<int> importNativeRecords() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 0;

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getAndClearNativeRecords',
      );
      if (result == null || result.isEmpty) return 0;

      final db = BatteryDb();
      int imported = 0;

      for (final entry in result) {
        if (entry is Map) {
          final map = Map<String, dynamic>.from(entry);
          final type = map['type'] as String? ?? 'snapshot';

          if (type == 'charge_session') {
            final startPct = (map['start_pct'] as num?)?.toInt() ?? 0;
            final startDate = map['start_date'] as String? ?? '';
            final startTime = map['start_time'] as String? ?? '';
            final endPct = (map['end_pct'] as num?)?.toInt() ?? 0;
            final endDate = map['end_date'] as String? ?? '';
            final endTime = map['end_time'] as String? ?? '';

            final source = map['source'] as String? ?? 'AC';

            if (startDate.isNotEmpty &&
                startTime.isNotEmpty &&
                endDate.isNotEmpty &&
                endTime.isNotEmpty) {
              await db.insertChargeSession(ChargeSession(
                startPct: startPct,
                startDate: startDate,
                startTime: startTime,
                endPct: endPct,
                endDate: endDate,
                endTime: endTime,
                source: source,
              ));
              imported++;
            }
          } else {
            final timestamp = map['timestamp'] as String? ?? '';
            final level = (map['level'] as num?)?.toInt() ?? 0;
            final state = map['state'] as String? ?? 'unknown';

            if (timestamp.isNotEmpty && level >= 0) {
              await db.insertRecord(BatteryRecord(
                timestamp: timestamp,
                level: level.clamp(0, 100),
                state: state,
              ));
              imported++;
            }
          }
        }
      }

      if (imported > 0) {
        debugPrint('VoltBuddy: Successfully imported $imported native background records/sessions');
        await db.processRawRecordsIntoSessions();
      }

      return imported;
    } catch (e) {
      debugPrint('VoltBuddy: Failed to import native records: $e');
      return 0;
    }
  }

  /// Returns `notification` if the app was just opened by tapping the
  /// VoltBuddy notification, otherwise null. Reading clears it.
  static Future<String?> getLaunchSource() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('getLaunchSource');
    } catch (e) {
      debugPrint('VoltBuddy: Failed to read launch source: $e');
      return null;
    }
  }

  /// Returns and clears interaction-study events recorded by the native
  /// service while the app was closed (plug/unplug, 85% notification).
  static Future<List<Map<String, Object?>>> getAndClearNativeEvents() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getAndClearNativeEvents');
      if (result == null) return const [];
      return [
        for (final entry in result)
          if (entry is Map) Map<String, Object?>.from(entry),
      ];
    } catch (e) {
      debugPrint('VoltBuddy: Failed to read native events: $e');
      return const [];
    }
  }

  /// Returns device info (manufacturer, model, brand, Android version, etc.)
  /// from the native Android side via MethodChannel.
  static Future<Map<String, dynamic>?> getDeviceInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getDeviceInfo',
      );
      return result;
    } catch (e) {
      debugPrint('VoltBuddy: Failed to get device info: $e');
      return null;
    }
  }
}
