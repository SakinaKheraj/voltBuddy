import 'package:battery_plus/battery_plus.dart';
import 'package:voltbuddy/data/battery_db.dart'; // adjust import if needed

/// Called by Workmanager every 15 minutes on Android.
Future<void> collectBatteryData() async {
  final battery = Battery();
  final int level = await battery.batteryLevel;
  final BatteryState state = await battery.batteryState;

  final record = BatteryRecord(
    timestamp: DateTime.now().toIso8601String(),
    level: level,
    state: state.toString().split('.').last,
  );

  await BatteryDb().insertRecord(record);
}
