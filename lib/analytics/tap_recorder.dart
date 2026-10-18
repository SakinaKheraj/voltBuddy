import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'event_logger.dart';

/// Records every tap on the screen, whether or not it hit a control.
///
/// Sits above the whole app as a translucent [Listener], so it observes
/// pointers without taking part in gesture handling. A short while after each
/// tap it checks whether any user action was logged; if not, the tap is a
/// "dead tap" (`handled = false`) — the participant tapped something that
/// does nothing.
class InteractionTapRecorder extends StatefulWidget {
  final Widget child;
  const InteractionTapRecorder({super.key, required this.child});

  static const Duration responseWindow = Duration(milliseconds: 400);
  static const Duration maxTapDuration = Duration(milliseconds: 600);

  @override
  State<InteractionTapRecorder> createState() => _InteractionTapRecorderState();
}

class _PointerDown {
  final Offset position;
  final int mono;
  final DateTime at;
  bool moved = false;
  _PointerDown(this.position, this.mono, this.at);
}

class _InteractionTapRecorderState extends State<InteractionTapRecorder> {
  final Map<int, _PointerDown> _downs = {};

  @override
  Widget build(BuildContext context) {
    final logger = EventLogger.instance;
    if (!logger.enabled) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) =>
          _downs[e.pointer] = _PointerDown(e.position, logger.monoNow, DateTime.now()),
      onPointerMove: (e) {
        final down = _downs[e.pointer];
        if (down != null && (e.position - down.position).distance > kTouchSlop) {
          down.moved = true;
        }
      },
      onPointerCancel: (e) => _downs.remove(e.pointer),
      onPointerUp: (e) => _onUp(e, logger),
      child: widget.child,
    );
  }

  void _onUp(PointerUpEvent e, EventLogger logger) {
    final down = _downs.remove(e.pointer);
    if (down == null || down.moved) return;
    final holdMs = logger.monoNow - down.mono;
    if (holdMs > InteractionTapRecorder.maxTapDuration.inMilliseconds) return;

    // Resolve region and state now, before the tap's handler changes the UI.
    Map<String, Object?> region = const {};
    try {
      region = logger.tapContextResolver?.call(down.position) ?? const {};
    } catch (_) {}
    final ctx = logger.snapshotContext();
    final size = MediaQuery.maybeSizeOf(context);

    Timer(InteractionTapRecorder.responseWindow, () {
      final handledBy = logger.firstTapResponseSince(down.mono);
      logger.log(
        'tap',
        target: region['zone'] as String?,
        at: down.at,
        atMono: down.mono,
        tapResponse: false,
        contextOverride: ctx,
        props: {
          'x': _round(down.position.dx),
          'y': _round(down.position.dy),
          if (size != null) 'screen_w': _round(size.width),
          if (size != null) 'screen_h': _round(size.height),
          'hold_ms': holdMs,
          'handled': handledBy != null,
          if (handledBy != null) 'handled_by': handledBy,
          ...Map.of(region)..remove('zone'),
        },
      );
    });
  }

  static double _round(double v) => (v * 10).roundToDouble() / 10;
}

/// Tracks dialogs and dropdown menus (popup routes) so taps inside them are
/// attributed correctly, and logs how long each stayed open.
class TrackingNavigatorObserver extends NavigatorObserver {
  TrackingNavigatorObserver._();
  static final TrackingNavigatorObserver instance = TrackingNavigatorObserver._();

  final List<({Route<dynamic> route, String kind, int openedMono})> _popups = [];

  /// `dialog` or `menu` while one is on top, otherwise null.
  String? get topPopupKind => _popups.isEmpty ? null : _popups.last.kind;

  static String? _kindOf(Route<dynamic> route) {
    if (route is DialogRoute) return 'dialog';
    if (route is PopupRoute) return 'menu';
    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final kind = _kindOf(route);
    if (kind == null) return;
    _popups.add((route: route, kind: kind, openedMono: EventLogger.instance.monoNow));
    EventLogger.instance.log('overlay_opened', target: kind);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _closed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _closed(route);

  void _closed(Route<dynamic> route) {
    final idx = _popups.indexWhere((p) => identical(p.route, route));
    if (idx < 0) return;
    final popup = _popups.removeAt(idx);
    EventLogger.instance.log('overlay_closed', target: popup.kind, props: {
      'open_ms': EventLogger.instance.monoNow - popup.openedMono,
    });
  }
}
