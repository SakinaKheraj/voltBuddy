/// Build switches.
///
/// `flutter build ... --flavor play` produces the public Google Play app:
/// no research features (interaction tracking, Student ID prompt) and no
/// Talk button (it needs a Gemini key that is not shipped).
/// `--flavor study` is the research build sideloaded to participants.
const bool kPlayBuild = String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'play';

/// Research-only features (Student ID prompt, participant ID in exports).
const bool kStudyFeatures = !kPlayBuild;

/// Phase 2 interaction tracking. Always off in the Play build; in the study
/// build it can be turned off without touching code:
///   flutter build apk --flavor study --dart-define=VB_TRACKING=false
const bool kInteractionTrackingEnabled =
    kStudyFeatures && bool.fromEnvironment('VB_TRACKING', defaultValue: true);

/// Shows the live event viewer inside the hidden Dev tab. Off for
/// participant builds; enable with --dart-define=VB_EVENT_VIEWER=true.
const bool kEventViewerEnabled =
    bool.fromEnvironment('VB_EVENT_VIEWER', defaultValue: false);

/// Keep in sync with `version:` in pubspec.yaml.
const String kAppVersion = '2.2.1+6';
