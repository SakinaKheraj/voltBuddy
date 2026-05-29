import 'package:workmanager/workmanager.dart';

/// Registers a periodic Workmanager task that runs every 15 minutes.
/// Call this once (e.g., in the app's initState) to start background collection.
void scheduleBatteryBackground() {
  Workmanager().registerPeriodicTask(
    'batteryPeriodicTask', // unique name
    'batteryBackground',   // the task identifier used in the dispatcher
    frequency: const Duration(minutes: 15),
    // No extra constraints needed for this simple demo.
  );
}
