import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/simulation_models.dart';

import 'services/localization_service.dart';
import 'services/gemini_service.dart';
import 'widgets/neo_brutalist.dart';
import 'widgets/pet_renderer.dart';
import 'widgets/heatmap_widget.dart';
import 'widgets/journey_map_widget.dart';

import 'package:battery_plus/battery_plus.dart';
import 'data/battery_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loc = LocalizationService();
  await loc.init();
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
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LocalizationService _loc = LocalizationService();
  final GeminiService _gemini = GeminiService();

  // State Variables
  int _hp = 100;
  int _xp = 0;
  int _currentRankIndex = 0;
  String _currentSpecies = "cat"; // cat, dog, rabbit
  String _currentTab = "tab-stats"; // tab-stats, tab-tips, tab-data, tab-sandbox

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

  // Floating text messages
  final List<FloatingTextModel> _floatingTexts = [];

  // Simulation Metrics Data
  final Map<String, WeeklyMetrics> _weeklyStats = {};
  final Map<String, DailyMetrics> _dailyData = {};
  final GlobalMetrics _globalMetrics = GlobalMetrics();
  int _simulatedWeeksCount = 0;

  // Active Sessions Timeline Cards
  final List<Map<String, dynamic>> _timelineCards = [];

  // Real-Time Tracking State
  bool _isCharging = false;
  StreamSubscription<BatteryState>? _batterySubscription;
  final Battery _battery = Battery();

  // Expanded cards index state tracker
  final Set<int> _expandedCardIndices = {};

  // Screen shake variables
  late AnimationController _screenShakeController;
  late Animation<double> _screenShakeAnimation;

  final ScrollController _timelineScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

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

    _screenShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _screenShakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _screenShakeController, curve: Curves.linear),
    );

    // Load real-time battery stats
    _loadRealStats();
    // Initialize active charging detection
    _initBatteryListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batterySubscription?.cancel();
    _speechTimer?.cancel();
    _timelineScrollController.dispose();
    _mainScrollController.dispose();
    _screenShakeController.dispose();
    super.dispose();
  }

  // --- ACTIONS ---

  void _triggerBadgeClick() {
    setState(() {
      _badgeClickCount++;
      if (_badgeClickCount >= 5) {
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
        explanation = "Explain that you are hurt because the user overcharges you at night too many days.";
      } else {
        explanation = "Explain that you are starving because the user lets the battery drop too low.";
      }
    }

    final prompt =
        "You are a $state $_currentSpecies at Rank $rankName. Your name is Sparky. $explanation Give a short, 1-sentence quote. If you are thriving, be boastful. If sick or tired, complain about the user's bad habits. Limit your response to 12 words maximum.";
    final sysPrompt = _loc.translate("sys_prompt_talk",
        defaultVal: "You are a companion pet. You speak like a primitive caveman...");

    _showSpeechBubble(_loc.translate("thinking", defaultVal: "Thinking..."));

    final response = await _gemini.fetchGeminiWithRetry(prompt: prompt, systemPrompt: sysPrompt);

    // Clean up quotes
    final cleanResponse = response.replaceAll('"', '').trim();
    _showSpeechBubble('"$cleanResponse"');
  }

  Future<void> _askPetAdvice() async {
    if (_globalMetrics.total == 0) {
      _showSpeechBubble("Run simulation first!");
      return;
    }

    final rankName = _getRankName(_currentRankIndex);
    final prompt =
        "You are my $_currentSpecies pet currently at Rank $rankName. Here is my overall battery charging data: ${_globalMetrics.total} total charges, ${_globalMetrics.overcharges} overcharges (which burns you), ${_globalMetrics.perfectCharges} perfect charges (which makes you strong, 20-80%), and ${_globalMetrics.criticalStarts} times I starved you by letting the battery drop below 15%. Write a 2-paragraph performance review. Praise me for good things, scold me for bad things, and tell me what to do.";
    final sysPrompt = _loc.translate("sys_prompt_advice",
        defaultVal: "You are a companion pet. Give actionable tips about charging...");

    // Show loading Dialog in advice tab
    setState(() {
      _adviceContent = const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            children: [
              CircularProgressIndicator(color: NeoColors.primary),
              SizedBox(height: 12),
              Text(
                "Pet is thinking hard...",
                style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold),
              )
            ],
          ),
        ),
      );
    });

    final response = await _gemini.fetchGeminiWithRetry(prompt: prompt, systemPrompt: sysPrompt);

    setState(() {
      _adviceContent = NeoCard(
        borderWidth: 3.0,
        shadowOffset: const Offset(3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: NeoColors.primary),
                const SizedBox(width: 8),
                Text(
                  _loc.translate('pets_advice', defaultVal: 'Pet Speaks').toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    color: NeoColors.rpgText,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.black26),
            const SizedBox(height: 6),
            Text(
              response,
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 13.0,
                height: 1.4,
                color: NeoColors.rpgText,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget? _adviceContent;

  // --- SIMULATION LOGIC ---

  // --- REAL-TIME CHARGING LOGIC & DB HELPERS ---

  Future<void> _loadRealStats() async {
    final sessions = await BatteryDb().getAllChargeSessions();
    _applySessionsToState(sessions);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryAndPendingSession();
    } else if (state == AppLifecycleState.paused) {
      _saveCheckpoint();
    }
  }

  Future<void> _saveCheckpoint() async {
    try {
      final state = await _battery.batteryState;
      final currentLevel = await _battery.batteryLevel;
      await BatteryDb().insertRecord(BatteryRecord(
        timestamp: DateTime.now().toIso8601String(),
        level: currentLevel,
        state: state.toString().split('.').last,
      ));
    } catch (_) {}
  }

  void _initBatteryListener() async {
    await _checkBatteryAndPendingSession();

    _batterySubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      _handleBatteryStateChange(state);
    });
  }

  Future<void> _checkBatteryAndPendingSession() async {
    try {
      final state = await _battery.batteryState;
      final currentLevel = await _battery.batteryLevel;
      final isNowCharging = state == BatteryState.charging || state == BatteryState.full;
      
      final pending = await BatteryDb().getPendingSession();
      final latestRecord = await BatteryDb().getLatestRecord();
      
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      if (isNowCharging != _isCharging) {
        setState(() {
          _isCharging = isNowCharging;
          if (_isCharging) {
            _petGlowTrigger++;
          }
        });
      }

      int? offlineStartPct;
      String? offlineStartDate;
      String? offlineStartTime;

      if (pending != null) {
        offlineStartPct = pending['start_pct'] as int;
        offlineStartDate = pending['start_date'] as String;
        offlineStartTime = pending['start_time'] as String;
      } else if (latestRecord != null && latestRecord.level < currentLevel - 1) {
        offlineStartPct = latestRecord.level;
        try {
          final dt = DateTime.parse(latestRecord.timestamp);
          offlineStartDate = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
          offlineStartTime = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
        } catch (_) {
          offlineStartDate = dateStr;
          offlineStartTime = timeStr;
        }
      }

      if (offlineStartPct != null && currentLevel > offlineStartPct) {
        await BatteryDb().clearPendingSession();

        final completedSession = ChargeSession(
          startPct: offlineStartPct,
          startDate: offlineStartDate ?? dateStr,
          startTime: offlineStartTime ?? timeStr,
          endPct: currentLevel,
          endDate: dateStr,
          endTime: timeStr,
        );

        await BatteryDb().insertChargeSession(completedSession);
        _spawnFloatingText("Charged to $currentLevel%!", const Color(0xFF2A9D8F));
        _showSpeechBubble("Charged! +${currentLevel - offlineStartPct}% battery.");

        await _loadRealStats();
      }

      if (isNowCharging) {
        final refreshedPending = await BatteryDb().getPendingSession();
        if (refreshedPending == null) {
          await BatteryDb().savePendingSession(currentLevel, dateStr, timeStr);
        }
      } else {
        await BatteryDb().clearPendingSession();
      }

      await BatteryDb().insertRecord(BatteryRecord(
        timestamp: now.toIso8601String(),
        level: currentLevel,
        state: state.toString().split('.').last,
      ));

    } catch (e) {
      print("Error in _checkBatteryAndPendingSession: $e");
    }
  }

  Future<void> _handleBatteryStateChange(BatteryState state) async {
    final isNowCharging = state == BatteryState.charging || state == BatteryState.full;
    if (isNowCharging == _isCharging) return;

    setState(() {
      _isCharging = isNowCharging;
      if (_isCharging) {
        _petGlowTrigger++;
      }
    });

    try {
      final currentLevel = await _battery.batteryLevel;
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      if (_isCharging) {
        await BatteryDb().savePendingSession(currentLevel, dateStr, timeStr);
        _spawnFloatingText("Charging Started! ⚡", const Color(0xFF2A9D8F));
        _showSpeechBubble("Charging... Feeling the power! ⚡");
      } else {
        final pending = await BatteryDb().getPendingSession();
        if (pending != null) {
          final startPct = pending['start_pct'] as int;
          final startDate = pending['start_date'] as String;
          final startTime = pending['start_time'] as String;

          await BatteryDb().clearPendingSession();

          final completedSession = ChargeSession(
            startPct: startPct,
            startDate: startDate,
            startTime: startTime,
            endPct: currentLevel,
            endDate: dateStr,
            endTime: timeStr,
          );

          await BatteryDb().insertChargeSession(completedSession);
          _spawnFloatingText("Charged to $currentLevel%!", const Color(0xFF2A9D8F));
          _showSpeechBubble("Charged! +${currentLevel - startPct}% battery.");

          await _loadRealStats();
        }
      }
    } catch (e) {
      print("Error in _handleBatteryStateChange: $e");
    }
  }

  // --- SIMULATION LOGIC REMOVED ---

  void _applySessionsToState(List<ChargeSession> sessions) {
    int localHp = 100;
    int localXp = 0;
    int localRankIndex = 0;

    final Map<String, WeeklyMetrics> localWeeklyStats = {};
    final Map<String, DailyMetrics> localDailyData = {};
    final GlobalMetrics localGlobalMetrics = GlobalMetrics();
    final List<Map<String, dynamic>> localTimelineCards = [];

    if (sessions.isNotEmpty) {
      final firstDateObj = DateTime.parse('${sessions.first.startDate} ${sessions.first.startTime}');
      final lastDateObj = DateTime.parse('${sessions.last.endDate} ${sessions.last.endTime}');
      final diffDays = lastDateObj.difference(firstDateObj).inDays;
      final diffWeeks = (diffDays / 7.0).ceil();
      final localWeeksCount = diffWeeks == 0 ? 1 : diffWeeks;

      localGlobalMetrics.total = sessions.length;

      for (int idx = 0; idx < sessions.length; idx++) {
        final s = sessions[idx];

        final startDt = DateTime.parse('${s.startDate} ${s.startTime}');
        final endDt = DateTime.parse('${s.endDate} ${s.endTime}');
        final duration = endDt.difference(startDt);
        final h = duration.inHours;
        final m = duration.inMinutes % 60;
        final durationStr = h > 0 ? '${h}h ${m}m' : '${m}m';

        int hpDelta = 0;
        int xpDelta = 0;
        String msg = _loc.translate("msg_standard_charge", defaultVal: "Standard Charge");
        String flavorText = "Standard charging session. Sparky charged peacefully. Keep it between 20% and 80% to earn extra bonuses next time!";
        Color cardBg = Colors.white;
        Color cardBorder = NeoColors.rpgText;
        Color cardText = NeoColors.rpgText;
        IconData icon = Icons.bolt;

        if (s.isOvercharge) {
          hpDelta = -15;
          xpDelta = 5;
          msg = _loc.translate("msg_overcharge_penalty", defaultVal: "Overcharge Penalty");
          flavorText = "Ouch! Left plugged in past 95%. This causes sustained high voltage stress, degrading battery health (-15 HP).";
          cardBg = const Color(0xFFFEE2E2);
          cardBorder = NeoColors.rpgBad;
          cardText = NeoColors.rpgBad;
          icon = Icons.battery_alert;
          localGlobalMetrics.overcharges++;
        } else if (s.isCriticalStart) {
          hpDelta = -10;
          xpDelta = 10;
          msg = _loc.translate("msg_critical_starvation", defaultVal: "Critical Starvation");
          flavorText = "Starvation warning! Charging started below 10%. Deep discharges put heavy stress on battery cells (-10 HP).";
          cardBg = const Color(0xFFFFEDD5);
          cardBorder = NeoColors.primary;
          cardText = const Color(0xFFC2410C);
          icon = Icons.warning_amber;
          localGlobalMetrics.criticalStarts++;
        } else if (s.isPerfectCharge) {
          hpDelta = 5;
          xpDelta = 30;
          msg = _loc.translate("msg_perfect_charge", defaultVal: "Perfect Charge!");
          flavorText = "Bussin! Started above 20% and stopped before 85%. Excellent battery stewardship (+5 HP, +30 XP).";
          cardBg = const Color(0xFFD1FAE5);
          cardBorder = NeoColors.rpgSurface;
          cardText = const Color(0xFF065F46);
          icon = Icons.stars;
          localGlobalMetrics.perfectCharges++;
        } else {
          hpDelta = 2;
          xpDelta = 15;
        }

        final sDate = DateTime.parse('${s.startDate} 00:00:00');
        final daysDiff = sDate.difference(firstDateObj).inDays;
        final weekNum = (daysDiff / 7).floor() + 1;
        final weekKey = "Week $weekNum";

        localWeeklyStats.putIfAbsent(weekKey, () => WeeklyMetrics(weekNum: weekNum, key: weekKey));
        final weekMetrics = localWeeklyStats[weekKey]!;
        weekMetrics.xp += xpDelta;
        weekMetrics.hpDelta += hpDelta;
        weekMetrics.total++;
        if (s.isOvercharge) weekMetrics.over++;
        if (s.isCriticalStart) weekMetrics.crit++;
        if (s.isPerfectCharge) weekMetrics.perf++;

        final dayKey = s.startDate;
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
        dailyMetrics.rankName = _loc.translate("rank_$id", defaultVal: fallback);

        final cardInfo = {
          'date': s.startDate,
          'time': s.startTime,
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
      final bool perfectChargeHappened = localGlobalMetrics.perfectCharges > _globalMetrics.perfectCharges;
      final bool xpReached100 = (localXp >= 100 && _xp < 100);
      final bool hasPenalty = localGlobalMetrics.overcharges > _globalMetrics.overcharges ||
                              localGlobalMetrics.criticalStarts > _globalMetrics.criticalStarts;

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

        _timelineCards.clear();
        _timelineCards.addAll(localTimelineCards);

        _simulatedWeeksCount = localWeeksCount;
        _expandedCardIndices.clear();
      });

      final finalRankName = _getRankName(_currentRankIndex);
      _spawnFloatingText(
        _loc.translate("final_rank", defaultVal: "Final Rank: {rank_name}").replaceAll("{rank_name}", finalRankName),
        NeoColors.rpgGold,
      );

      if (leveledUp || hasPenalty) {
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
        _timelineCards.clear();
        _simulatedWeeksCount = 0;
        _expandedCardIndices.clear();
      });
    }
  }





  void _triggerScreenShake() {
    _screenShakeController.forward(from: 0.0);
  }

  // --- MANUAL DEV INTERACTIONS ---

  void _manualGoodCharge() {
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
      if (_currentRankIndex > oldRank || (_xp >= 100 && oldXp < 100) || _xp == 0) {
        _petGlowTrigger++;
      }
    });
    if (_currentRankIndex > oldRank) {
      _triggerScreenShake();
    }
    _spawnFloatingText("+15 HP / +30 XP", NeoColors.rpgAccent);
  }

  void _manualOvercharge() {
    setState(() {
      _hp = math.max(0, _hp - 20);
      _simFinalHp = _hp;
    });
    _triggerScreenShake();
    _spawnFloatingText("-20 HP", NeoColors.rpgBad);
  }

  void _forceState(String state) {
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

    final petName = _loc.translate('title', defaultVal: 'VoltBuddy').split(' ')[0];

    // Constrain application width on tablet/desktop to max 480px, replicating max-w-md
    return Scaffold(
      backgroundColor: const Color(0xFFE8E5D1),
      body: AnimatedBuilder(
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
                _buildHeader(),


                // Scrollable body containing Pet Stage and Tabs content
                Expanded(
                  child: SingleChildScrollView(
                    controller: _mainScrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 38),
                        // Pet Arena Stage
                        PetRenderer(
                          species: _currentSpecies,
                          rankIndex: _currentRankIndex,
                          batch: batch,
                          healthState: state,
                          speechText: _speechText,
                          speechVisible: _speechVisible,
                          floatingTexts: _floatingTexts,
                          glowTrigger: _petGlowTrigger,
                          isCharging: _isCharging,
                        ),
                        const SizedBox(height: 12),

                        // Asset details labels
                        _buildPetDetails(statusText, statusColor, petName),

                        // Progress health and exp bars
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          child: _buildProgressBars(),
                        ),
                        const SizedBox(height: 8),

                        // Neo-brutalist navigation tabs bar
                        _buildTabBar(),

                        // Active Tab container block
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(16.0),
                          child: _buildActiveTabContent(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final rankName = _getRankName(_currentRankIndex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
      child: Row(
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
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
              child: Row(
                children: [
                  const Icon(Icons.star, color: NeoColors.primary, size: 16.0),
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
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _currentLanguage,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, color: NeoColors.rpgText, size: 16.0),
                    style: const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                      color: NeoColors.rpgText,
                    ),
                    onChanged: _changeLanguage,
                    items: const [
                      DropdownMenuItem(value: "regular", child: Text("REGULAR")),
                      DropdownMenuItem(value: "genz", child: Text("GEN Z")),
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
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: NeoColors.rpgSurface, size: 15.0),
                    const SizedBox(width: 4),
                    Text(
                      _loc.translate('week_label',
                              defaultVal: 'Week {num}')
                          .replaceAll('{num}', '$_simulatedWeeksCount')
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
      ),
    );
  }

  Widget _buildPetDetails(String statusText, Color statusColor, String petName) {
    final rankName = _getRankName(_currentRankIndex);
    final speciesName = _currentSpecies.substring(0, 1).toUpperCase() + _currentSpecies.substring(1);
    final batch = _ranks[_currentRankIndex]["batch"] as int;

    // "Drip: GOAT Cat (Drop 1)" or similar
    final dripText = _loc.translate('asset_label', defaultVal: 'Asset: {rank_name} {species} (Batch {batch})')
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

        // Quick Species Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSpeciesButton("cat", _loc.translate('cat_btn', defaultVal: '🐱 Cat')),
            const SizedBox(width: 6),
            _buildSpeciesButton("dog", _loc.translate('dog_btn', defaultVal: '🐶 Dog')),
            const SizedBox(width: 6),
            _buildSpeciesButton("rabbit", _loc.translate('rabbit_btn', defaultVal: '🐰 Rabbit')),
          ],
        ),
        const SizedBox(height: 10),

        // Action Status details row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status Tag Badge
            Container(
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: NeoColors.rpgText, width: 3.0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 3.0),
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

            const SizedBox(width: 8),
            // Talk Button
            NeoButton(
              backgroundColor: Colors.white,
              borderWidth: 2.0,
              borderRadius: 20.0,
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  "⚡ SPARKY IS CHARGING...",
                  style: TextStyle(
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
      ],
    );
  }

  Widget _buildSpeciesButton(String species, String label) {
    return GestureDetector(
      onTap: () {
        if (_currentSpecies != species) {
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
          label: _loc.translate('battery_health', defaultVal: 'Battery Health (HP)').toUpperCase(),
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
          label: _loc.translate('exp_rank_up', defaultVal: 'Exp to Rank Up').toUpperCase(),
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
          _buildTabButton("tab-stats", _loc.translate('tab_stats', defaultVal: 'Stats')),
          _buildTabButton("tab-tips", _loc.translate('tab_tips', defaultVal: 'Tips')),
          _buildTabButton("tab-data", _loc.translate('tab_logs', defaultVal: 'Logs')),
          if (_sandboxUnlocked)
            _buildTabButton("tab-sandbox", _loc.translate('tab_sandbox', defaultVal: 'Dev'), isSandbox: true),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabId, String label, {bool isSandbox = false}) {
    final active = _currentTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentTab = tabId;
          });
        },
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
        // Calendar Heatmap section
        HeatmapWidget(
          dailyData: _dailyData,
          globalMetrics: _globalMetrics,
          onDaySelected: (dayMetrics, petQuote) {
            setState(() {
              if (dayMetrics.hpAtEndOfDay != null) _hp = dayMetrics.hpAtEndOfDay!;
              if (dayMetrics.xpAtEndOfDay != null) _xp = dayMetrics.xpAtEndOfDay!;
              if (dayMetrics.rankAtEndOfDay != null) _currentRankIndex = dayMetrics.rankAtEndOfDay!;
            });
            _showSpeechBubble(petQuote);

            if (dayMetrics.averageScore >= 80) {
              setState(() {
                _petGlowTrigger++;
              });
            }
          },
          onDayDismissed: () {
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
          xpPerWeek: _simulatedWeeksCount > 0 ? _globalMetrics.totalXpEarned / _simulatedWeeksCount : 0.0,
          totalWeeks: _simulatedWeeksCount,
        ),
      ],
    );
  }

  Widget _buildTipsTab() {
    final adviceBtn = _loc.translate('ask_advice_btn', defaultVal: 'Ask Pet for Advice ✨');
    final wisdomTitle1 = _loc.translate('rule_20_80_title', defaultVal: 'The Golden Rule: 20-80');
    final wisdomDesc1 = _loc.translate('rule_20_80_desc', defaultVal: 'Keep battery energy between 20-80%...');
    final wisdomTitle2 = _loc.translate('night_charge_title', defaultVal: 'Beware the Night Charge');
    final wisdomDesc2 = _loc.translate('night_charge_desc', defaultVal: 'Leaving plugged in overnight damages HP...');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Advice header
        Row(
          children: [
            const Icon(Icons.psychology, color: NeoColors.primary),
            const SizedBox(width: 8),
            Text(
              _loc.translate('pets_advice', defaultVal: "Pet's Advice").toUpperCase(),
              style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 13.0, color: NeoColors.rpgText),
            ),
          ],
        ),
        const SizedBox(height: 12),

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
                style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w900, color: Colors.white, fontSize: 12.0),
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
                border: Border.all(color: NeoColors.rpgText.withOpacity(0.2), width: 2.0),
              ),
              child: Center(
                child: Text(
                  _loc.translate('run_sim_tips_msg', defaultVal: 'Run simulation first to get personalized advice!'),
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
          _loc.translate('general_wisdom', defaultVal: 'General Wisdom').toUpperCase(),
          style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 11.5, color: NeoColors.rpgText.withOpacity(0.6)),
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
              const Icon(Icons.battery_charging_full, color: NeoColors.rpgSurface, size: 28.0),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wisdomTitle1.toUpperCase(),
                      style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w900, fontSize: 12.5, color: NeoColors.rpgText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wisdomDesc1,
                      style: TextStyle(fontFamily: 'Space Grotesk', fontSize: 11.5, height: 1.3, color: NeoColors.rpgText.withOpacity(0.8)),
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
                      style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w900, fontSize: 12.5, color: NeoColors.rpgText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wisdomDesc2,
                      style: TextStyle(fontFamily: 'Space Grotesk', fontSize: 11.5, height: 1.3, color: NeoColors.rpgText.withOpacity(0.8)),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: NeoColors.rpgText),
                SizedBox(width: 8),
                Text(
                  "REAL CHARGE HISTORY",
                  style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 13.0, color: NeoColors.rpgText),
                ),
              ],
            ),
            if (_timelineCards.isNotEmpty)
              NeoButton(
                backgroundColor: NeoColors.rpgMuted,
                borderColor: NeoColors.rpgText,
                shadowColor: NeoColors.rpgText,
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                onPressed: () async {
                  await BatteryDb().clearChargeSessions();
                  await _loadRealStats();
                  _spawnFloatingText("Logs Cleared!", NeoColors.rpgMuted);
                },
                child: const Text(
                  "CLEAR ALL",
                  style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w900, color: Colors.white, fontSize: 10.0),
                ),
              ),
          ],
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
            style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 11.5, color: NeoColors.rpgText),
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
              final String timeLabel = "${card['date']} ${card['time'].toString().substring(0, 5)}";
              final String rangeLabel = "${card['startPct']}% → ${card['endPct']}%";
              final int hpDelta = card['hpDelta'] as int;
              final int xpDelta = card['xpDelta'] as int;
              final bool isExpanded = _expandedCardIndices.contains(idx);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: GestureDetector(
                  onTap: () {
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
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                                    border: Border.all(color: card['cardText'] as Color, width: 1.5),
                                  ),
                                  child: Icon(card['icon'] as IconData, color: card['cardText'] as Color, size: 18.0),
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
                                        color: (card['cardText'] as Color).withValues(alpha: 0.7),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(6.0),
                                    border: Border.all(color: card['cardText'] as Color, width: 1.0),
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
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "SESSION DETAILS",
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.w900,
                                        color: (card['cardText'] as Color).withValues(alpha: 0.8),
                                      ),
                                    ),
                                    Text(
                                      "Duration: ${card['duration']}",
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.bold,
                                        color: NeoColors.rpgText.withValues(alpha: 0.6),
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
                          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
    final flexProgTitle = _loc.translate('tier_progression', defaultVal: '7-Tier Rank Progression');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Level tier Progression setter
        Text(
          flexProgTitle.toUpperCase(),
          style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 10.0, color: NeoColors.rpgText.withOpacity(0.6)),
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
            style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, color: NeoColors.rpgText, fontSize: 13.0),
            onChanged: (val) {
              if (val != null) {
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
                    const Icon(Icons.battery_charging_full, color: Colors.white),
                    const SizedBox(height: 4),
                    Text(
                      _loc.translate('good_charge', defaultVal: 'Good Charge (+XP)').toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 9.0, color: Colors.white),
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
                      _loc.translate('overcharge', defaultVal: 'Overcharge (-HP)').toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 9.0, color: Colors.white),
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
      ],
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
                final widthFactor = math.max(0.0, math.min(1.0, animVal / maxValue));
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
