import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:visibility_detector/visibility_detector.dart';

import 'analytics/event_logger.dart';
import 'analytics/tap_recorder.dart';
import 'analytics/tracking_config.dart';
import 'models/simulation_models.dart';

import 'services/app_prefs.dart';
import 'services/battery_snapshot_service.dart';
import 'services/charging_ai_service.dart';
import 'services/localization_service.dart';
import 'services/gemini_service.dart';
import 'widgets/neo_brutalist.dart';
import 'widgets/pet_renderer.dart';
import 'widgets/heatmap_widget.dart';
import 'widgets/journey_map_widget.dart';

import 'package:battery_plus/battery_plus.dart';
import 'data/battery_db.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';
import 'background/battery_task.dart' show callbackDispatcher;
import 'background/schedule_battery.dart' show scheduleBatteryBackground;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(
    fileName: '.env',
    isOptional: true,
    mergeWith: {
      'GEMINI_API_KEY': const String.fromEnvironment(
        'GEMINI_API_KEY',
        defaultValue: '',
      ),
    },
  );

  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  } catch (e) {
    debugPrint("Failed to initialize Workmanager: $e");
  }

  final loc = LocalizationService();
  await loc.init();

  await AppPrefs.instance.load();
  final savedPersona = AppPrefs.instance.persona;
  if (savedPersona != null) loc.locale = savedPersona;

  try {
    await EventLogger.instance.init(
      launchSourceReader: BatterySnapshotService.getLaunchSource,
      nativeEventsReader: BatterySnapshotService.getAndClearNativeEvents,
    );
  } catch (e) {
    debugPrint("Failed to initialize interaction tracking: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.spaceGroteskTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      navigatorObservers: [TrackingNavigatorObserver.instance],
      builder: (context, child) =>
          InteractionTapRecorder(child: child ?? const SizedBox.shrink()),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LocalizationService _loc = LocalizationService();
  final GeminiService _gemini = GeminiService();
  final ChargingAiService _chargingAi = const ChargingAiService();

  // State Variables
  int _hp = 100;
  int _xp = 0;
  int _currentRankIndex = 0;
  String _currentSpecies = _restoredSpecies(); // cat, dog, rabbit
  String _currentTab =
      "tab-stats"; // tab-stats, tab-tips, tab-data, tab-sandbox

  // Simulation final state to restore to after dismissing popover
  int _simFinalHp = 100;
  int _simFinalXp = 0;
  int _simFinalRankIndex = 0;

  // Sandbox Easter Egg
  int _badgeClickCount = 0;
  bool _sandboxUnlocked = false;

  // Localization Language
  String _currentLanguage = "genz"; // Default to Gen Z

  // Glow trigger to animate the pet when score >= 80 or species changes
  int _petGlowTrigger = 0;

  // Pet dialogue state
  String _speechText = "...";
  bool _speechVisible = false;
  Timer? _speechTimer;
  Timer? _missionBriefTimer;
  bool _missionBriefVisible = false;

  // Floating text messages
  final List<FloatingTextModel> _floatingTexts = [];
  int _feedRewardTrigger = 0;
  int _warningReactionTrigger = 0;

  // Simulation Metrics Data
  final Map<String, WeeklyMetrics> _weeklyStats = {};
  final Map<String, DailyMetrics> _dailyData = {};
  final GlobalMetrics _globalMetrics = GlobalMetrics();
  late ChargingAiReport _aiReport;
  int _simulatedWeeksCount = 0;

  // Active Sessions Timeline Cards
  final List<Map<String, dynamic>> _timelineCards = [];

  // Real-Time Tracking State
  bool _isCharging = false;
  int _currentBatteryLevel = 100;
  String _currentBatteryState = 'unknown';
  int? _chargingStartLevel;
  bool _chargeNudgeShown = false;
  bool _hasLoadedRealStats = false;
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _foregroundBatteryTimer;
  final Battery _battery = Battery();

  // Expanded cards index state tracker
  final Set<int> _expandedCardIndices = {};

  // Screen shake variables
  late AnimationController _screenShakeController;
  late Animation<double> _screenShakeAnimation;

  final ScrollController _timelineScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

  // --- Phase 2 interaction tracking state ---
  final EventLogger _tracker = EventLogger.instance;
  bool _batteryKnown = false;
  bool _appInForeground = true;
  // Screen regions used to attribute raw taps (checked in this order).
  final Map<String, GlobalKey> _zoneKeys = {
    for (final zone in const [
      'header',
      'tab_bar',
      'pet_stage',
      'pet_details',
      'progress_bars',
      'tab_content',
    ])
      zone: GlobalKey(debugLabel: 'zone_$zone'),
  };
  int? _tabEnteredMono;
  double _tabMaxScrollPx = 0;
  int? _contentSeenStartMono;
  String? _contentSeenTab;
  double _contentSeenMaxPx = 0;
  double _lastContentVisiblePx = 0;
  static const double _contentSeenMinPx = 100;
  int? _scrollStartMono;
  double? _scrollStartPx;
  bool _scrollUserDriven = false;
  int? _missionShownMono;
  String? _missionShownTitle;
  bool _heatmapPopoverOpen = false;
  int? _heatmapOpenedMono;
  String? _heatmapOpenDate;

  static String _restoredSpecies() {
    final saved = AppPrefs.instance.species;
    return const ['cat', 'dog', 'rabbit'].contains(saved) ? saved! : 'cat';
  }

  final List<Map<String, dynamic>> _ranks = [
    {"id": 1, "name": "Recruit", "batch": 1},
    {"id": 2, "name": "Squire", "batch": 1},
    {"id": 3, "name": "Knight", "batch": 2},
    {"id": 4, "name": "Captain", "batch": 3},
    {"id": 5, "name": "Lord", "batch": 4},
    {"id": 6, "name": "Duke", "batch": 4},
    {"id": 7, "name": "Emperor", "batch": 5}
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentLanguage = _loc.currentLocale;
    _aiReport = _chargingAi.analyze(const []);

    _screenShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _screenShakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _screenShakeController, curve: Curves.linear),
    );

    _tracker.contextProvider = _trackingContext;
    _tracker.tapContextResolver = _resolveTapZone;
    _tracker.addLifecycleHooks(
      beforeBackground: _onTrackingBackground,
      afterForeground: _onTrackingForeground,
    );
    _mainScrollController.addListener(_onMainScroll);
    _enterTab('launch');

    // Load real-time battery stats
    _loadRealStats();
    _missionBriefTimer = Timer(const Duration(milliseconds: 650), () async {
      if (!mounted) return;
      if (AppPrefs.instance.participantId == null) {
        await _promptParticipantId(firstTime: true);
      }
      if (mounted) {
        setState(() {
          _updateObscured(() => _missionBriefVisible = true);
        });
        _missionShownMono = _tracker.monoNow;
        _missionShownTitle = _missionTitle();
        _tracker.log('mission_brief_shown', target: _missionShownTitle, props: {
          'score': _aiReport.totalSessions == 0 ? null : _aiReport.score,
          'log_count': _aiReport.totalSessions,
        });
      }
    });
    // Initialize active charging detection
    _initBatteryListener();
    // Schedule background periodic battery log collection
    try {
      scheduleBatteryBackground();
    } catch (e) {
      debugPrint("Failed to schedule background tasks: $e");
    }
  }

  @override
  void dispose() {
    _tracker.removeLifecycleHooks(
      beforeBackground: _onTrackingBackground,
      afterForeground: _onTrackingForeground,
    );
    _tracker.contextProvider = null;
    _tracker.tapContextResolver = null;
    WidgetsBinding.instance.removeObserver(this);
    _batterySubscription?.cancel();
    _stopForegroundTimer();
    _speechTimer?.cancel();
    _missionBriefTimer?.cancel();
    _timelineScrollController.dispose();
    _mainScrollController.dispose();
    _screenShakeController.dispose();
    super.dispose();
  }

  // --- ACTIONS ---

  void _triggerBadgeClick() {
    _tracker.log('rank_badge_tapped',
        userAction: true, props: {'count': _badgeClickCount + 1});
    setState(() {
      _badgeClickCount++;
      if (_badgeClickCount >= 5) {
        if (!_sandboxUnlocked) _tracker.log('sandbox_unlocked');
        _sandboxUnlocked = true;
        _spawnFloatingText(
          _loc.translate('alert_sandbox', defaultVal: 'Sandbox Unlocked!'),
          NeoColors.rpgGold,
        );
        _badgeClickCount = 0;
      }
    });
  }

  void _changeLanguage(String? lang) {
    if (lang != null) {
      _tracker.log('persona_selected', target: lang, userAction: true, props: {
        'from': _currentLanguage,
        'changed': lang != _currentLanguage,
      });
      AppPrefs.instance.persona = lang;
      setState(() {
        _currentLanguage = lang;
        _loc.locale = lang;
      });
    }
  }

  void _spawnFloatingText(String text, Color color) {
    final random = math.Random();
    final xOffset = (random.nextDouble() - 0.5) * 60.0;
    final yOffset = (random.nextDouble() - 0.5) * 20.0;

    final model = FloatingTextModel(
      text: text,
      color: color,
      xOffset: xOffset,
      yOffset: yOffset,
    );

    setState(() {
      _floatingTexts.add(model);
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _floatingTexts.removeWhere((item) => item.id == model.id);
        });
      }
    });
  }

  void _showSpeechBubble(String text) {
    _speechTimer?.cancel();
    setState(() {
      _speechText = text;
      _speechVisible = true;
    });

    _speechTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _speechVisible = false;
        });
      }
    });
  }

  String _getHealthState() {
    if (_hp > 60) return "thriving";
    if (_hp > 30) return "tired";
    return "sick";
  }

  String _getRankName(int index) {
    final id = _ranks[index]["id"] as int;
    final fallback = _ranks[index]["name"] as String;
    return _loc.translate("rank_$id", defaultVal: fallback);
  }

  // --- GEMINI FUNCTIONS ---

  Future<void> _talkToPet() async {
    final state = _getHealthState();
    final rankName = _getRankName(_currentRankIndex);

    String explanation = "";
    if (state == "sick" || state == "tired") {
      if (_globalMetrics.overcharges > _globalMetrics.criticalStarts) {
        explanation =
            "Explain that you are hurt because the user overcharges you at night too many days.";
      } else {
        explanation =
            "Explain that you are starving because the user lets the battery drop too low.";
      }
    }

    final prompt =
        "You are a $state $_currentSpecies at Rank $rankName. Your name is Sparky. $explanation Give a short, 1-sentence quote. If you are thriving, be boastful. If sick or tired, complain about the user's bad habits. Limit your response to 12 words maximum.";
    final sysPrompt = _loc.translate("sys_prompt_talk",
        defaultVal:
            "You are a companion pet. You speak like a primitive caveman...");

    _showSpeechBubble(_loc.translate("thinking", defaultVal: "Thinking..."));

    _tracker.log('talk_tapped', userAction: true);
    final talkStartMono = _tracker.monoNow;
    final response = await _gemini.fetchGeminiWithRetry(
        prompt: prompt, systemPrompt: sysPrompt);
    _tracker.log('talk_response', props: {
      'outcome': response.startsWith('Gemini key missing')
          ? 'key_missing'
          : response == 'Me oracle broken. Try later.'
              ? 'error'
              : 'ok',
      'latency_ms': _tracker.monoNow - talkStartMono,
    });

    // Clean up quotes
    final cleanResponse = response.replaceAll('"', '').trim();
    _showSpeechBubble('"$cleanResponse"');
  }

  Future<void> _askPetAdvice() async {
    final report = _aiReport;
    _tracker.log('advice_generated', userAction: true, props: {
      'score': report.score,
      'has_enough_data': report.hasEnoughData,
      'total_sessions': report.totalSessions,
    });
    setState(() {
      _adviceContent = _buildAiAdviceCard(report);
      if (report.score >= 85 && report.hasEnoughData) {
        _petGlowTrigger++;
      }
    });
    _showSpeechBubble(report.petLine);
  }

  Widget? _adviceContent;

  // --- INTERACTION TRACKING HELPERS ---

  Map<String, Object?> _trackingContext() => {
        'tab': _currentTab,
        'battery_pct': _batteryKnown ? _currentBatteryLevel : null,
        'battery_state': _batteryKnown ? _currentBatteryState : null,
        'is_charging': _batteryKnown ? _isCharging : null,
        'persona': _currentLanguage,
        'species': _currentSpecies,
        'hp': _hp,
        'xp': _xp,
        'rank_index': _currentRankIndex,
      };

  double get _scrollPx =>
      _mainScrollController.hasClients ? _mainScrollController.offset : 0.0;

  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  Map<String, Object?> _resolveTapZone(Offset globalPosition) {
    final base = <String, Object?>{'scroll_px': _round1(_scrollPx)};
    final popup = TrackingNavigatorObserver.instance.topPopupKind;
    if (popup != null) return {...base, 'zone': popup};
    if (_heatmapPopoverOpen) return {...base, 'zone': 'heatmap_popover'};
    if (_missionBriefVisible) return {...base, 'zone': 'mission_brief'};

    for (final entry in _zoneKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(globalPosition);
      if ((Offset.zero & box.size).contains(local)) {
        return {
          ...base,
          'zone': entry.key,
          if (entry.key == 'tab_content') 'content_y': _round1(local.dy),
          if (entry.key == 'tab_content') 'content_h': _round1(box.size.height),
        };
      }
    }
    return {...base, 'zone': 'outside'};
  }

  void _enterTab(String reason) {
    _tabEnteredMono = _tracker.monoNow;
    _tabMaxScrollPx = _scrollPx;
    _tracker.log('tab_entered', target: _currentTab, props: {'reason': reason});
  }

  void _leaveTab(String reason) {
    final entered = _tabEnteredMono;
    if (entered == null) return;
    _closeContentSeen();
    _tracker.log('tab_left', target: _currentTab, props: {
      'reason': reason,
      'duration_ms': _tracker.monoNow - entered,
      'max_scroll_px': _round1(_tabMaxScrollPx),
      'scroll_extent_px': _mainScrollController.hasClients
          ? _round1(_mainScrollController.position.maxScrollExtent)
          : null,
    });
    _tabEnteredMono = null;
  }

  void _onMainScroll() {
    if (_scrollPx > _tabMaxScrollPx) _tabMaxScrollPx = _scrollPx;
  }

  bool _onMainScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _scrollStartMono ??= _tracker.monoNow;
      _scrollStartPx ??= n.metrics.pixels;
    } else if (n is UserScrollNotification &&
        n.direction != ScrollDirection.idle) {
      _scrollUserDriven = true;
    } else if (n is ScrollEndNotification && _scrollStartPx != null) {
      final from = _scrollStartPx!;
      final to = n.metrics.pixels;
      if (_scrollUserDriven && (to - from).abs() >= 8) {
        _tracker.log('scrolled', userAction: true, tapResponse: false, props: {
          'from_px': _round1(from),
          'to_px': _round1(to),
          'extent_px': _round1(n.metrics.maxScrollExtent),
          'viewport_px': _round1(n.metrics.viewportDimension),
          'duration_ms':
              _tracker.monoNow - (_scrollStartMono ?? _tracker.monoNow),
        });
      }
      _scrollStartMono = null;
      _scrollStartPx = null;
      _scrollUserDriven = false;
    }
    return false;
  }

  Key get _tabContentKey => ValueKey('vb-tab-content-$_currentTab');

  void _onTabContentVisibility(VisibilityInfo info) {
    if (!mounted || info.key != _tabContentKey || !_appInForeground) return;
    final px = info.visibleBounds.height;
    _lastContentVisiblePx = px;
    if (px >= _contentSeenMinPx && !_contentObscured) {
      _contentSeenStartMono ??= _tracker.monoNow;
      _contentSeenTab = _currentTab;
      if (px > _contentSeenMaxPx) _contentSeenMaxPx = px;
    } else {
      _closeContentSeen();
    }
  }

  // The mission brief and dialogs cover the tab content, so time under them
  // is not counted as "seen".
  int _modalDepth = 0;
  bool get _contentObscured => _missionBriefVisible || _modalDepth > 0;

  void _updateObscured(VoidCallback change) {
    final wasObscured = _contentObscured;
    change();
    if (!wasObscured && _contentObscured) {
      _closeContentSeen();
    } else if (wasObscured && !_contentObscured) {
      _resumeContentSeenIfVisible();
    }
  }

  void _resumeContentSeenIfVisible() {
    if (!_appInForeground ||
        _contentObscured ||
        _lastContentVisiblePx < _contentSeenMinPx) {
      return;
    }
    _contentSeenStartMono = _tracker.monoNow;
    _contentSeenTab = _currentTab;
    _contentSeenMaxPx = _lastContentVisiblePx;
  }

  void _closeContentSeen() {
    final start = _contentSeenStartMono;
    if (start == null) return;
    _tracker.log('tab_content_seen', target: _contentSeenTab, props: {
      'duration_ms': _tracker.monoNow - start,
      'max_visible_px': _round1(_contentSeenMaxPx),
    });
    _contentSeenStartMono = null;
    _contentSeenMaxPx = 0;
  }

  void _onTrackingBackground() {
    _leaveTab('background');
    _appInForeground = false;
  }

  void _onTrackingForeground() {
    _appInForeground = true;
    _enterTab('resume');
    _resumeContentSeenIfVisible();
  }

  void _selectTab(String tabId) {
    final from = _currentTab;
    _tracker.log('tab_selected', target: tabId, userAction: true, props: {
      'from': from,
      'changed': from != tabId,
    });
    if (from == tabId) return;
    _leaveTab('switch');
    setState(() {
      _currentTab = tabId;
    });
    _lastContentVisiblePx = 0;
    _enterTab('switch');
  }

  static String _fileSafe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<void> _promptParticipantId({required bool firstTime}) async {
    _tracker
        .log('participant_id_prompt_shown', props: {'first_time': firstTime});
    final previous = AppPrefs.instance.participantId;
    _updateObscured(() => _modalDepth++);
    final saved = await showDialog<String>(
      context: context,
      barrierDismissible: !firstTime,
      builder: (dialogContext) => PopScope(
        canPop: !firstTime,
        child: _ParticipantIdDialog(
          initialValue: previous ?? '',
          firstTime: firstTime,
        ),
      ),
    );
    _updateObscured(() => _modalDepth--);

    if (saved != null) {
      AppPrefs.instance.participantId = saved;
      _tracker.log('participant_id_saved', userAction: true, props: {
        'first_time': firstTime,
        'changed': saved != previous,
      });
      if (mounted) setState(() {});
    } else {
      _tracker.log('participant_id_prompt_closed', userAction: true);
    }
  }

  // --- SIMULATION LOGIC ---

  // --- REAL-TIME CHARGING LOGIC & DB HELPERS ---

  Future<void> _loadRealStats() async {
    final sessions = await BatteryDb().getAllChargeSessions();
    _applySessionsToState(sessions);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Import any charging records captured natively while the app was killed
      _importNativeRecordsAndRefresh();
      _startForegroundTimer();
    } else if (state == AppLifecycleState.paused) {
      _saveCheckpoint();
      _stopForegroundTimer();
    }
  }

  /// Imports records from the native PowerConnectionReceiver (captured while
  /// the app was killed), processes them into sessions, then refreshes UI.
  Future<void> _importNativeRecordsAndRefresh() async {
    try {
      final imported = await BatterySnapshotService.importNativeRecords();
      if (imported > 0) {
        await BatteryDb().processRawRecordsIntoSessions();
        debugPrint('VoltBuddy: Imported $imported bg records on resume');
      }
    } catch (e) {
      debugPrint('VoltBuddy: Native record import failed: $e');
    }
    await _checkBatteryAndPendingSession();
  }

  Future<void> _saveCheckpoint() async {
    try {
      final snapshot = await BatterySnapshotService.current();
      await BatteryDb().insertRecord(BatteryRecord(
        timestamp: DateTime.now().toIso8601String(),
        level: snapshot.level,
        state: snapshot.state,
      ));
    } catch (_) {}
  }

  void _initBatteryListener() async {
    // Start native 24/7 foreground service
    await BatterySnapshotService.startBatteryService();

    // Import any records and complete sessions captured natively while app was closed
    await _importNativeRecordsAndRefresh();

    _batterySubscription =
        _battery.onBatteryStateChanged.listen((BatteryState state) {
      _handleBatteryStateChange(state);
    });

    _startForegroundTimer();
  }

  void _startForegroundTimer() {
    _foregroundBatteryTimer?.cancel();
    _foregroundBatteryTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkBatteryAndPendingSession();
    });
  }

  void _stopForegroundTimer() {
    _foregroundBatteryTimer?.cancel();
    _foregroundBatteryTimer = null;
  }

  Future<void> _checkBatteryAndPendingSession() async {
    try {
      final snapshot = await BatterySnapshotService.current();
      final currentLevel = snapshot.level;
      final isNowCharging = snapshot.isChargeSessionState;

      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      // Write record to database
      await BatteryDb().insertRecord(BatteryRecord(
        timestamp: now.toIso8601String(),
        level: currentLevel,
        state: snapshot.state,
      ));

      // Process raw records to detect sessions
      await BatteryDb().processRawRecordsIntoSessions();

      int? startPct;
      if (isNowCharging) {
        final pending = await BatteryDb().getPendingSession();
        if (pending != null) {
          startPct = pending['start_pct'] as int;
        } else {
          await BatteryDb().savePendingSession(currentLevel, dateStr, timeStr);
          startPct = currentLevel;
        }
      } else {
        await BatteryDb().clearPendingSession();
      }

      if (isNowCharging && currentLevel >= 85 && !_chargeNudgeShown) {
        _tracker.log('unplug_nudge_shown', props: {
          'level': currentLevel,
          'severity': currentLevel >= 95 ? 'high' : 'target',
        });
        _chargeNudgeShown = true;
        _warningReactionTrigger++;
        final targetText = currentLevel >= 95
            ? "High charge risk: unplug now."
            : "85% target reached. Unplug soon.";
        _spawnFloatingText("UNPLUG TARGET!", NeoColors.primary);
        _showSpeechBubble(targetText);
      } else if (!isNowCharging || currentLevel < 80) {
        _chargeNudgeShown = false;
      }

      if (isNowCharging != _isCharging || !_batteryKnown) {
        _tracker.log('charge_state_observed', props: {
          'charging': isNowCharging,
          'level': currentLevel,
          'state': snapshot.state,
          'first_reading': !_batteryKnown,
        });
      }
      _batteryKnown = true;

      if (isNowCharging != _isCharging) {
        if (isNowCharging) {
          final pluggedText = snapshot.state == 'connectedNotCharging'
              ? "Plugged In!"
              : "Charging Started!";
          _spawnFloatingText("$pluggedText ⚡", const Color(0xFF2A9D8F));
          _showSpeechBubble(snapshot.state == 'connectedNotCharging'
              ? "Plugged in. I'll watch the battery level."
              : "Charging... Feeling the power! ⚡");
        } else {
          final diff = (_chargingStartLevel != null)
              ? (currentLevel - _chargingStartLevel!)
              : 0;
          if (diff > 0) {
            _spawnFloatingText(
                "Charged to $currentLevel%!", const Color(0xFF2A9D8F));
            _showSpeechBubble("Charged! +$diff% battery.");
          }
        }
        setState(() {
          _isCharging = isNowCharging;
          if (_isCharging) {
            _petGlowTrigger++;
          }
        });
      }

      setState(() {
        _currentBatteryLevel = currentLevel;
        _currentBatteryState = snapshot.state;
        _chargingStartLevel = startPct;
      });

      await _loadRealStats();
    } catch (e) {
      debugPrint("Error in _checkBatteryAndPendingSession: $e");
    }
  }

  Future<void> _handleBatteryStateChange(BatteryState state) async {
    await _checkBatteryAndPendingSession();
  }

  // --- SIMULATION LOGIC REMOVED ---

  DateTime _parseDateTime(String dateStr, String timeStr) {
    try {
      final trimmedDate = dateStr.trim();
      final trimmedTime = timeStr.trim();

      final dateParts = trimmedDate.split(RegExp(r'[-/]'));
      final timeParts = trimmedTime.split(':');

      int year = DateTime.now().year;
      int month = DateTime.now().month;
      int day = DateTime.now().day;
      int hour = 0;
      int minute = 0;
      int second = 0;

      if (dateParts.length == 3) {
        year = int.tryParse(dateParts[0]) ?? year;
        month = int.tryParse(dateParts[1]) ?? month;
        day = int.tryParse(dateParts[2]) ?? day;
      }

      if (timeParts.isNotEmpty) {
        hour = int.tryParse(timeParts[0]) ?? 0;
        if (timeParts.length > 1) {
          minute = int.tryParse(timeParts[1]) ?? 0;
        }
        if (timeParts.length > 2) {
          second = int.tryParse(timeParts[2]) ?? 0;
        }
      }

      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return DateTime.now();
    }
  }

  DateTime _parseDateUtc(String dateStr) {
    try {
      final trimmed = dateStr.trim();
      final parts = trimmed.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final d = int.parse(parts[2]);
        return DateTime.utc(y, m, d);
      }
      final dt = DateTime.parse(trimmed);
      return DateTime.utc(dt.year, dt.month, dt.day);
    } catch (_) {
      final now = DateTime.now();
      return DateTime.utc(now.year, now.month, now.day);
    }
  }

  void _applySessionsToState(List<ChargeSession> sessions) {
    int localHp = 100;
    int localXp = 0;
    int localRankIndex = 0;

    final Map<String, WeeklyMetrics> localWeeklyStats = {};
    final Map<String, DailyMetrics> localDailyData = {};
    final GlobalMetrics localGlobalMetrics = GlobalMetrics();
    final List<Map<String, dynamic>> localTimelineCards = [];

    // Chronologically sort sessions to ensure correct date comparison bounds
    final sortedSessions = List<ChargeSession>.from(sessions)
      ..sort((a, b) {
        final aDt = _parseDateTime(a.startDate, a.startTime);
        final bDt = _parseDateTime(b.startDate, b.startTime);
        return aDt.compareTo(bDt);
      });
    final aiReport = _chargingAi.analyze(sortedSessions);
    final hadLoadedRealStats = _hasLoadedRealStats;
    final previousSessionTotal = _globalMetrics.total;

    if (sortedSessions.isNotEmpty) {
      // Parse dates at UTC midnight to avoid local DST/timezone truncation errors
      final firstDateRaw = sortedSessions.first.startDate;
      final lastDateRaw = sortedSessions.last.endDate;
      final firstDateObj = _parseDateUtc(firstDateRaw);
      final lastDateObj = _parseDateUtc(lastDateRaw);
      final diffDays = lastDateObj.difference(firstDateObj).inDays;
      final diffWeeks = (diffDays / 7.0).ceil();
      final localWeeksCount = diffWeeks == 0 ? 1 : diffWeeks;

      localGlobalMetrics.total = sortedSessions.length;

      for (int idx = 0; idx < sortedSessions.length; idx++) {
        final s = sortedSessions[idx];

        final startDt = _parseDateTime(s.startDate, s.startTime);
        final endDt = _parseDateTime(s.endDate, s.endTime);
        final duration = endDt.difference(startDt);
        final h = duration.inHours;
        final m = duration.inMinutes % 60;
        final durationStr = h > 0 ? '${h}h ${m}m' : '${m}m';

        final startDatePadded =
            "${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}";

        int hpDelta = 0;
        int xpDelta = 0;
        String msg = _loc.translate("msg_standard_charge",
            defaultVal: "Standard Charge");
        String flavorText =
            "Standard charging session. Sparky charged peacefully. Keep it between 20% and 80% to earn extra bonuses next time!";
        Color cardBg = Colors.white;
        Color cardBorder = NeoColors.rpgText;
        Color cardText = NeoColors.rpgText;
        IconData icon = Icons.bolt;

        if (s.isOvercharge) {
          hpDelta = -15;
          xpDelta = 5;
          msg = _loc.translate("msg_overcharge_penalty",
              defaultVal: "Overcharge Penalty");
          flavorText =
              "Ouch! Left plugged in past 95%. This causes sustained high voltage stress, degrading battery health (-15 HP).";
          cardBg = const Color(0xFFFEE2E2);
          cardBorder = NeoColors.rpgBad;
          cardText = NeoColors.rpgBad;
          icon = Icons.battery_alert;
          localGlobalMetrics.overcharges++;
        } else if (s.isCriticalStart) {
          hpDelta = -10;
          xpDelta = 10;
          msg = _loc.translate("msg_critical_starvation",
              defaultVal: "Critical Starvation");
          flavorText =
              "Starvation warning! Charging started below 10%. Deep discharges put heavy stress on battery cells (-10 HP).";
          cardBg = const Color(0xFFFFEDD5);
          cardBorder = NeoColors.primary;
          cardText = const Color(0xFFC2410C);
          icon = Icons.warning_amber;
          localGlobalMetrics.criticalStarts++;
        } else if (s.isPerfectCharge) {
          hpDelta = 5;
          xpDelta = 30;
          msg = _loc.translate("msg_perfect_charge",
              defaultVal: "Perfect Charge!");
          flavorText =
              "Bussin! Started above 20% and stopped before 85%. Excellent battery stewardship (+5 HP, +30 XP).";
          cardBg = const Color(0xFFD1FAE5);
          cardBorder = NeoColors.rpgSurface;
          cardText = const Color(0xFF065F46);
          icon = Icons.stars;
          localGlobalMetrics.perfectCharges++;
        } else {
          hpDelta = 2;
          xpDelta = 15;
        }

        final sDate = _parseDateUtc(startDatePadded);
        final daysDiff = sDate.difference(firstDateObj).inDays;
        final weekNum = (daysDiff / 7).floor() + 1;
        final weekKey = "Week $weekNum";

        localWeeklyStats.putIfAbsent(
            weekKey, () => WeeklyMetrics(weekNum: weekNum, key: weekKey));
        final weekMetrics = localWeeklyStats[weekKey]!;
        weekMetrics.xp += xpDelta;
        weekMetrics.hpDelta += hpDelta;
        weekMetrics.total++;
        if (s.isOvercharge) weekMetrics.over++;
        if (s.isCriticalStart) weekMetrics.crit++;
        if (s.isPerfectCharge) weekMetrics.perf++;

        final dayKey = startDatePadded;
        localDailyData.putIfAbsent(dayKey, () => DailyMetrics(date: dayKey));
        final dailyMetrics = localDailyData[dayKey]!;
        dailyMetrics.sessions++;
        if (s.isOvercharge) dailyMetrics.overcharges++;
        if (s.isCriticalStart) dailyMetrics.criticals++;
        if (s.isPerfectCharge) dailyMetrics.perfects++;

        int sessionScore = 70;
        if (s.isPerfectCharge) {
          sessionScore = 100;
        } else if (s.isCriticalStart) {
          sessionScore = 30;
        } else if (s.isOvercharge) {
          sessionScore = 10;
        }
        dailyMetrics.totalScore += sessionScore;
        dailyMetrics.types.add(s.isOvercharge
            ? 'overcharge'
            : s.isCriticalStart
                ? 'critical'
                : s.isPerfectCharge
                    ? 'perfect'
                    : 'ok');

        localGlobalMetrics.totalXpEarned += xpDelta;

        localHp = math.min(100, math.max(0, localHp + hpDelta));
        localXp += xpDelta;
        while (localXp >= 100 && localRankIndex < 6) {
          localRankIndex++;
          localXp -= 100;
        }
        if (localRankIndex >= 6) {
          localXp = 100;
        }

        dailyMetrics.hpAtEndOfDay = localHp;
        dailyMetrics.rankAtEndOfDay = localRankIndex;
        dailyMetrics.xpAtEndOfDay = localXp;

        final id = _ranks[localRankIndex]["id"] as int;
        final fallback = _ranks[localRankIndex]["name"] as String;
        dailyMetrics.rankName =
            _loc.translate("rank_$id", defaultVal: fallback);

        final cardInfo = {
          'date': startDatePadded,
          'time': s.startTime.trim(),
          'startPct': s.startPct,
          'endPct': s.endPct,
          'msg': msg,
          'hpDelta': hpDelta,
          'xpDelta': xpDelta,
          'cardBg': cardBg,
          'cardBorder': cardBorder,
          'cardText': cardText,
          'icon': icon,
          'duration': durationStr,
          'flavorText': flavorText,
        };

        localTimelineCards.insert(0, cardInfo);
      }

      final bool leveledUp = localRankIndex > _currentRankIndex;
      final bool perfectChargeHappened =
          localGlobalMetrics.perfectCharges > _globalMetrics.perfectCharges;
      final bool xpReached100 = (localXp >= 100 && _xp < 100);
      final bool hasPenalty =
          localGlobalMetrics.overcharges > _globalMetrics.overcharges ||
              localGlobalMetrics.criticalStarts > _globalMetrics.criticalStarts;
      final bool newRealSessionAdded =
          hadLoadedRealStats && localGlobalMetrics.total > previousSessionTotal;
      final newestSession = sortedSessions.last;

      setState(() {
        _hp = localHp;
        _xp = localXp;
        _currentRankIndex = localRankIndex;
        _simFinalHp = localHp;
        _simFinalXp = localXp;
        _simFinalRankIndex = localRankIndex;

        if (leveledUp || perfectChargeHappened || xpReached100) {
          _petGlowTrigger++;
        }

        _weeklyStats.clear();
        _weeklyStats.addAll(localWeeklyStats);
        _dailyData.clear();
        _dailyData.addAll(localDailyData);

        _globalMetrics.total = localGlobalMetrics.total;
        _globalMetrics.overcharges = localGlobalMetrics.overcharges;
        _globalMetrics.criticalStarts = localGlobalMetrics.criticalStarts;
        _globalMetrics.perfectCharges = localGlobalMetrics.perfectCharges;
        _globalMetrics.totalXpEarned = localGlobalMetrics.totalXpEarned;
        _aiReport = aiReport;
        if (_adviceContent != null) {
          _adviceContent = _buildAiAdviceCard(aiReport);
        }

        _timelineCards.clear();
        _timelineCards.addAll(localTimelineCards);

        _simulatedWeeksCount = localWeeksCount;
        _hasLoadedRealStats = true;
        _expandedCardIndices.clear();
      });

      if (newRealSessionAdded) {
        final finalRankName = _getRankName(_currentRankIndex);
        _spawnFloatingText(
          _loc
              .translate("final_rank", defaultVal: "Final Rank: {rank_name}")
              .replaceAll("{rank_name}", finalRankName),
          NeoColors.rpgGold,
        );
        _triggerSessionReward(newestSession);
      }

      if (newRealSessionAdded && (leveledUp || hasPenalty)) {
        _triggerScreenShake();
      }
    } else {
      setState(() {
        _hp = 100;
        _xp = 0;
        _currentRankIndex = 0;
        _simFinalHp = 100;
        _simFinalXp = 0;
        _simFinalRankIndex = 0;
        _weeklyStats.clear();
        _dailyData.clear();
        _globalMetrics.total = 0;
        _globalMetrics.overcharges = 0;
        _globalMetrics.criticalStarts = 0;
        _globalMetrics.perfectCharges = 0;
        _globalMetrics.totalXpEarned = 0;
        _aiReport = aiReport;
        if (_adviceContent != null) {
          _adviceContent = _buildAiAdviceCard(aiReport);
        }
        _timelineCards.clear();
        _simulatedWeeksCount = 0;
        _hasLoadedRealStats = true;
        _expandedCardIndices.clear();
      });
    }
  }

  void _triggerSessionReward(ChargeSession session) {
    _tracker.log('session_feedback_shown', props: {
      'kind': session.isPerfectCharge
          ? 'reward'
          : (session.isOvercharge || session.isCriticalStart)
              ? 'risk'
              : 'logged',
      'start_pct': session.startPct,
      'end_pct': session.endPct,
      'start': '${session.startDate} ${session.startTime}',
      'end': '${session.endDate} ${session.endTime}',
    });
    if (session.isPerfectCharge) {
      setState(() {
        _feedRewardTrigger++;
        _petGlowTrigger++;
      });
      _spawnFloatingText("HEALTHY SNACK!", NeoColors.rpgAccent);
      _showSpeechBubble("Healthy charge logged. Food reward unlocked.");
    } else if (session.isOvercharge || session.isCriticalStart) {
      setState(() {
        _warningReactionTrigger++;
      });
      _spawnFloatingText("RISK DETECTED!", NeoColors.rpgBad);
      _showSpeechBubble("That charging habit hurt my battery health.");
    } else {
      _spawnFloatingText("CHARGE LOGGED!", NeoColors.primary);
      _showSpeechBubble("Good log. Aim for 20-85% to feed me next time.");
    }
  }

  void _triggerScreenShake() {
    _screenShakeController.forward(from: 0.0);
  }

  Future<void> _shareLogsCsv() async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final rect =
        box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;

    _tracker.log('export_tapped', userAction: true);
    try {
      final sessions = await BatteryDb().getAllChargeSessions();
      if (sessions.isEmpty && !_tracker.enabled) {
        _spawnFloatingText("No logs to share!", NeoColors.rpgMuted);
        return;
      }

      // Fetch device info from native Android
      final deviceInfo = await BatterySnapshotService.getDeviceInfo();
      final participantId = AppPrefs.instance.participantId ?? 'UNKNOWN';
      final fileTag = _fileSafe(participantId);
      final tempDir = await getTemporaryDirectory();
      final shareFiles = <XFile>[];

      final csvBuffer = StringBuffer();

      // Device & Study Metadata Header
      csvBuffer.writeln("# ========================================================");
      csvBuffer.writeln("# VoltBuddy Longitudinal Behavioral Research Logs");
      csvBuffer.writeln("# Export Timestamp : ${DateTime.now().toIso8601String()}");
      csvBuffer.writeln("# Participant ID   : $participantId");
      csvBuffer.writeln("# App Version      : $kAppVersion");
      if (deviceInfo != null) {
        final manufacturer = deviceInfo['manufacturer'] ?? 'Unknown';
        final model = deviceInfo['model'] ?? 'Unknown';
        final brand = deviceInfo['brand'] ?? 'Unknown';
        final androidVer = deviceInfo['androidVersion'] ?? 'Unknown';
        final sdkInt = deviceInfo['sdkInt'] ?? 'Unknown';
        csvBuffer.writeln("# Device           : $manufacturer $model ($brand)");
        csvBuffer.writeln("# Android OS       : $androidVer (SDK $sdkInt)");
      }
      final personaLabel = _currentLanguage.toUpperCase();
      final currentRank = _getRankName(_currentRankIndex).toUpperCase();
      csvBuffer.writeln("# Active Persona   : $personaLabel");
      csvBuffer.writeln("# Current Pet Rank : $currentRank");
      csvBuffer.writeln("# Current Pet HP   : $_hp/100");
      csvBuffer.writeln("# Current Species  : $_currentSpecies");
      csvBuffer.writeln("# Total Sessions   : ${sessions.length}");
      csvBuffer.writeln("# ========================================================");
      csvBuffer.writeln("#");

      // Column headers
      csvBuffer.writeln(
          "Session #,Start Date,Start Time,Start Battery %,End Date,End Time,End Battery %,Battery Gained %,Duration (Mins),Charge Speed (%/hr),Time of Day,Is Overnight,Is Perfect Charge,Is Overcharge,Is Critical Start,Is Low Start,Power Source,Active Persona,Pet Rank,Pet HP,Device,Android OS");

      // Data rows
      final deviceLabel = deviceInfo != null
          ? "${deviceInfo['manufacturer']} ${deviceInfo['model']}"
          : "Unknown";
      final osLabel = deviceInfo != null
          ? "Android ${deviceInfo['androidVersion']} (SDK ${deviceInfo['sdkInt']})"
          : "Android";

      int sessionNum = 1;
      for (final s in sessions) {
        csvBuffer.writeln(
            "$sessionNum,${s.startDate},${s.startTime},${s.startPct},${s.endDate},${s.endTime},${s.endPct},${s.batteryGained},${s.durationMinutes},${s.chargeRatePerHour},${s.timeOfDay},${s.isOvernight ? 'TRUE' : 'FALSE'},${s.isPerfectCharge ? 'TRUE' : 'FALSE'},${s.isOvercharge ? 'TRUE' : 'FALSE'},${s.isCriticalStart ? 'TRUE' : 'FALSE'},${s.isLowStart ? 'TRUE' : 'FALSE'},${s.source},$personaLabel,$currentRank,$_hp,$deviceLabel,$osLabel");
        sessionNum++;
      }

      if (sessions.isNotEmpty) {
        final file = File('${tempDir.path}/charge_logs_$fileTag.csv');
        await file.writeAsString(csvBuffer.toString());
        shareFiles.add(XFile(file.path));
      }

      int eventCount = 0;
      if (_tracker.enabled) {
        final eventsCsv = await _tracker.buildCsv(
          participantId: participantId,
          installId: AppPrefs.instance.installId,
          deviceInfo: deviceInfo,
        );
        eventCount = '\n'.allMatches(eventsCsv).length;
        final eventsFile =
            File('${tempDir.path}/interaction_logs_$fileTag.csv');
        await eventsFile.writeAsString(eventsCsv);
        shareFiles.add(XFile(eventsFile.path));
      }

      if (kEventViewerEnabled) {
        // Test builds only: keep a copy readable via `adb pull`.
        final testDir = await getExternalStorageDirectory();
        if (testDir != null) {
          for (final f in shareFiles) {
            await File(f.path)
                .copy('${testDir.path}/${f.path.split('/').last}');
          }
        }
      }

      final result = await SharePlus.instance.share(
        ShareParams(
          files: shareFiles,
          text: 'VoltBuddy Charging & Interaction Logs CSV',
          sharePositionOrigin: rect,
        ),
      );
      _tracker.log('export_result', props: {
        'status': result.status.name,
        'files': shareFiles.length,
        'charge_sessions': sessions.length,
        'csv_lines': eventCount,
      });
    } catch (e) {
      _tracker.log('export_result', props: {'status': 'error'});
      _spawnFloatingText("Share failed: $e", NeoColors.rpgBad);
    }
  }

  Future<void> _showClearConfirmationDialog(BuildContext context) async {
    _tracker.log('clear_dialog_opened', userAction: true);
    final openedMono = _tracker.monoNow;
    _updateObscured(() => _modalDepth++);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: NeoCard(
            backgroundColor: NeoColors.rpgBg,
            borderColor: NeoColors.rpgText,
            borderWidth: 4.0,
            shadowColor: NeoColors.rpgText,
            shadowOffset: const Offset(6, 6),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: NeoColors.rpgMuted, size: 28.0),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loc
                            .translate('clear_dialog_title',
                                defaultVal: 'CLEAR ALL DATA?')
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w900,
                          fontSize: 16.0,
                          color: NeoColors.rpgText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _loc.translate('clear_dialog_desc',
                      defaultVal:
                          'This will permanently wipe all recorded charging sessions. Are you sure you want to proceed?'),
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    fontSize: 12.0,
                    color: NeoColors.rpgText,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    NeoButton(
                      backgroundColor: Colors.white,
                      borderColor: NeoColors.rpgText,
                      shadowColor: NeoColors.rpgText,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        _loc
                            .translate('btn_cancel', defaultVal: 'CANCEL')
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w900,
                          fontSize: 11.0,
                          color: NeoColors.rpgText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    NeoButton(
                      backgroundColor: NeoColors.rpgMuted,
                      borderColor: NeoColors.rpgText,
                      shadowColor: NeoColors.rpgText,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        _loc
                            .translate('btn_clear', defaultVal: 'CONFIRM')
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w900,
                          fontSize: 11.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    _updateObscured(() => _modalDepth--);

    _tracker.log('clear_dialog_closed', userAction: true, props: {
      'result': confirmed == true
          ? 'confirmed'
          : confirmed == false
              ? 'cancelled'
              : 'dismissed',
      'open_ms': _tracker.monoNow - openedMono,
    });
    if (confirmed == true) {
      await BatteryDb().clearAllBatteryData();
      await _loadRealStats();
      _spawnFloatingText("Logs Cleared!", NeoColors.rpgMuted);
    }
  }

  // --- MANUAL DEV INTERACTIONS ---

  void _manualGoodCharge() {
    _tracker.log('sandbox_action', target: 'good_charge', userAction: true);
    final oldRank = _currentRankIndex;
    final oldXp = _xp;
    setState(() {
      _hp = math.min(100, _hp + 15);
      _xp += 30;
      if (_xp >= 100) {
        if (_currentRankIndex < 6) {
          _currentRankIndex++;
          _xp = 0;
        } else {
          _xp = 100;
        }
      }
      _simFinalHp = _hp;
      _simFinalXp = _xp;
      _simFinalRankIndex = _currentRankIndex;

      // Trigger evolution glow on XP milestones or rank increases
      if (_currentRankIndex > oldRank ||
          (_xp >= 100 && oldXp < 100) ||
          _xp == 0) {
        _petGlowTrigger++;
      }
      _feedRewardTrigger++;
    });
    if (_currentRankIndex > oldRank) {
      _triggerScreenShake();
    }
    _spawnFloatingText("+15 HP / +30 XP", NeoColors.rpgAccent);
  }

  void _manualOvercharge() {
    _tracker.log('sandbox_action', target: 'overcharge', userAction: true);
    setState(() {
      _hp = math.max(0, _hp - 20);
      _simFinalHp = _hp;
      _warningReactionTrigger++;
    });
    _triggerScreenShake();
    _spawnFloatingText("-20 HP", NeoColors.rpgBad);
  }

  void _forceState(String state) {
    _tracker.log('sandbox_action',
        target: 'force_state', userAction: true, props: {'value': state});
    setState(() {
      if (state == 'thriving') {
        _hp = 100;
      } else if (state == 'tired') {
        _hp = 50;
      } else {
        _hp = 15;
      }
      _simFinalHp = _hp;
    });
    _spawnFloatingText("Vibe: ${state.toUpperCase()}", NeoColors.rpgText);
  }

  // --- BUILD UI ---

  @override
  Widget build(BuildContext context) {
    final batch = _ranks[_currentRankIndex]["batch"] as int;
    final state = _getHealthState();

    final statusText = state == 'thriving'
        ? _loc.translate('status_thriving', defaultVal: 'Status: Thriving')
        : state == 'tired'
            ? _loc.translate('status_tired', defaultVal: 'Status: Tired')
            : _loc.translate('status_critical', defaultVal: 'Status: Critical');

    final statusColor = state == 'thriving'
        ? NeoColors.rpgAccent
        : state == 'tired'
            ? Colors.grey[500]!
            : NeoColors.rpgMuted;

    final petName =
        _loc.translate('title', defaultVal: 'VoltBuddy').split(' ')[0];

    // Constrain application width on tablet/desktop to max 480px, replicating max-w-md
    return Scaffold(
      backgroundColor: const Color(0xFFE8E5D1),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _screenShakeAnimation,
            builder: (context, child) {
              double dx = 0.0;
              double dy = 0.0;
              if (_screenShakeController.isAnimating) {
                final random = math.Random();
                final progress = _screenShakeAnimation.value;
                final strength = 8.0 * (1.0 - progress);
                dx = (random.nextDouble() - 0.5) * 2 * strength;
                dy = (random.nextDouble() - 0.5) * 2 * strength;
              }
              return Transform.translate(
                offset: Offset(dx, dy),
                child: child,
              );
            },
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480.0),
                decoration: const BoxDecoration(
                  color: NeoColors.rpgBg,
                  border: Border.symmetric(
                    vertical: BorderSide(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
                child: Column(
                  children: [
                    // Header section
                    KeyedSubtree(
                      key: _zoneKeys['header'],
                      child: _buildHeader(),
                    ),

                    // Scrollable body containing Pet Stage and Tabs content
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onMainScrollNotification,
                        child: SingleChildScrollView(
                          controller: _mainScrollController,
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            children: [
                              const SizedBox(height: 80),
                              // Pet Arena Stage
                              KeyedSubtree(
                                key: _zoneKeys['pet_stage'],
                                child: PetRenderer(
                                  species: _currentSpecies,
                                  rankIndex: _currentRankIndex,
                                  batch: batch,
                                  healthState: state,
                                  speechText: _speechText,
                                  speechVisible: _speechVisible,
                                  floatingTexts: _floatingTexts,
                                  glowTrigger: _petGlowTrigger,
                                  feedRewardTrigger: _feedRewardTrigger,
                                  warningReactionTrigger:
                                      _warningReactionTrigger,
                                  isCharging: _isCharging,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Asset details labels
                              KeyedSubtree(
                                key: _zoneKeys['pet_details'],
                                child: _buildPetDetails(
                                    statusText, statusColor, petName),
                              ),

                              // Progress health and exp bars
                              Padding(
                                key: _zoneKeys['progress_bars'],
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0, vertical: 12.0),
                                child: _buildProgressBars(),
                              ),
                              const SizedBox(height: 8),

                              // Neo-brutalist navigation tabs bar
                              KeyedSubtree(
                                key: _zoneKeys['tab_bar'],
                                child: _buildTabBar(),
                              ),

                              // Active Tab container block
                              VisibilityDetector(
                                key: _tabContentKey,
                                onVisibilityChanged: _onTabContentVisibility,
                                child: Container(
                                  key: _zoneKeys['tab_content'],
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(16.0),
                                  child: _buildActiveTabContent(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildMissionBriefOverlay(),
        ],
      ),
    );
  }

  String _missionTitle() {
    if (_isCharging && _currentBatteryLevel >= 85) {
      return 'Unplug quest';
    }
    if (_isCharging) {
      return 'Charge watch active';
    }
    if (_aiReport.totalSessions == 0) {
      return 'First quest';
    }
    if (_aiReport.score < 70 && _aiReport.hasEnoughData) {
      return 'Recovery quest';
    }
    return 'Streak quest';
  }

  String _missionBody() {
    if (_isCharging && _currentBatteryLevel >= 85) {
      return 'Battery is at $_currentBatteryLevel%. Unplug soon to protect the healthy charge window.';
    }
    if (_isCharging) {
      final start =
          _chargingStartLevel == null ? '' : ' from $_chargingStartLevel%';
      return 'VoltBuddy is tracking this session$start. Target: stop around 80-85%.';
    }
    if (_aiReport.totalSessions == 0) {
      return 'Complete one real charging session. VoltBuddy will turn it into your first AI score and habit card.';
    }
    if (_aiReport.score < 70 && _aiReport.hasEnoughData) {
      return _aiReport.nextAction;
    }
    return _aiReport.weeklyReport.focusArea;
  }

  Color _missionColor() {
    if (_isCharging && _currentBatteryLevel >= 85) {
      return NeoColors.rpgBad;
    }
    if (_isCharging) {
      return NeoColors.rpgAccent;
    }
    return _aiScoreColor(_aiReport);
  }

  IconData _missionIcon() {
    if (_isCharging && _currentBatteryLevel >= 85) {
      return Icons.notification_important;
    }
    if (_isCharging) {
      return Icons.bolt;
    }
    if (_aiReport.totalSessions == 0) {
      return Icons.flag;
    }
    return Icons.psychology;
  }

  Widget _buildMissionBriefOverlay() {
    return MissionBriefOverlay(
      visible: _missionBriefVisible,
      title: _missionTitle(),
      body: _missionBody(),
      color: _missionColor(),
      icon: _missionIcon(),
      scoreLabel: _aiReport.scoreLabel,
      score: _aiReport.totalSessions == 0 ? null : _aiReport.score,
      logCount: _aiReport.totalSessions,
      isCharging: _isCharging,
      batteryLevel: _currentBatteryLevel,
      onDismiss: () {
        _tracker.log('mission_brief_dismissed',
            target: _missionShownTitle,
            userAction: true,
            props: {
              'visible_ms': _missionShownMono == null
                  ? null
                  : _tracker.monoNow - _missionShownMono!,
            });
        setState(() {
          _updateObscured(() => _missionBriefVisible = false);
        });
      },
    );
  }

  Widget _buildHeader() {
    final rankName = _getRankName(_currentRankIndex);
    return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.only(top: 44.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: const BoxDecoration(
          color: NeoColors.rpgBg,
          border: Border(
            bottom: BorderSide(color: NeoColors.rpgText, width: 4.0),
          ),
          boxShadow: [
            BoxShadow(
              color: NeoColors.rpgText,
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rowWidget = Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // RANK BADGE (Hidden Easter Egg trigger)
                GestureDetector(
                  onTap: _triggerBadgeClick,
                  child: NeoCard(
                    backgroundColor: Colors.white,
                    borderWidth: 2.5,
                    borderRadius: 12.0,
                    shadowOffset: const Offset(2, 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10.0, vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.star,
                            color: NeoColors.primary, size: 16.0),
                        const SizedBox(width: 4),
                        Text(
                          rankName.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                            color: NeoColors.rpgText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Right controls
                Row(
                  children: [
                    // Language Select Menu
                    NeoCard(
                      backgroundColor: Colors.white,
                      borderWidth: 2.5,
                      borderRadius: 12.0,
                      shadowOffset: const Offset(2, 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _currentLanguage,
                          isDense: true,
                          icon: const Icon(Icons.arrow_drop_down,
                              color: NeoColors.rpgText, size: 16.0),
                          style: const TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                            color: NeoColors.rpgText,
                          ),
                          onChanged: _changeLanguage,
                          onTap: () => _tracker.log('persona_menu_opened',
                              userAction: true),
                          items: const [
                            DropdownMenuItem(
                                value: "regular", child: Text("REGULAR")),
                            DropdownMenuItem(
                                value: "genz", child: Text("GEN Z")),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Time week indicator badge
                    NeoCard(
                      backgroundColor: Colors.white,
                      borderWidth: 2.5,
                      borderRadius: 12.0,
                      shadowOffset: const Offset(2, 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10.0, vertical: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month,
                              color: NeoColors.rpgSurface, size: 15.0),
                          const SizedBox(width: 4),
                          Text(
                            _loc
                                .translate('week_label',
                                    defaultVal: 'Week {num}')
                                .replaceAll('{num}',
                                    '${_simulatedWeeksCount == 0 ? 1 : _simulatedWeeksCount}')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                              color: NeoColors.rpgText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );

            // Responsive scaling for narrow screens
            return constraints.maxWidth < 375
                ? SizedBox(
                    width: constraints.maxWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 375,
                        child: rowWidget,
                      ),
                    ),
                  )
                : rowWidget;
          },
        ),
      ),
    );
  }

  Widget _buildPetDetails(
      String statusText, Color statusColor, String petName) {
    final rankName = _getRankName(_currentRankIndex);
    final speciesName = _currentSpecies.substring(0, 1).toUpperCase() +
        _currentSpecies.substring(1);
    final batch = _ranks[_currentRankIndex]["batch"] as int;

    // "Drip: GOAT Cat (Drop 1)" or similar
    final dripText = _loc
        .translate('asset_label',
            defaultVal: 'Asset: {rank_name} {species} (Batch {batch})')
        .replaceAll('{rank_name}', rankName)
        .replaceAll('{species}', speciesName)
        .replaceAll('{batch}', '$batch');

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: NeoColors.rpgText,
            borderRadius: BorderRadius.circular(16.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
          child: Text(
            dripText.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.bold,
              fontSize: 9.5,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          petName.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w900,
            fontSize: 28.0,
            color: NeoColors.rpgText,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 8),

        // Quick Species Buttons (using Wrap for responsiveness)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6.0,
          runSpacing: 6.0,
          children: [
            _buildSpeciesButton(
                "cat", _loc.translate('cat_btn', defaultVal: '🐱 Cat')),
            _buildSpeciesButton(
                "dog", _loc.translate('dog_btn', defaultVal: '🐶 Dog')),
            _buildSpeciesButton("rabbit",
                _loc.translate('rabbit_btn', defaultVal: '🐰 Rabbit')),
          ],
        ),
        const SizedBox(height: 10),

        // Action Status details row (using Wrap for responsiveness)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            // Status Tag Badge
            Container(
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: NeoColors.rpgText, width: 3.0),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14.0, vertical: 3.0),
              child: Text(
                statusText.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  color: Colors.white,
                ),
              ),
            ),

            // Talk Button
            NeoButton(
              backgroundColor: Colors.white,
              borderWidth: 2.0,
              borderRadius: 20.0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              onPressed: _talkToPet,
              child: Text(
                _loc.translate('talk_btn', defaultVal: 'Talk ✨').toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  color: NeoColors.rpgText,
                ),
              ),
            ),
          ],
        ),
        if (_isCharging) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2A9D8F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NeoColors.rpgText, width: 2.0),
              boxShadow: const [
                BoxShadow(
                  color: NeoColors.rpgText,
                  offset: Offset(2, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  _chargingStatusText(),
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 11.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_isCharging && _currentBatteryLevel >= 85) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: NeoCard(
              backgroundColor: const Color(0xFFFFEDD5),
              borderColor: _currentBatteryLevel >= 95
                  ? NeoColors.rpgBad
                  : NeoColors.primary,
              borderWidth: 3.0,
              shadowOffset: const Offset(3, 3),
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _currentBatteryLevel >= 95
                        ? Icons.battery_alert
                        : Icons.notification_important,
                    color: _currentBatteryLevel >= 95
                        ? NeoColors.rpgBad
                        : NeoColors.primary,
                    size: 24.0,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentBatteryLevel >= 95
                              ? 'HIGH CHARGE RISK'
                              : '85% TARGET REACHED',
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                            color: _currentBatteryLevel >= 95
                                ? NeoColors.rpgBad
                                : NeoColors.rpgText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Unplug soon to reduce full-charge stress during routine charging.',
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                            height: 1.25,
                            color: NeoColors.rpgText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _chargingStatusText() {
    final verb = _currentBatteryState == 'connectedNotCharging'
        ? 'PLUGGED IN'
        : 'CHARGING';
    return _chargingStartLevel != null
        ? "⚡ SPARKY IS $verb... ($_chargingStartLevel% -> $_currentBatteryLevel%)"
        : "⚡ SPARKY IS $verb... ($_currentBatteryLevel%)";
  }

  Widget _buildSpeciesButton(String species, String label) {
    return GestureDetector(
      onTap: () {
        _tracker
            .log('species_selected', target: species, userAction: true, props: {
          'from': _currentSpecies,
          'changed': _currentSpecies != species,
        });
        if (_currentSpecies != species) {
          AppPrefs.instance.species = species;
          setState(() {
            _currentSpecies = species;
            _petGlowTrigger++;
            _spawnFloatingText(species.toUpperCase(), NeoColors.primary);
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: NeoColors.rpgText, width: 2.0),
          boxShadow: const [
            BoxShadow(
              color: NeoColors.rpgText,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            color: NeoColors.rpgText,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBars() {
    Color hpColor = NeoColors.rpgAccent;
    if (_hp <= 60) hpColor = NeoColors.primary;
    if (_hp <= 30) hpColor = NeoColors.rpgMuted;

    return Column(
      children: [
        // Battery/HP Progress bar
        NeoProgressBar(
          label: _loc
              .translate('battery_health', defaultVal: 'Battery Health (HP)')
              .toUpperCase(),
          value: _hp,
          maxValue: 100,
          height: 24.0,
          barColor: hpColor,
          labelColor: NeoColors.rpgText,
          borderWidth: 3.0,
        ),
        const SizedBox(height: 12),

        // Clout/XP Progress bar
        NeoProgressBar(
          label: _loc
              .translate('exp_rank_up', defaultVal: 'Exp to Rank Up')
              .toUpperCase(),
          value: _xp,
          maxValue: 100,
          height: 14.0,
          barColor: NeoColors.primary,
          labelColor: NeoColors.rpgText.withValues(alpha: 0.6),
          borderWidth: 2.5,
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: NeoColors.rpgText,
        border: Border(
          top: BorderSide(color: NeoColors.rpgText, width: 4.0),
        ),
      ),
      child: Row(
        children: [
          _buildTabButton(
              "tab-stats", _loc.translate('tab_stats', defaultVal: 'Stats')),
          _buildTabButton(
              "tab-tips", _loc.translate('tab_tips', defaultVal: 'Tips')),
          _buildTabButton(
              "tab-data", _loc.translate('tab_logs', defaultVal: 'Logs')),
          if (_sandboxUnlocked)
            _buildTabButton(
                "tab-sandbox", _loc.translate('tab_sandbox', defaultVal: 'Dev'),
                isSandbox: true),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabId, String label, {bool isSandbox = false}) {
    final active = _currentTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectTab(tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          decoration: BoxDecoration(
            color: active ? NeoColors.primary : NeoColors.rpgText,
            border: Border(
              right: const BorderSide(color: Colors.white24, width: 1.0),
              bottom: active
                  ? const BorderSide(color: Colors.black26, width: 4.0)
                  : BorderSide.none,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 10.0,
              fontWeight: FontWeight.w900,
              color: isSandbox
                  ? (active ? Colors.white : NeoColors.primary)
                  : Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_currentTab) {
      case 'tab-tips':
        return _buildTipsTab();
      case 'tab-data':
        return _buildLogsTab();
      case 'tab-sandbox':
        return _buildSandboxTab();
      case 'tab-stats':
      default:
        return _buildStatsTab();
    }
  }

  Widget _buildStatsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWeeklyReportPanel(),
        const SizedBox(height: 16),

        // Calendar Heatmap section
        HeatmapWidget(
          dailyData: _dailyData,
          globalMetrics: _globalMetrics,
          onDaySelected: (dayMetrics, petQuote) {
            _heatmapPopoverOpen = true;
            _heatmapOpenedMono = _tracker.monoNow;
            _heatmapOpenDate = dayMetrics.date;
            _tracker.log('heatmap_day_opened',
                target: dayMetrics.date,
                userAction: true,
                props: {
                  'sessions': dayMetrics.sessions,
                  'avg_score': dayMetrics.averageScore,
                });
            setState(() {
              if (dayMetrics.hpAtEndOfDay != null)
                _hp = dayMetrics.hpAtEndOfDay!;
              if (dayMetrics.xpAtEndOfDay != null)
                _xp = dayMetrics.xpAtEndOfDay!;
              if (dayMetrics.rankAtEndOfDay != null)
                _currentRankIndex = dayMetrics.rankAtEndOfDay!;
            });
            _showSpeechBubble(petQuote);

            if (dayMetrics.averageScore >= 80) {
              setState(() {
                _petGlowTrigger++;
              });
            }
          },
          onDayDismissed: () {
            if (_heatmapPopoverOpen) {
              _tracker.log('heatmap_day_closed',
                  target: _heatmapOpenDate,
                  userAction: true,
                  props: {
                    'open_ms': _tracker.monoNow -
                        (_heatmapOpenedMono ?? _tracker.monoNow),
                  });
            }
            _heatmapPopoverOpen = false;
            if (!mounted) return;
            setState(() {
              _hp = _simFinalHp;
              _xp = _simFinalXp;
              _currentRankIndex = _simFinalRankIndex;
              _speechVisible = false;
            });
          },
        ),
        const SizedBox(height: 16),

        // Journey map timeline
        JourneyMapWidget(
          weeklyStats: _weeklyStats,
          totalXp: _globalMetrics.totalXpEarned,
          xpPerWeek: _simulatedWeeksCount > 0
              ? _globalMetrics.totalXpEarned / _simulatedWeeksCount
              : 0.0,
          totalWeeks: _simulatedWeeksCount,
        ),
      ],
    );
  }

  Widget _buildWeeklyReportPanel() {
    final report = _aiReport.weeklyReport;
    final scoreColor = !report.hasData
        ? NeoColors.rpgSilver
        : report.score >= 85
            ? NeoColors.rpgAccent
            : report.score >= 70
                ? NeoColors.primary
                : report.score >= 50
                    ? NeoColors.rpgMuted
                    : NeoColors.rpgBad;

    return NeoCard(
      backgroundColor: const Color(0xFFE8F5EF),
      borderColor: NeoColors.rpgText,
      borderWidth: 3.0,
      shadowOffset: const Offset(3, 3),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: scoreColor, width: 3.0),
                  boxShadow: const [
                    BoxShadow(
                      color: NeoColors.rpgText,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      report.hasData ? '${report.score}' : '--',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 18.0,
                        color: scoreColor,
                      ),
                    ),
                    const Text(
                      'WEEK',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 7.5,
                        color: NeoColors.rpgText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THIS WEEK REPORT',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 13.0,
                        color: NeoColors.rpgText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${report.dateRange} | ${report.trendLabel}',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 10.0,
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              _buildAiMetricChip(
                icon: Icons.bolt,
                label: 'sessions',
                value: '${report.totalSessions}',
                color: NeoColors.rpgText,
              ),
              _buildAiMetricChip(
                icon: Icons.restaurant,
                label: 'healthy',
                value: '${report.healthySessions}',
                color: NeoColors.rpgAccent,
              ),
              _buildAiMetricChip(
                icon: Icons.warning_amber,
                label: 'risky',
                value: '${report.riskySessions}',
                color: report.riskySessions > 0
                    ? NeoColors.rpgBad
                    : NeoColors.rpgSilver,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: NeoColors.rpgText, width: 2.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BEST: ${report.bestHabit}',
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    height: 1.25,
                    color: NeoColors.rpgText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'FOCUS: ${report.focusArea}',
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    height: 1.25,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _aiScoreColor(ChargingAiReport report) {
    if (report.totalSessions == 0) return NeoColors.rpgSilver;
    if (report.score >= 85) return NeoColors.rpgAccent;
    if (report.score >= 70) return NeoColors.primary;
    if (report.score >= 50) return NeoColors.rpgMuted;
    return NeoColors.rpgBad;
  }

  Color _habitSeverityColor(HabitSeverity severity) {
    switch (severity) {
      case HabitSeverity.good:
        return NeoColors.rpgAccent;
      case HabitSeverity.watch:
        return NeoColors.primary;
      case HabitSeverity.risky:
        return NeoColors.rpgBad;
    }
  }

  IconData _habitSeverityIcon(HabitSeverity severity) {
    switch (severity) {
      case HabitSeverity.good:
        return Icons.check_circle;
      case HabitSeverity.watch:
        return Icons.visibility;
      case HabitSeverity.risky:
        return Icons.warning_amber;
    }
  }

  Color _recommendationColor(RecommendationPriority priority) {
    switch (priority) {
      case RecommendationPriority.low:
        return NeoColors.rpgAccent;
      case RecommendationPriority.medium:
        return NeoColors.primary;
      case RecommendationPriority.high:
        return NeoColors.rpgBad;
    }
  }

  String _priorityLabel(RecommendationPriority priority) {
    switch (priority) {
      case RecommendationPriority.low:
        return 'LOW';
      case RecommendationPriority.medium:
        return 'MED';
      case RecommendationPriority.high:
        return 'HIGH';
    }
  }

  Widget _buildAiMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14.0),
          const SizedBox(width: 5),
          Text(
            '$label $value'.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w900,
              fontSize: 9.0,
              color: NeoColors.rpgText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCoachPanel() {
    final report = _aiReport;
    final scoreColor = _aiScoreColor(report);
    final scoreText = report.totalSessions == 0 ? '--' : '${report.score}';

    return NeoCard(
      backgroundColor: const Color(0xFFFFF7D6),
      borderColor: NeoColors.rpgText,
      borderWidth: 3.0,
      shadowOffset: const Offset(3, 3),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor, width: 5.0),
                  boxShadow: const [
                    BoxShadow(
                      color: NeoColors.rpgText,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      scoreText,
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: report.totalSessions == 0 ? 21.0 : 24.0,
                        color: scoreColor,
                      ),
                    ),
                    const Text(
                      'AI SCORE',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 8.0,
                        color: NeoColors.rpgText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.psychology,
                            color: NeoColors.primary, size: 20.0),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'VOLTBUDDY AI COACH',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.w900,
                              fontSize: 13.0,
                              color: NeoColors.rpgText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${report.scoreLabel} | ${report.riskLevel}',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 12.0,
                        color: scoreColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.confidenceLabel.toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.bold,
                        fontSize: 9.5,
                        color: NeoColors.rpgText.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.summary,
            style: const TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
              height: 1.35,
              color: NeoColors.rpgText,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7.0,
            runSpacing: 7.0,
            children: [
              _buildAiMetricChip(
                icon: Icons.history,
                label: 'logs',
                value: '${report.totalSessions}',
                color: NeoColors.rpgText,
              ),
              _buildAiMetricChip(
                icon: Icons.stars,
                label: 'ideal',
                value: '${report.perfectSessions}',
                color: NeoColors.rpgAccent,
              ),
              _buildAiMetricChip(
                icon: Icons.battery_alert,
                label: 'risk',
                value:
                    '${report.overchargeSessions + report.criticalStartSessions}',
                color:
                    report.overchargeSessions + report.criticalStartSessions > 0
                        ? NeoColors.rpgBad
                        : NeoColors.rpgSilver,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: NeoColors.rpgText, width: 2.0),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.flag, color: scoreColor, size: 18.0),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.nextAction,
                    style: const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w900,
                      fontSize: 11.0,
                      height: 1.25,
                      color: NeoColors.rpgText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitRow(ChargingHabit habit) {
    final color = _habitSeverityColor(habit.severity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_habitSeverityIcon(habit.severity), color: color, size: 18.0),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.title.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  habit.evidence,
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                    height: 1.25,
                    color: NeoColors.rpgText.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationRow(ChargingRecommendation recommendation) {
    final color = _recommendationColor(recommendation.priority);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: NeoColors.rpgText, width: 1.5),
            ),
            child: Text(
              _priorityLabel(recommendation.priority),
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w900,
                fontSize: 8.0,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.title.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    color: NeoColors.rpgText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  recommendation.body,
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                    height: 1.25,
                    color: NeoColors.rpgText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  recommendation.impact.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 8.5,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAdviceCard(ChargingAiReport report) {
    return NeoCard(
      borderWidth: 3.0,
      shadowOffset: const Offset(3, 3),
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: NeoColors.primary),
              const SizedBox(width: 8),
              Text(
                _loc
                    .translate('pets_advice', defaultVal: 'Pet Speaks')
                    .toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  color: NeoColors.rpgText,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.black26),
          const SizedBox(height: 6),
          Text(
            report.petLine,
            style: const TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 13.0,
              height: 1.35,
              fontWeight: FontWeight.bold,
              color: NeoColors.rpgText,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'DETECTED HABITS',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w900,
              fontSize: 10.0,
              color: NeoColors.rpgText,
            ),
          ),
          const SizedBox(height: 8),
          ...report.habits.take(4).map(_buildHabitRow),
          const SizedBox(height: 4),
          const Text(
            'NEXT RECOMMENDATIONS',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w900,
              fontSize: 10.0,
              color: NeoColors.rpgText,
            ),
          ),
          const SizedBox(height: 8),
          ...report.recommendations.take(4).map(_buildRecommendationRow),
        ],
      ),
    );
  }

  Widget _buildTipsTab() {
    final adviceBtn =
        _loc.translate('ask_advice_btn', defaultVal: 'Generate AI Advice');
    final wisdomTitle1 = _loc.translate('rule_20_80_title',
        defaultVal: 'The Golden Rule: 20-80');
    final wisdomDesc1 = _loc.translate('rule_20_80_desc',
        defaultVal: 'Keep battery energy between 20-80%...');
    final wisdomTitle2 = _loc.translate('night_charge_title',
        defaultVal: 'Beware the Night Charge');
    final wisdomDesc2 = _loc.translate('night_charge_desc',
        defaultVal: 'Leaving plugged in overnight damages HP...');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Advice header
        Row(
          children: [
            const Icon(Icons.psychology, color: NeoColors.primary),
            const SizedBox(width: 8),
            Text(
              _loc
                  .translate('pets_advice', defaultVal: "Pet's Advice")
                  .toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                  color: NeoColors.rpgText),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildAiCoachPanel(),
        const SizedBox(height: 16),

        // Ask advice button
        NeoButton(
          backgroundColor: NeoColors.primary,
          borderColor: NeoColors.rpgText,
          shadowColor: NeoColors.rpgText,
          onPressed: _askPetAdvice,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                adviceBtn.toUpperCase(),
                style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontSize: 12.0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Generated Gemini content
        _adviceContent ??
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: NeoColors.rpgBg,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                    color: NeoColors.rpgText.withOpacity(0.2), width: 2.0),
              ),
              child: Center(
                child: Text(
                  _loc.translate('run_sim_tips_msg',
                      defaultVal:
                          'Tap Generate AI Advice to see the habits and recommendations behind your score.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    color: NeoColors.rpgText.withOpacity(0.6),
                    fontSize: 12.0,
                  ),
                ),
              ),
            ),
        const SizedBox(height: 20),

        // General wisdom header
        Text(
          _loc
              .translate('general_wisdom', defaultVal: 'General Wisdom')
              .toUpperCase(),
          style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
              color: NeoColors.rpgText.withOpacity(0.6)),
        ),
        const Divider(color: Colors.black12, height: 12),
        const SizedBox(height: 6),

        // Rule 20-80 Card
        NeoCard(
          backgroundColor: const Color(0xFFE8E5D1),
          borderWidth: 2.0,
          shadowOffset: const Offset(2, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.battery_charging_full,
                  color: NeoColors.rpgSurface, size: 28.0),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wisdomTitle1.toUpperCase(),
                      style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: NeoColors.rpgText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wisdomDesc1,
                      style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 11.5,
                          height: 1.3,
                          color: NeoColors.rpgText.withOpacity(0.8)),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Night charging is an ick Card
        NeoCard(
          backgroundColor: const Color(0xFFE8E5D1),
          borderWidth: 2.0,
          shadowOffset: const Offset(2, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.bedtime, color: NeoColors.rpgMuted, size: 28.0),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wisdomTitle2.toUpperCase(),
                      style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: NeoColors.rpgText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wisdomDesc2,
                      style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 11.5,
                          height: 1.3,
                          color: NeoColors.rpgText.withOpacity(0.8)),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Real data header row
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, color: NeoColors.rpgText),
                SizedBox(width: 8),
                Text(
                  "REAL CHARGE HISTORY",
                  style: TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.bold,
                      fontSize: 13.0,
                      color: NeoColors.rpgText),
                ),
              ],
            ),
            if (_timelineCards.isNotEmpty || _tracker.enabled)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NeoButton(
                    backgroundColor: NeoColors.primary,
                    borderColor: NeoColors.rpgText,
                    shadowColor: NeoColors.rpgText,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10.0, vertical: 6.0),
                    onPressed: _shareLogsCsv,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share, color: Colors.white, size: 12.0),
                        SizedBox(width: 4),
                        Text(
                          "SHARE CSV",
                          style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 10.0),
                        ),
                      ],
                    ),
                  ),
                  if (_timelineCards.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    NeoButton(
                      backgroundColor: NeoColors.rpgMuted,
                      borderColor: NeoColors.rpgText,
                      shadowColor: NeoColors.rpgText,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10.0, vertical: 6.0),
                      onPressed: () => _showClearConfirmationDialog(context),
                      child: const Text(
                        "CLEAR ALL",
                        style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontSize: 10.0),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _promptParticipantId(firstTime: false),
          child: Row(
            children: [
              const Icon(Icons.badge, color: NeoColors.rpgText, size: 14.0),
              const SizedBox(width: 6),
              Text(
                "PARTICIPANT ID: ${AppPrefs.instance.participantId ?? 'NOT SET'}",
                style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    fontSize: 10.5,
                    color: NeoColors.rpgText),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit, color: NeoColors.rpgText, size: 12.0),
            ],
          ),
        ),
        if (_timelineCards.isEmpty) ...[
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: NeoColors.rpgBg,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: NeoColors.rpgText, width: 2.0),
            ),
            child: const Center(
              child: Text(
                "No charging sessions recorded yet.\nPlug in your device to log real-time data!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.bold,
                  color: NeoColors.rpgText,
                  fontSize: 12.0,
                ),
              ),
            ),
          ),
        ],

        // Running logs Cards timeline list
        if (_timelineCards.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            "REAL CHARGING SESSIONS",
            style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
                color: NeoColors.rpgText),
          ),
          const Divider(color: Colors.black26),
          const SizedBox(height: 6),
          ListView.builder(
            controller: _timelineScrollController,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _timelineCards.length,
            itemBuilder: (context, idx) {
              final card = _timelineCards[idx];
              final String timeLabel =
                  "${card['date']} ${card['time'].toString().substring(0, 5)}";
              final String rangeLabel =
                  "${card['startPct']}% → ${card['endPct']}%";
              final int hpDelta = card['hpDelta'] as int;
              final int xpDelta = card['xpDelta'] as int;
              final bool isExpanded = _expandedCardIndices.contains(idx);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: GestureDetector(
                  onTap: () {
                    _tracker.log('log_card_toggled', userAction: true, props: {
                      'index': idx,
                      'expanded': !isExpanded,
                      'session_date': card['date'],
                    });
                    setState(() {
                      if (isExpanded) {
                        _expandedCardIndices.remove(idx);
                      } else {
                        _expandedCardIndices.add(idx);
                      }
                    });
                  },
                  child: NeoCard(
                    backgroundColor: card['cardBg'] as Color,
                    borderColor: card['cardBorder'] as Color,
                    borderWidth: 3.0,
                    shadowOffset: const Offset(2, 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: card['cardText'] as Color,
                                        width: 1.5),
                                  ),
                                  child: Icon(card['icon'] as IconData,
                                      color: card['cardText'] as Color,
                                      size: 18.0),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      timeLabel.toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: (card['cardText'] as Color)
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    Text(
                                      rangeLabel,
                                      style: const TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 13.0,
                                        fontWeight: FontWeight.w900,
                                        color: NeoColors.rpgText,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(6.0),
                                    border: Border.all(
                                        color: card['cardText'] as Color,
                                        width: 1.0),
                                  ),
                                  child: Text(
                                    card['msg'].toString().toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'Space Grotesk',
                                      fontSize: 8.0,
                                      fontWeight: FontWeight.w900,
                                      color: card['cardText'] as Color,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${hpDelta > 0 ? '+$hpDelta' : hpDelta} HP | +$xpDelta XP",
                                  style: const TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: NeoColors.rpgText,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(color: Colors.black12, height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "SESSION DETAILS",
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.w900,
                                        color: (card['cardText'] as Color)
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                    Text(
                                      "Duration: ${card['duration']}",
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.bold,
                                        color: NeoColors.rpgText
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  card['flavorText'] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 11.0,
                                    height: 1.3,
                                    color: NeoColors.rpgText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          crossFadeState: isExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 250),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ]
      ],
    );
  }

  Widget _buildSandboxTab() {
    final flexProgTitle = _loc.translate('tier_progression',
        defaultVal: '7-Tier Rank Progression');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Level tier Progression setter
        Text(
          flexProgTitle.toUpperCase(),
          style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.bold,
              fontSize: 10.0,
              color: NeoColors.rpgText.withOpacity(0.6)),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: NeoColors.rpgText, width: 2.0),
            boxShadow: const [
              BoxShadow(
                color: NeoColors.rpgText,
                offset: Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: DropdownButton<int>(
            value: _currentRankIndex,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.bold,
                color: NeoColors.rpgText,
                fontSize: 13.0),
            onChanged: (val) {
              if (val != null) {
                _tracker.log('sandbox_action',
                    target: 'set_rank',
                    userAction: true,
                    props: {'value': val});
                setState(() {
                  _currentRankIndex = val;
                  _simFinalRankIndex = val;
                });
                _spawnFloatingText("RANK ${val + 1}", NeoColors.rpgGold);
              }
            },
            items: List.generate(
              _ranks.length,
              (idx) => DropdownMenuItem(
                value: idx,
                child: Text(
                  "${_ranks[idx]['id']}. ${_getRankName(idx)} (Batch ${_ranks[idx]['batch']})",
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Interaction quick buttons
        Row(
          children: [
            Expanded(
              child: NeoButton(
                backgroundColor: NeoColors.rpgSurface,
                onPressed: _manualGoodCharge,
                child: Column(
                  children: [
                    const Icon(Icons.battery_charging_full,
                        color: Colors.white),
                    const SizedBox(height: 4),
                    Text(
                      _loc
                          .translate('good_charge',
                              defaultVal: 'Good Charge (+XP)')
                          .toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.bold,
                          fontSize: 9.0,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NeoButton(
                backgroundColor: NeoColors.rpgMuted,
                onPressed: _manualOvercharge,
                child: Column(
                  children: [
                    const Icon(Icons.battery_alert, color: Colors.white),
                    const SizedBox(height: 4),
                    Text(
                      _loc
                          .translate('overcharge',
                              defaultVal: 'Overcharge (-HP)')
                          .toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.bold,
                          fontSize: 9.0,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Force Health status buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildForceStateBtn('thriving', "THRIVING"),
            const SizedBox(width: 8),
            _buildForceStateBtn('tired', "TIRED"),
            const SizedBox(width: 8),
            _buildForceStateBtn('sick', "SICK"),
          ],
        ),
        if (kEventViewerEnabled && _tracker.enabled) ...[
          const SizedBox(height: 16),
          _buildEventViewer(),
        ],
      ],
    );
  }

  /// Test-build-only list of the most recent interaction events.
  Widget _buildEventViewer() {
    return StatefulBuilder(
      builder: (context, setViewerState) =>
          FutureBuilder<List<Map<String, Object?>>>(
        future: _tracker.latest(40),
        builder: (context, snap) {
          final rows = snap.data ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "EVENT LOG (LATEST ${rows.length})",
                      style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.bold,
                          fontSize: 10.0,
                          color: NeoColors.rpgText),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => setViewerState(() {}),
                  ),
                ],
              ),
              for (final r in rows)
                Text(
                  "${r['session_seq'] ?? 'nat'} ${r['event']}"
                  "${r['target'] != null ? ' [${r['target']}]' : ''}"
                  " ${r['props'] ?? ''}",
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 9.0),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForceStateBtn(String value, String label) {
    return GestureDetector(
      onTap: () => _forceState(value),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: NeoColors.rpgText, width: 2.0),
          boxShadow: const [
            BoxShadow(
              color: NeoColors.rpgText,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            color: NeoColors.rpgText,
          ),
        ),
      ),
    );
  }
}

class MissionBriefOverlay extends StatefulWidget {
  final bool visible;
  final String title;
  final String body;
  final Color color;
  final IconData icon;
  final String scoreLabel;
  final int? score;
  final int logCount;
  final bool isCharging;
  final int batteryLevel;
  final VoidCallback onDismiss;

  const MissionBriefOverlay({
    super.key,
    required this.visible,
    required this.title,
    required this.body,
    required this.color,
    required this.icon,
    required this.scoreLabel,
    required this.score,
    required this.logCount,
    required this.isCharging,
    required this.batteryLevel,
    required this.onDismiss,
  });

  @override
  State<MissionBriefOverlay> createState() => _MissionBriefOverlayState();
}

class _MissionBriefOverlayState extends State<MissionBriefOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: Container(
            color: Colors.black.withValues(alpha: 0.34),
            child: SafeArea(
              child: Center(
                child: AnimatedSlide(
                  offset: widget.visible ? Offset.zero : const Offset(0, 0.10),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  child: AnimatedScale(
                    scale: widget.visible ? 1.0 : 0.90,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            return NeoCard(
                              backgroundColor: const Color(0xFFFFF7D6),
                              borderColor: NeoColors.rpgText,
                              borderWidth: 4.0,
                              shadowOffset: const Offset(7, 7),
                              padding: EdgeInsets.zero,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [
                                    _MissionScanLayer(
                                      progress: _controller.value,
                                      color: widget.color,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(18.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildTopRow(),
                                          const SizedBox(height: 14),
                                          _buildMissionText(),
                                          const SizedBox(height: 14),
                                          _buildProgressPanel(),
                                          const SizedBox(height: 14),
                                          _buildMissionStats(),
                                          const SizedBox(height: 16),
                                          _buildActionRow(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse =
                1.0 + math.sin(_controller.value * math.pi * 2) * 0.05;
            return Transform.scale(
              scale: pulse,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: NeoColors.rpgText, width: 3.0),
                  boxShadow: const [
                    BoxShadow(
                      color: NeoColors.rpgText,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 30),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI COMPANION BOOT',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  fontSize: 10.0,
                  color: NeoColors.rpgText.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  fontSize: 20.0,
                  height: 1.0,
                  color: NeoColors.rpgText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMissionText() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: NeoColors.rpgText, width: 2.5),
      ),
      child: Text(
        widget.body,
        style: const TextStyle(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w900,
          fontSize: 13.0,
          height: 1.35,
          color: NeoColors.rpgText,
        ),
      ),
    );
  }

  Widget _buildProgressPanel() {
    final level = widget.isCharging ? widget.batteryLevel : 0;
    final progress = widget.isCharging ? (level / 100.0).clamp(0.0, 1.0) : 0.18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              widget.isCharging ? Icons.battery_charging_full : Icons.memory,
              color: widget.color,
              size: 17,
            ),
            const SizedBox(width: 6),
            Text(
              widget.isCharging
                  ? 'LIVE CHARGE MONITOR: $level%'
                  : 'LOCAL AI SCAN READY',
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
                color: NeoColors.rpgText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NeoColors.rpgText, width: 2.5),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final animatedBoost =
                  math.sin(_controller.value * math.pi * 2) * 0.03;
              final width = constraints.maxWidth *
                  (progress + animatedBoost).clamp(0.08, 1.0);
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: width,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMissionStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatChip(
            icon: Icons.psychology,
            label: 'AI',
            value: widget.score == null
                ? widget.scoreLabel
                : '${widget.score} ${widget.scoreLabel}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatChip(
            icon: Icons.receipt_long,
            label: 'LOGS',
            value: '${widget.logCount}',
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 9.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: NeoColors.rpgText, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: NeoColors.rpgText,
            offset: Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: widget.color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: $value'.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w900,
                fontSize: 9.0,
                color: NeoColors.rpgText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Offline. Explainable. Based on your real logs.'.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w900,
              fontSize: 9.5,
              height: 1.25,
              color: NeoColors.rpgText.withValues(alpha: 0.70),
            ),
          ),
        ),
        const SizedBox(width: 10),
        NeoButton(
          backgroundColor: widget.color,
          borderColor: NeoColors.rpgText,
          shadowColor: NeoColors.rpgText,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          onPressed: widget.onDismiss,
          child: const Text(
            'START MISSION',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _MissionScanLayer extends StatelessWidget {
  final double progress;
  final Color color;

  const _MissionScanLayer({
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _MissionScanPainter(
          progress: progress,
          color: color,
        ),
      ),
    );
  }
}

class _MissionScanPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _MissionScanPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = NeoColors.rpgText.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double y = 10; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final scanY = size.height * progress;
    final scanPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..strokeWidth = 26
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(18, scanY),
      Offset(size.width - 18, scanY),
      scanPaint,
    );

    final dotPaint = Paint()..color = color.withValues(alpha: 0.18);
    for (var i = 0; i < 8; i++) {
      final x = ((i * 71) + progress * size.width) % size.width;
      final y = 16.0 + (i * 31) % math.max(1, size.height - 32);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MissionScanPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class NeoProgressBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final double height;
  final Color barColor;
  final Color labelColor;
  final double borderWidth;

  const NeoProgressBar({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    required this.height,
    required this.barColor,
    required this.labelColor,
    required this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: value.toDouble()),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, animVal, child) {
            final displayVal = animVal.round();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    fontSize: height >= 20 ? 11.0 : 10.0,
                    color: labelColor,
                  ),
                ),
                Text(
                  "$displayVal / $maxValue",
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    fontSize: height >= 20 ? 11.0 : 10.0,
                    color: labelColor,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(height),
            border: Border.all(color: NeoColors.rpgText, width: borderWidth),
            boxShadow: const [
              BoxShadow(
                color: NeoColors.rpgText,
                offset: Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: value.toDouble()),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, animVal, child) {
                final widthFactor =
                    math.max(0.0, math.min(1.0, animVal / maxValue));
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widthFactor,
                  child: Container(
                    decoration: BoxDecoration(
                      color: barColor,
                      border: Border(
                        right: BorderSide(
                          color: NeoColors.rpgText,
                          width: borderWidth + 1.0,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// One-time Student ID prompt for the Phase 2 study. Owns its text
/// controller so it is disposed only after the dialog's exit animation.
class _ParticipantIdDialog extends StatefulWidget {
  final String initialValue;
  final bool firstTime;

  const _ParticipantIdDialog({
    required this.initialValue,
    required this.firstTime,
  });

  @override
  State<_ParticipantIdDialog> createState() => _ParticipantIdDialogState();
}

class _ParticipantIdDialogState extends State<_ParticipantIdDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{4,20}$').hasMatch(value)) {
      setState(
          () => _error = 'Enter your Student ID (letters and numbers only).');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: NeoCard(
        backgroundColor: NeoColors.rpgBg,
        borderColor: NeoColors.rpgText,
        borderWidth: 4.0,
        shadowColor: NeoColors.rpgText,
        shadowOffset: const Offset(6, 6),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.badge, color: NeoColors.primary, size: 26.0),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STUDY PARTICIPANT ID',
                    style: TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w900,
                      fontSize: 16.0,
                      color: NeoColors.rpgText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Enter your Student ID once. It is added to your exported files so the research team can match them to you.',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.bold,
                fontSize: 12.0,
                color: NeoColors.rpgText,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w900,
                fontSize: 16.0,
                color: NeoColors.rpgText,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. 202301173',
                errorText: _error,
                filled: true,
                fillColor: Colors.white,
                border: const OutlineInputBorder(
                  borderSide: BorderSide(color: NeoColors.rpgText, width: 2.0),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!widget.firstTime) ...[
                  NeoButton(
                    backgroundColor: Colors.white,
                    borderColor: NeoColors.rpgText,
                    shadowColor: NeoColors.rpgText,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w900,
                        fontSize: 11.0,
                        color: NeoColors.rpgText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                NeoButton(
                  backgroundColor: NeoColors.primary,
                  borderColor: NeoColors.rpgText,
                  shadowColor: NeoColors.rpgText,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  onPressed: _submit,
                  child: const Text(
                    'SAVE',
                    style: TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w900,
                      fontSize: 11.0,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
