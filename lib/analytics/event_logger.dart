import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'event_store.dart';
import 'tracking_config.dart';

typedef ContextProvider = Map<String, Object?> Function();
typedef TapContextResolver = Map<String, Object?> Function(Offset globalPosition);

/// Phase 2 in-app interaction logger.
///
/// Events are buffered in memory and written to [EventStore] in small batches
/// (every few seconds, and immediately when the app goes to the background).
/// Logging never throws into the UI: every failure is swallowed and the batch
/// is retried on the next flush.
class EventLogger {
  EventLogger._();
  static final EventLogger instance = EventLogger._();

  static const int _flushThreshold = 25;
  static const Duration _flushInterval = Duration(seconds: 3);
  static const int _maxBufferedRows = 5000;

  late EventStore _store;
  bool _initialized = false;
  bool get enabled => kInteractionTrackingEnabled && _initialized;

  final List<Map<String, Object?>> _buffer = [];
  Future<void>? _inFlight;
  Timer? _flushTimer;

  final Stopwatch _mono = Stopwatch();
  int get monoNow => _mono.elapsedMilliseconds;

  String _launchId = '';
  int _sessionCounter = 0;
  String _sessionId = '';
  int _sessionSeq = 0;
  bool _inForeground = true;
  final Stopwatch _foreground = Stopwatch();
  DateTime? _backgroundedAt;
  AppLifecycleListener? _lifecycle;

  /// Supplies tab / battery / pet state attached to every event.
  ContextProvider? contextProvider;

  /// Maps a tap position to the screen region it landed in.
  TapContextResolver? tapContextResolver;

  Future<String?> Function()? _launchSourceReader;
  Future<List<Map<String, Object?>>> Function()? _nativeEventsReader;

  final List<VoidCallback> _beforeBackground = [];
  final List<VoidCallback> _afterForeground = [];

  // User actions that can "answer" a tap, used to detect dead taps.
  final List<({int mono, String event})> _recentTapResponses = [];

  Future<void> init({
    EventStore? store,
    bool attachLifecycle = true,
    Future<String?> Function()? launchSourceReader,
    Future<List<Map<String, Object?>>> Function()? nativeEventsReader,
  }) async {
    if (!kInteractionTrackingEnabled || _initialized) return;
    _store = store ?? SqfliteEventStore();
    _launchSourceReader = launchSourceReader;
    _nativeEventsReader = nativeEventsReader;
    _mono
      ..reset()
      ..start();
    _launchId = _randomHex(4);
    _initialized = true;
    _startSession();

    log('app_opened', props: {
      'cold_start': true,
      'launch_source': await _readLaunchSource(),
    });
    await importNativeEvents();

    if (attachLifecycle) {
      _lifecycle = AppLifecycleListener(
        onShow: () => unawaited(handleShow()),
        onHide: handleHide,
        onPause: () => unawaited(flush()),
        onDetach: () => unawaited(flush()),
      );
    }
    _flushTimer = Timer.periodic(_flushInterval, (_) => unawaited(flush()));
  }

  /// Registers callbacks run just before `app_backgrounded` is logged and just
  /// after `app_foregrounded`, so open tab / visibility spans can be closed and
  /// reopened around background time.
  void addLifecycleHooks({VoidCallback? beforeBackground, VoidCallback? afterForeground}) {
    if (beforeBackground != null) _beforeBackground.add(beforeBackground);
    if (afterForeground != null) _afterForeground.add(afterForeground);
  }

  void removeLifecycleHooks({VoidCallback? beforeBackground, VoidCallback? afterForeground}) {
    _beforeBackground.remove(beforeBackground);
    _afterForeground.remove(afterForeground);
  }

  @visibleForTesting
  void handleHide() {
    if (!enabled || !_inForeground) return;
    for (final hook in List.of(_beforeBackground)) {
      _safely(hook);
    }
    _inForeground = false;
    log('app_backgrounded', props: {'fg_duration_ms': _foreground.elapsedMilliseconds});
    _foreground
      ..stop()
      ..reset();
    _backgroundedAt = DateTime.now();
    unawaited(flush());
  }

  @visibleForTesting
  Future<void> handleShow() async {
    if (!enabled || _inForeground) return;
    _inForeground = true;
    _startSession();
    // Wall clock, not a Stopwatch: the monotonic clock stops while the phone
    // sleeps, which would undercount time away from the app.
    final bgMs = _backgroundedAt == null
        ? null
        : math.max(0, DateTime.now().difference(_backgroundedAt!).inMilliseconds);
    _backgroundedAt = null;
    final source = await _readLaunchSource();
    log('app_foregrounded', props: {'bg_duration_ms': bgMs, 'launch_source': source});
    for (final hook in List.of(_afterForeground)) {
      _safely(hook);
    }
    await importNativeEvents();
  }

  void _startSession() {
    _sessionCounter++;
    _sessionId = '$_launchId-$_sessionCounter';
    _sessionSeq = 0;
    _foreground
      ..reset()
      ..start();
  }

  /// Records one event.
  ///
  /// [userAction] marks events caused directly by the participant (as opposed
  /// to things the app showed them). [tapResponse] (defaults to [userAction])
  /// controls whether the event counts as the response to a raw tap.
  void log(
    String event, {
    String? target,
    Map<String, Object?>? props,
    bool userAction = false,
    bool? tapResponse,
    DateTime? at,
    int? atMono,
    String source = 'app',
    Map<String, Object?>? contextOverride,
  }) {
    if (!enabled) return;
    try {
      final now = at ?? DateTime.now();
      final isNative = source == 'native';
      final mono = atMono ?? monoNow;
      final ctx = contextOverride ?? snapshotContext();

      _buffer.add({
        'launch_id': _launchId,
        'session_id': isNative ? null : _sessionId,
        'session_seq': isNative ? null : ++_sessionSeq,
        'source': source,
        'ts_utc_ms': now.millisecondsSinceEpoch,
        'ts_local': localIsoWithOffset(now),
        'mono_ms': isNative ? null : mono,
        'event': event,
        'user_action': userAction ? 1 : 0,
        'tab': ctx['tab'],
        'target': target,
        'props': _encodeProps(props),
        'battery_pct': ctx['battery_pct'],
        'battery_state': ctx['battery_state'],
        'is_charging': _boolToInt(ctx['is_charging']),
        'persona': ctx['persona'],
        'species': ctx['species'],
        'hp': ctx['hp'],
        'xp': ctx['xp'],
        'rank_index': ctx['rank_index'],
        'app_version': kAppVersion,
      });

      if (tapResponse ?? userAction) {
        _recentTapResponses.add((mono: mono, event: event));
        if (_recentTapResponses.length > 20) _recentTapResponses.removeAt(0);
      }
      if (_buffer.length >= _flushThreshold) unawaited(flush());
    } catch (e) {
      debugPrint('VoltBuddy: event log failed for $event: $e');
    }
  }

  Map<String, Object?> snapshotContext() {
    try {
      return contextProvider?.call() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// Name of the first user action logged between [fromMono] and [toMono]
  /// (inclusive), if any. Bounding the window stops a later tap's action
  /// being credited to an earlier tap.
  String? firstTapResponseBetween(int fromMono, int toMono) {
    for (final r in _recentTapResponses) {
      if (r.mono >= fromMono && r.mono <= toMono) return r.event;
    }
    return null;
  }

  /// Set by the main screen when a scroll comes to rest; used to recognise a
  /// touch that only stopped a scroll.
  int lastScrollEndMono = -1;

  Future<void> flush() async {
    if (!_initialized) return;
    while (_inFlight != null) {
      await _inFlight;
    }
    if (_buffer.isEmpty) return;
    final batch = List.of(_buffer);
    _buffer.clear();
    final write = _store.insertAll(batch).catchError((Object e) {
      debugPrint('VoltBuddy: event flush failed, will retry: $e');
      _buffer.insertAll(0, batch);
      if (_buffer.length > _maxBufferedRows) {
        _buffer.removeRange(0, _buffer.length - _maxBufferedRows);
      }
    });
    _inFlight = write;
    try {
      await write;
    } finally {
      _inFlight = null;
    }
  }

  /// Pulls events recorded by the native Android service (plug/unplug and the
  /// "85% reached" notification) while the app was closed.
  Future<void> importNativeEvents() async {
    if (!enabled || _nativeEventsReader == null) return;
    try {
      final events = await _nativeEventsReader!();
      for (final e in events) {
        final name = e['event'] as String?;
        final tsMs = (e['ts_ms'] as num?)?.toInt();
        if (name == null || tsMs == null) continue;
        final props = Map<String, Object?>.from(e)
          ..remove('event')
          ..remove('ts_ms');
        final level = (props['level'] as num?)?.toInt();
        final state = props['state'] as String?;
        log(
          name,
          source: 'native',
          at: DateTime.fromMillisecondsSinceEpoch(tsMs),
          props: props,
          tapResponse: false,
          contextOverride: {
            'battery_pct': level,
            'battery_state': state,
            'is_charging': props['is_charging'],
          },
        );
      }
    } catch (e) {
      debugPrint('VoltBuddy: native event import failed: $e');
    }
  }

  Future<List<Map<String, Object?>>> latest(int limit) async {
    if (!enabled) return const [];
    await flush();
    return _store.latest(limit);
  }

  Future<int> count() async {
    if (!enabled) return 0;
    await flush();
    return _store.count();
  }

  /// Builds `interaction_logs.csv`. Comment lines (#) carry study metadata,
  /// matching the format of `charge_logs.csv`.
  Future<String> buildCsv({
    required String participantId,
    required String installId,
    Map<String, dynamic>? deviceInfo,
  }) async {
    await flush();
    final rows = await _store.all();
    final out = StringBuffer()
      ..writeln('# ========================================================')
      ..writeln('# VoltBuddy Phase 2 Interaction Logs')
      ..writeln('# Export Timestamp : ${localIsoWithOffset(DateTime.now())}')
      ..writeln('# Participant ID   : $participantId')
      ..writeln('# Install ID       : $installId')
      ..writeln('# App Version      : $kAppVersion');
    if (deviceInfo != null) {
      out
        ..writeln('# Device           : ${deviceInfo['manufacturer']} '
            '${deviceInfo['model']} (${deviceInfo['brand']})')
        ..writeln('# Android OS       : ${deviceInfo['androidVersion']} '
            '(SDK ${deviceInfo['sdkInt']})');
    }
    out
      ..writeln('# Total Events     : ${rows.length}')
      ..writeln('# ========================================================')
      ..writeln('#')
      ..writeln([
        'participant_id',
        'install_id',
        'event_id',
        ...kEventColumns.skip(1),
      ].join(','));

    for (final row in rows) {
      out.writeln([
        csvField(participantId),
        csvField(installId),
        for (final col in kEventColumns) csvField(row[col]),
      ].join(','));
    }
    return out.toString();
  }

  Future<String?> _readLaunchSource() async {
    try {
      return await _launchSourceReader?.call() ?? 'launcher_or_recents';
    } catch (_) {
      return 'unknown';
    }
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    _flushTimer?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    _buffer.clear();
    _recentTapResponses.clear();
    _beforeBackground.clear();
    _afterForeground.clear();
    _sessionCounter = 0;
    _inForeground = true;
    lastScrollEndMono = -1;
    contextProvider = null;
    tapContextResolver = null;
    _initialized = false;
  }

  @visibleForTesting
  String get sessionId => _sessionId;

  static void _safely(VoidCallback fn) {
    try {
      fn();
    } catch (e) {
      debugPrint('VoltBuddy: tracking hook failed: $e');
    }
  }

  static String? _encodeProps(Map<String, Object?>? props) {
    if (props == null || props.isEmpty) return null;
    try {
      return jsonEncode(props);
    } catch (_) {
      return jsonEncode(props.map((k, v) => MapEntry(k, v?.toString())));
    }
  }

  static int? _boolToInt(Object? v) => v is bool ? (v ? 1 : 0) : (v is int ? v : null);

  static String _randomHex(int bytes) {
    final rng = math.Random.secure();
    return List.generate(bytes, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// `2026-10-18T14:03:22.120+05:30`
String localIsoWithOffset(DateTime t) {
  final local = t.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final h = offset.inHours.abs().toString().padLeft(2, '0');
  final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final base = local.toIso8601String();
  return '$base$sign$h:$m';
}

/// Quotes a CSV field when needed. Newlines are flattened so each event stays
/// on one line (the Phase 1 Python parser reads line by line).
String csvField(Object? value) {
  if (value == null) return '';
  final s = value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  if (s.contains(',') || s.contains('"')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}
