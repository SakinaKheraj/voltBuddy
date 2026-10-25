import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltbuddy/analytics/event_logger.dart';
import 'package:voltbuddy/analytics/event_store.dart';
import 'package:voltbuddy/analytics/tap_recorder.dart';

void main() {
  late MemoryEventStore store;
  final logger = EventLogger.instance;

  Future<void> initLogger({
    List<Map<String, Object?>> nativeEvents = const [],
    String? launchSource,
  }) async {
    store = MemoryEventStore();
    await logger.init(
      store: store,
      attachLifecycle: false,
      launchSourceReader: () async => launchSource,
      nativeEventsReader: () async => nativeEvents,
    );
  }

  Map<String, Object?> props(Map<String, Object?> row) =>
      jsonDecode(row['props'] as String) as Map<String, Object?>;

  tearDown(() => logger.resetForTest());

  test('logs app_opened with launch source and attaches context', () async {
    await initLogger(launchSource: 'notification');
    logger.contextProvider = () => {
          'tab': 'tab-tips',
          'battery_pct': 62,
          'is_charging': true,
          'persona': 'genz',
        };
    logger.log('advice_generated', userAction: true, props: {'score': 81});
    await logger.flush();

    expect(store.rows.map((r) => r['event']), ['app_opened', 'advice_generated']);
    expect(props(store.rows.first)['launch_source'], 'notification');

    final advice = store.rows.last;
    expect(advice['tab'], 'tab-tips');
    expect(advice['battery_pct'], 62);
    expect(advice['is_charging'], 1);
    expect(advice['user_action'], 1);
    expect(advice['session_seq'], 2);
    expect(advice['source'], 'app');
    expect(props(advice)['score'], 81);
  });

  test('background/foreground closes and opens sessions around hooks', () async {
    await initLogger();
    final firstSession = logger.sessionId;
    final order = <String>[];
    logger.addLifecycleHooks(
      beforeBackground: () {
        order.add('hook_bg');
        logger.log('tab_left');
      },
      afterForeground: () {
        order.add('hook_fg');
        logger.log('tab_entered');
      },
    );

    logger.handleHide();
    logger.handleHide(); // duplicate hide is ignored
    await logger.handleShow();
    await logger.flush();

    expect(store.rows.map((r) => r['event']), [
      'app_opened',
      'tab_left',
      'app_backgrounded',
      'app_foregrounded',
      'tab_entered',
    ]);
    expect(order, ['hook_bg', 'hook_fg']);
    expect(store.rows[2]['session_id'], firstSession);
    expect(store.rows[3]['session_id'], isNot(firstSession));
    expect(store.rows[3]['session_seq'], 1);
    expect(props(store.rows[2]).containsKey('fg_duration_ms'), isTrue);
    expect(props(store.rows[3])['launch_source'], 'launcher_or_recents');
  });

  test('device status is logged at start and again only when it changes', () async {
    var status = <String, Object?>{'notifications_enabled': true, 'battery_unrestricted': false};
    store = MemoryEventStore();
    await logger.init(
      store: store,
      attachLifecycle: false,
      deviceStatusReader: () async => status,
    );

    logger.handleHide();
    await logger.handleShow(); // unchanged -> not logged again
    status = {'notifications_enabled': false, 'battery_unrestricted': false};
    logger.handleHide();
    await logger.handleShow(); // notifications turned off -> logged
    await logger.flush();

    final rows = store.rows.where((r) => r['event'] == 'device_status').toList();
    expect(rows, hasLength(2));
    expect(props(rows.first)['notifications_enabled'], isTrue);
    expect(props(rows.first)['changed'], isFalse);
    expect(props(rows.last)['notifications_enabled'], isFalse);
    expect(props(rows.last)['changed'], isTrue);
  });

  test('imports native events with their own timestamps', () async {
    final ts = DateTime(2026, 10, 18, 9, 30).millisecondsSinceEpoch;
    await initLogger(nativeEvents: [
      {
        'event': 'native_unplug_nudge_posted',
        'ts_ms': ts,
        'level': 86,
        'state': 'charging',
        'is_charging': true,
        'start_pct': 40,
      },
      {'event': 'missing_timestamp'},
    ]);
    await logger.flush();

    final native = store.rows.where((r) => r['source'] == 'native').toList();
    expect(native, hasLength(1));
    expect(native.single['event'], 'native_unplug_nudge_posted');
    expect(native.single['ts_utc_ms'], ts);
    expect(native.single['session_id'], isNull);
    expect(native.single['battery_pct'], 86);
    expect(native.single['is_charging'], 1);
    expect(props(native.single)['start_pct'], 40);
  });

  test('only user actions count as tap responses', () async {
    await initLogger();
    final since = logger.monoNow;
    logger.log('unplug_nudge_shown');
    logger.log('scrolled', userAction: true, tapResponse: false);
    expect(logger.firstTapResponseBetween(since, since + 10000), isNull);
    logger.log('talk_tapped', userAction: true);
    expect(logger.firstTapResponseBetween(since, since + 10000), 'talk_tapped');
  });

  test("a later tap's action is not credited to an earlier tap", () async {
    await initLogger();
    // Tap A: down at 1000, up at 1190 (no handler). Tap B's action at 1548.
    logger.log('tab_selected', userAction: true, atMono: 1548);
    expect(logger.firstTapResponseBetween(1000, 1190 + 250), isNull);
    expect(logger.firstTapResponseBetween(1518, 1548 + 250), 'tab_selected');
  });

  test('CSV export has metadata header and one line per event', () async {
    await initLogger();
    logger.log('species_selected',
        target: 'dog', props: {'note': 'has "quotes", commas\nand newline'});
    final csv = await logger.buildCsv(participantId: 'P000000', installId: 'abcd');
    final lines = csv.trimRight().split('\n');

    expect(lines.where((l) => l.startsWith('# Participant ID')).single,
        contains('P000000'));
    final header = lines.firstWhere((l) => !l.startsWith('#'));
    expect(header.split(',').take(3), ['participant_id', 'install_id', 'event_id']);
    final dataLines = lines.skipWhile((l) => l.startsWith('#')).skip(1).toList();
    expect(dataLines, hasLength(2));
    expect(dataLines.last, startsWith('P000000,abcd,2,'));
    // The props field survives CSV quoting and decodes back to the original.
    final quoted = RegExp(r',"(\{.*\})",').firstMatch(dataLines.last)!.group(1)!;
    final decoded = jsonDecode(quoted.replaceAll('""', '"')) as Map;
    expect(decoded['note'], 'has "quotes", commas\nand newline');
  });

  test('csvField escapes only when needed', () {
    expect(csvField(null), '');
    expect(csvField(42), '42');
    expect(csvField('a,b'), '"a,b"');
    expect(csvField('say "hi"'), '"say ""hi"""');
    expect(csvField('line1\nline2'), 'line1 line2');
  });

  test('localIsoWithOffset includes a UTC offset', () {
    expect(localIsoWithOffset(DateTime(2026, 10, 18, 14, 3)),
        matches(RegExp(r'^2026-10-18T14:03:00\.000[+-]\d{2}:\d{2}$')));
  });

  testWidgets('tap recorder marks dead taps and handled taps', (tester) async {
    await tester.runAsync(initLogger);
    logger.tapContextResolver = (_) => {'zone': 'test_zone'};

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => InteractionTapRecorder(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            const SizedBox(key: Key('empty'), width: 200, height: 200),
            ElevatedButton(
              key: const Key('button'),
              onPressed: () => logger.log('button_pressed', userAction: true),
              child: const Text('Press'),
            ),
          ],
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('empty')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('button')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(logger.flush);

    final taps = store.rows.where((r) => r['event'] == 'tap').toList();
    expect(taps, hasLength(2));
    expect(props(taps.first)['handled'], isFalse);
    expect(props(taps.last)['handled'], isTrue);
    expect(props(taps.last)['handled_by'], 'button_pressed');
    expect(taps.first['target'], 'test_zone');
  });

  testWidgets('closing a dialog by tapping outside is not a dead tap', (tester) async {
    await tester.runAsync(initLogger);

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [TrackingNavigatorObserver.instance],
      builder: (context, child) => InteractionTapRecorder(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Hi')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(TrackingNavigatorObserver.instance.topPopupKind, 'dialog');

    await tester.tapAt(const Offset(10, 10)); // barrier, outside the dialog
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(logger.flush);

    expect(TrackingNavigatorObserver.instance.topPopupKind, isNull);
    final events = store.rows.map((r) => r['event']).toList();
    expect(events, containsAllInOrder(['overlay_opened', 'overlay_closed']));
    final barrierTap = store.rows.where((r) => r['event'] == 'tap').last;
    expect(props(barrierTap)['handled'], isTrue);
    expect(props(barrierTap)['handled_by'], 'overlay_closed');
  });
}
