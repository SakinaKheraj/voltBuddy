import 'package:workmanager/workmanager.dart';

/// Registers a periodic Workmanager task that runs every 15 minutes.
/// Call this once (e.g., in the app's initState) to start background collection.
///
/// Uses [ExistingWorkPolicy.keep] to prevent duplicate task registration
/// if this is called multiple times (e.g., on every app launch).
void scheduleBatteryBackground() {
  Workmanager().registerPeriodicTask(
    'batteryPeriodicTask', // unique name
    'batteryBackground',   // the task identifier used in the dispatcher
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 1),
    constraints: Constraints(
      networkType: NetworkType.not_required,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
  );
}

