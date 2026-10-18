/// Phase 2 interaction-tracking switches.
///
/// Tracking can be turned off without touching code:
///   flutter build apk --dart-define=VB_TRACKING=false
const bool kInteractionTrackingEnabled =
    bool.fromEnvironment('VB_TRACKING', defaultValue: true);

/// Shows the live event viewer inside the hidden Dev tab. Off for
/// participant builds; enable with --dart-define=VB_EVENT_VIEWER=true.
const bool kEventViewerEnabled =
    bool.fromEnvironment('VB_EVENT_VIEWER', defaultValue: false);

/// Keep in sync with `version:` in pubspec.yaml.
const String kAppVersion = '2.1.0+2';
