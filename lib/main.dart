import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';

import 'models/simulation_models.dart';

import 'services/localization_service.dart';
import 'services/gemini_service.dart';
import 'widgets/neo_brutalist.dart';
import 'widgets/pet_renderer.dart';
import 'widgets/heatmap_widget.dart';
import 'widgets/journey_map_widget.dart';

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

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
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

  // Active/Simulating Sessions Timeline Cards
  final List<ChargeSession> _simulationSessions = [];
  final List<Map<String, dynamic>> _timelineCards = [];
  bool _isSimulating = false;

  // Expanded cards index state tracker
  final Set<int> _expandedCardIndices = {};

  // Screen shake variables
  late AnimationController _screenShakeController;
  late Animation<double> _screenShakeAnimation;

  // Text fields controllers for logs
  final TextEditingController _csvInputController = TextEditingController(text: _presetLog1);
  final TextEditingController _csvInputController2 = TextEditingController(text: _presetLog2);
  final TextEditingController _csvInputController3 = TextEditingController(text: _presetLog3);

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
    _currentLanguage = _loc.currentLocale;

    _screenShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _screenShakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _screenShakeController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _speechTimer?.cancel();
    _csvInputController.dispose();
    _csvInputController2.dispose();
    _csvInputController3.dispose();
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

  void _runSimulation(String text) {
    if (_isSimulating) return;

    final lines = text.trim().split("\n");
    if (lines.length < 2) return;

    // Temporary variables to hold calculation state
    int localHp = 100;
    int localXp = 0;
    int localRankIndex = 0;

    final Map<String, WeeklyMetrics> localWeeklyStats = {};
    final Map<String, DailyMetrics> localDailyData = {};
    final GlobalMetrics localGlobalMetrics = GlobalMetrics();
    final List<Map<String, dynamic>> localTimelineCards = [];

    List<ChargeSession> sessions = [];
    LogEntry? pendingConnect;

    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      try {
        final entry = LogEntry.fromCsvLine(lines[i]);
        if (entry.eventType == ChargeEventType.powerConnected) {
          pendingConnect = entry;
        } else if (entry.eventType == ChargeEventType.powerDisconnected && pendingConnect != null) {
          sessions.add(ChargeSession(
            startPct: pendingConnect.percentage,
            startDate: pendingConnect.date,
            startTime: pendingConnect.time,
            endPct: entry.percentage,
            endDate: entry.date,
            endTime: entry.time,
          ));
          pendingConnect = null;
        }
      } catch (e) {
        print('Parsing error at line $i: $e');
      }
    }

    if (sessions.isEmpty) return;

    // Determine simulation week count
    final firstDateObj = DateTime.parse('${sessions.first.startDate} ${sessions.first.startTime}');
    final lastDateObj = DateTime.parse('${sessions.last.endDate} ${sessions.last.endTime}');
    final diffDays = lastDateObj.difference(firstDateObj).inDays;
    final diffWeeks = (diffDays / 7.0).ceil();
    final localSimulatedWeeksCount = diffWeeks == 0 ? 1 : diffWeeks;

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

      // Add to Weekly Stats aggregation
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

      // Daily Data aggregation for Heatmap
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

      // Update state
      localHp = math.min(100, math.max(0, localHp + hpDelta));
      localXp += xpDelta;
      while (localXp >= 100 && localRankIndex < 6) {
        localRankIndex++;
        localXp -= 100;
      }
      if (localRankIndex >= 6) {
        localXp = 100;
      }

      // Save snapshots at end of day
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

      // Add to front of timeline list to match prepend
      localTimelineCards.insert(0, cardInfo);
    }

    final bool leveledUp = localRankIndex > _currentRankIndex;
    final bool hasPenalty = localGlobalMetrics.overcharges > _globalMetrics.overcharges ||
                            localGlobalMetrics.criticalStarts > _globalMetrics.criticalStarts;

    setState(() {
      _hp = localHp;
      _xp = localXp;
      _currentRankIndex = localRankIndex;
      _simFinalHp = localHp;
      _simFinalXp = localXp;
      _simFinalRankIndex = localRankIndex;
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

      _simulatedWeeksCount = localSimulatedWeeksCount;
      _isSimulating = false;
      _currentTab = "tab-stats"; // directly swap to Receipts/Stats tab
      _expandedCardIndices.clear(); // reset expanded state on reload
    });

    final finalRankName = _getRankName(_currentRankIndex);
    _spawnFloatingText(
      _loc.translate("final_rank", defaultVal: "Final Rank: {rank_name}").replaceAll("{rank_name}", finalRankName),
      NeoColors.rpgGold,
    );

    if (leveledUp || hasPenalty) {
      _triggerScreenShake();
    }
  }



  // Better implementation of CSV picking:
  Future<void> _pickCSV() async {
    try {
      FileResultPicker.pickCSVFile((content) {
        if (content != null) {
          setState(() {
            _csvInputController.text = content;
            _csvInputController2.text = content;
            _csvInputController3.text = content;
            _timelineCards.clear();
          });
          _spawnFloatingText(
            _loc.translate('alert_csv_loaded', defaultVal: 'CSV Loaded!'),
            NeoColors.rpgSurface,
          );
        }
      });
    } catch (e) {
      print('File picker error: $e');
    }
  }

  void _triggerScreenShake() {
    _screenShakeController.forward(from: 0.0);
  }

  // --- MANUAL DEV INTERACTIONS ---

  void _manualGoodCharge() {
    final oldRank = _currentRankIndex;
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
                        const SizedBox(height: 16),
                        // Pet Arena Stage
                        PetRenderer(
                          species: _currentSpecies,
                          rankIndex: _currentRankIndex,
                          batch: batch,
                          healthState: state,
                          speechText: _speechText,
                          speechVisible: _speechVisible,
                          floatingTexts: _floatingTexts,
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
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: NeoColors.rpgText, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: NeoColors.rpgText,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: DropdownButton<String>(
                  value: _currentLanguage,
                  underline: const SizedBox.shrink(),
                  icon: const Icon(Icons.arrow_drop_down, color: NeoColors.rpgText),
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
              const SizedBox(width: 8),

              // Time week indicator badge
              NeoCard(
                backgroundColor: Colors.white,
                borderWidth: 2.5,
                borderRadius: 12.0,
                shadowOffset: const Offset(2, 2),
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
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
              shadowOffset: const Offset(2, 2),
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
      ],
    );
  }

  Widget _buildSpeciesButton(String species, String label) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentSpecies = species;
          _spawnFloatingText(species.toUpperCase(), NeoColors.primary);
        });
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
    final csvImportText = _loc.translate('csv_import', defaultVal: 'CSV Import');
    final loadCsvText = _loc.translate('load_csv', defaultVal: 'Load CSV');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Import CSV header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.dataset, color: NeoColors.rpgText),
                const SizedBox(width: 8),
                Text(
                  csvImportText.toUpperCase(),
                  style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 13.0, color: NeoColors.rpgText),
                ),
              ],
            ),
            // Load CSV Button picker
            NeoButton(
              backgroundColor: NeoColors.rpgSurface,
              borderColor: NeoColors.rpgText,
              shadowColor: NeoColors.rpgText,
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              onPressed: _pickCSV,
              child: Row(
                children: [
                  const Icon(Icons.upload_file, color: Colors.white, size: 14.0),
                  const SizedBox(width: 4),
                  Text(
                    loadCsvText.toUpperCase(),
                    style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w900, color: Colors.white, fontSize: 10.0),
                  ),
                ],
              ),

            ),
          ],
        ),
        const SizedBox(height: 16),

        // Log Inputs and presets simulation lists
        _buildSimLogPreset(
          index: 1,
          label: _loc.translate('log_1_label', defaultVal: 'Log 1 — Normal Charging'),
          btnText: _loc.translate('run_sim_log_1', defaultVal: 'Run Simulation — Log 1'),
          controller: _csvInputController,
          themeColor: NeoColors.rpgText,
        ),
        _buildDividerOr(),
        _buildSimLogPreset(
          index: 2,
          label: _loc.translate('log_2_label', defaultVal: 'Log 2 — Bad Charging'),
          btnText: _loc.translate('run_sim_log_2', defaultVal: 'Run Simulation — Log 2'),
          controller: _csvInputController2,
          themeColor: NeoColors.rpgMuted,
        ),
        _buildDividerOr(),
        _buildSimLogPreset(
          index: 3,
          label: _loc.translate('log_3_label', defaultVal: 'Log 3 — Good Charging'),
          btnText: _loc.translate('run_sim_log_3', defaultVal: 'Run Simulation — Log 3'),
          controller: _csvInputController3,
          themeColor: NeoColors.rpgAccent,
        ),

        // Running logs Cards timeline list
        if (_timelineCards.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            "SIMULATION LOGS",
            style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 11.5, color: NeoColors.rpgText),
          ),
          const Divider(color: Colors.black26),
          const SizedBox(height: 6),
          ListView.builder(
            controller: _timelineScrollController,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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

  Widget _buildSimLogPreset({
    required int index,
    required String label,
    required String btnText,
    required TextEditingController controller,
    required Color themeColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  "$index",
                  style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.bold, fontSize: 11.5, color: NeoColors.rpgText),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: NeoColors.rpgBg,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: NeoColors.rpgText, width: 2.0),
          ),
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: controller,
            maxLines: null,
            readOnly: true,
            style: const TextStyle(fontFamily: 'Courier', fontSize: 9.0, color: NeoColors.rpgText),
            decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
          ),
        ),
        const SizedBox(height: 6),
        NeoButton(
          backgroundColor: themeColor,
          borderColor: NeoColors.rpgText,
          shadowColor: NeoColors.rpgText,
          onPressed: () => _runSimulation(controller.text),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.play_arrow, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                btnText.toUpperCase(),
                style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w900, color: Colors.white, fontSize: 10.5),
              ),
            ],
          ),

        ),
      ],
    );
  }

  Widget _buildDividerOr() {
    final orVibeText = _loc.translate('or_try', defaultVal: 'or try');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Expanded(child: Container(height: 1.5, color: NeoColors.rpgText.withOpacity(0.2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Text(
              orVibeText.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: NeoColors.rpgText.withOpacity(0.4),
              ),
            ),
          ),
          Expanded(child: Container(height: 1.5, color: NeoColors.rpgText.withOpacity(0.2))),
        ],
      ),
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

  // --- MOCK PRESET LOG STRINGS ---

  static const String _presetLog1 = """user_id,event_type,percentage,date,time,timezone
1,power_connected,2,2025-10-23,19:00:35,+05:30
1,power_disconnected,8,2025-10-23,19:07:38,+05:30
1,power_connected,7,2025-10-23,19:17:43,+05:30
1,power_disconnected,41,2025-10-23,20:02:50,+05:30
1,power_connected,35,2025-10-23,22:11:47,+05:30
1,power_disconnected,100,2025-10-24,00:29:42,+05:30
1,power_connected,51,2025-10-27,09:51:39,+05:30
1,power_disconnected,91,2025-10-27,10:30:36,+05:30
1,power_connected,46,2025-10-27,19:14:25,+05:30
1,power_disconnected,77,2025-10-27,19:33:14,+05:30
1,power_connected,47,2025-10-28,00:51:17,+05:30
1,power_disconnected,100,2025-10-28,07:00:32,+05:30
1,power_connected,40,2025-10-28,17:32:38,+05:30
1,power_disconnected,64,2025-10-28,17:47:24,+05:30
1,power_connected,33,2025-10-28,22:20:39,+05:30
1,power_disconnected,65,2025-10-28,22:33:43,+05:30
1,power_connected,62,2025-10-28,22:56:42,+05:30
1,power_disconnected,65,2025-10-28,23:03:38,+05:30
1,power_connected,49,2025-10-29,00:36:31,+05:30
1,power_disconnected,100,2025-10-29,06:34:09,+05:30
1,power_connected,42,2025-10-29,14:06:48,+05:30
1,power_disconnected,44,2025-10-29,14:09:15,+05:30
1,power_connected,42,2025-10-29,14:15:17,+05:30
1,power_disconnected,42,2025-10-29,14:16:34,+05:30
1,power_connected,28,2025-10-29,18:48:23,+05:30
1,power_disconnected,80,2025-10-29,19:13:24,+05:30
1,power_connected,8,2025-10-31,18:56:10,+05:30
1,power_disconnected,100,2025-10-31,21:48:15,+05:30
1,power_connected,38,2025-11-02,19:53:27,+05:30
1,power_disconnected,100,2025-11-02,20:42:30,+05:30
1,power_connected,70,2025-11-04,15:35:00,+05:30
1,power_disconnected,70,2025-11-04,15:35:11,+05:30
1,power_connected,3,2025-11-08,10:47:20,+05:30
1,power_disconnected,22,2025-11-08,10:54:13,+05:30
1,power_connected,1,2025-11-09,20:49:34,+05:30
1,power_disconnected,39,2025-11-09,21:04:45,+05:30
1,power_connected,37,2025-11-09,22:49:14,+05:30
1,power_disconnected,80,2025-11-10,00:44:13,+05:30
1,power_connected,17,2025-11-12,16:01:17,+05:30
1,power_disconnected,80,2025-11-13,00:09:06,+05:30""";

  static const String _presetLog2 = """user_id,event_type,percentage,date,time,timezone
108,power_connected,29,2025-10-21,18:28:22,+05:30
108,power_disconnected,47,2025-10-21,18:43:52,+05:30
108,power_connected,47,2025-10-21,19:02:15,+05:30
108,power_disconnected,60,2025-10-21,19:13:41,+05:30
108,power_connected,32,2025-10-22,16:10:17,+05:30
108,power_disconnected,90,2025-10-22,17:22:20,+05:30
108,power_connected,32,2025-10-23,10:07:50,+05:30
108,power_disconnected,100,2025-10-23,11:12:24,+05:30
108,power_connected,23,2025-10-23,20:19:53,+05:30
108,power_disconnected,100,2025-10-23,22:16:14,+05:30
108,power_connected,23,2025-10-25,09:59:17,+05:30
108,power_disconnected,100,2025-10-25,11:51:44,+05:30
108,power_connected,48,2025-10-25,21:48:43,+05:30
108,power_disconnected,100,2025-10-25,22:59:19,+05:30
108,power_connected,31,2025-10-27,16:19:43,+05:30
108,power_disconnected,100,2025-10-27,17:24:40,+05:30
108,power_connected,28,2025-10-31,11:21:13,+05:30
108,power_disconnected,100,2025-10-31,12:19:52,+05:30
108,power_connected,27,2025-11-02,19:40:54,+05:30
108,power_disconnected,100,2025-11-02,20:47:52,+05:30
108,power_connected,31,2025-11-04,19:30:19,+05:30
108,power_disconnected,96,2025-11-04,20:12:12,+05:30
108,power_connected,34,2025-11-06,14:03:33,+05:30
108,power_disconnected,97,2025-11-06,14:48:09,+05:30
108,power_connected,21,2025-11-07,19:44:39,+05:30
108,power_disconnected,100,2025-11-07,21:04:40,+05:30
108,power_connected,19,2025-11-09,10:53:42,+05:30
108,power_disconnected,100,2025-11-09,11:51:08,+05:30
108,power_connected,32,2025-11-11,11:32:59,+05:30
108,power_disconnected,100,2025-11-11,12:58:54,+05:30""";

  static const String _presetLog3 = """user_id,event_type,percentage,date,time,timezone
233,power_connected,18,2025-10-22,00:10:36,+05:30
233,power_disconnected,35,2025-10-22,00:28:10,+05:30
233,power_connected,16,2025-10-22,02:03:41,+05:30
233,power_disconnected,50,2025-10-22,02:24:24,+05:30
233,power_connected,33,2025-10-22,10:48:26,+05:30
233,power_disconnected,46,2025-10-22,10:55:35,+05:30
233,power_connected,27,2025-10-22,13:06:58,+05:30
233,power_disconnected,54,2025-10-22,13:26:13,+05:30
233,power_connected,48,2025-10-22,14:01:33,+05:30
233,power_disconnected,73,2025-10-22,14:22:17,+05:30
233,power_connected,22,2025-10-22,20:21:04,+05:30
233,power_disconnected,28,2025-10-22,20:25:07,+05:30
233,power_connected,22,2025-10-22,22:14:03,+05:30
233,power_disconnected,47,2025-10-22,22:27:06,+05:30
233,power_connected,35,2025-10-22,23:26:36,+05:30
233,power_disconnected,58,2025-10-22,23:46:45,+05:30
233,power_connected,55,2025-10-23,00:04:40,+05:30
233,power_disconnected,57,2025-10-23,00:07:18,+05:30
233,power_connected,23,2025-10-23,03:07:21,+05:30
233,power_disconnected,32,2025-10-23,03:12:25,+05:30
233,power_connected,23,2025-10-23,11:58:50,+05:30
233,power_disconnected,45,2025-10-23,12:16:00,+05:30
233,power_connected,40,2025-10-23,12:40:57,+05:30
233,power_disconnected,58,2025-10-23,12:52:36,+05:30
233,power_connected,42,2025-10-23,14:30:31,+05:30
233,power_disconnected,51,2025-10-23,14:39:35,+05:30
233,power_connected,34,2025-10-23,16:11:42,+05:30
233,power_disconnected,51,2025-10-23,16:25:47,+05:30
233,power_connected,17,2025-10-23,20:01:01,+05:30
233,power_disconnected,43,2025-10-23,20:19:15,+05:30
233,power_connected,28,2025-10-23,21:54:14,+05:30
233,power_disconnected,51,2025-10-23,22:14:26,+05:30
233,power_connected,17,2025-10-24,11:28:40,+05:30
233,power_disconnected,62,2025-10-24,12:01:49,+05:30
233,power_connected,56,2025-10-24,12:50:44,+05:30
233,power_disconnected,69,2025-10-24,13:01:31,+05:30
233,power_connected,49,2025-10-24,14:54:10,+05:30
233,power_disconnected,83,2025-10-24,15:21:31,+05:30
233,power_connected,53,2025-10-24,19:48:03,+05:30
233,power_disconnected,90,2025-10-24,20:19:14,+05:30
233,power_connected,19,2025-10-25,10:38:05,+05:30
233,power_disconnected,39,2025-10-25,10:51:59,+05:30
233,power_connected,29,2025-10-25,13:48:34,+05:30
233,power_disconnected,72,2025-10-25,14:22:20,+05:30
233,power_connected,23,2025-10-25,18:49:06,+05:30
233,power_disconnected,45,2025-10-25,19:06:24,+05:30
233,power_connected,25,2025-10-25,23:03:43,+05:30
233,power_disconnected,29,2025-10-25,23:06:12,+05:30
233,power_connected,19,2025-10-25,23:54:14,+05:30
233,power_disconnected,39,2025-10-26,00:10:47,+05:30
233,power_connected,27,2025-10-26,01:18:58,+05:30
233,power_disconnected,55,2025-10-26,01:44:06,+05:30
233,power_connected,16,2025-10-26,12:24:54,+05:30
233,power_disconnected,67,2025-10-26,13:07:53,+05:30
233,power_connected,62,2025-10-26,13:39:47,+05:30
233,power_disconnected,74,2025-10-26,13:49:33,+05:30
233,power_connected,13,2025-10-26,22:07:20,+05:30
233,power_disconnected,56,2025-10-26,22:33:28,+05:30
233,power_connected,49,2025-10-26,23:30:04,+05:30
233,power_disconnected,69,2025-10-26,23:45:10,+05:30
233,power_connected,65,2025-10-27,00:13:16,+05:30
233,power_disconnected,85,2025-10-27,00:28:06,+05:30
233,power_connected,31,2025-10-27,12:23:29,+05:30
233,power_disconnected,48,2025-10-27,12:37:30,+05:30
233,power_connected,19,2025-10-27,16:22:54,+05:30
233,power_disconnected,48,2025-10-27,16:47:04,+05:30
233,power_connected,46,2025-10-27,16:54:47,+05:30
233,power_disconnected,60,2025-10-27,17:08:45,+05:30
233,power_connected,55,2025-10-27,17:40:17,+05:30
233,power_disconnected,72,2025-10-27,17:54:12,+05:30
233,power_connected,34,2025-10-27,22:24:44,+05:30
233,power_disconnected,34,2025-10-27,22:25:10,+05:30
233,power_connected,27,2025-10-27,23:12:56,+05:30
233,power_disconnected,64,2025-10-27,23:47:35,+05:30
233,power_connected,32,2025-10-28,04:20:20,+05:30
233,power_disconnected,55,2025-10-28,04:38:37,+05:30
233,power_connected,20,2025-10-28,08:04:39,+05:30
233,power_disconnected,76,2025-10-28,08:37:10,+05:30
233,power_connected,35,2025-10-28,17:24:28,+05:30
233,power_disconnected,74,2025-10-28,17:57:09,+05:30
233,power_connected,16,2025-10-29,08:50:40,+05:30
233,power_disconnected,36,2025-10-29,09:01:26,+05:30
233,power_connected,18,2025-10-29,12:51:34,+05:30
233,power_disconnected,56,2025-10-29,13:31:50,+05:30
233,power_connected,37,2025-10-29,15:30:21,+05:30
233,power_disconnected,56,2025-10-29,15:46:17,+05:30
233,power_connected,32,2025-10-29,19:47:07,+05:30
233,power_disconnected,71,2025-10-29,20:12:06,+05:30
233,power_connected,33,2025-10-29,23:44:52,+05:30
233,power_disconnected,38,2025-10-29,23:49:16,+05:30
233,power_connected,18,2025-10-30,08:02:17,+05:30
233,power_disconnected,73,2025-10-30,08:33:29,+05:30
233,power_connected,15,2025-10-30,15:08:27,+05:30
233,power_disconnected,58,2025-10-30,15:45:58,+05:30
233,power_connected,39,2025-10-30,17:57:16,+05:30
233,power_disconnected,40,2025-10-30,17:58:03,+05:30
233,power_connected,27,2025-10-30,19:45:13,+05:30
233,power_disconnected,49,2025-10-30,20:02:55,+05:30
233,power_connected,17,2025-10-30,23:18:29,+05:30
233,power_disconnected,65,2025-10-31,00:00:00,+05:30
233,power_connected,23,2025-10-31,11:00:32,+05:30
233,power_disconnected,44,2025-10-31,11:19:48,+05:30
233,power_connected,26,2025-10-31,13:53:31,+05:30
233,power_disconnected,37,2025-10-31,14:02:49,+05:30
233,power_connected,26,2025-10-31,15:11:32,+05:30
233,power_disconnected,85,2025-10-31,15:47:19,+05:30
233,power_connected,52,2025-10-31,18:54:02,+05:30
233,power_disconnected,72,2025-10-31,19:06:23,+05:30
233,power_connected,27,2025-11-01,00:16:47,+05:30
233,power_disconnected,63,2025-11-01,00:42:25,+05:30
233,power_connected,50,2025-11-01,08:24:25,+05:30
233,power_disconnected,66,2025-11-01,08:33:16,+05:30
233,power_connected,15,2025-11-01,15:05:18,+05:30
233,power_disconnected,90,2025-11-01,16:18:37,+05:30
233,power_connected,12,2025-11-02,11:39:24,+05:30
233,power_disconnected,45,2025-11-02,12:00:08,+05:30
233,power_connected,35,2025-11-02,12:49:00,+05:30
233,power_disconnected,45,2025-11-02,12:56:48,+05:30
233,power_connected,16,2025-11-02,15:48:15,+05:30
233,power_disconnected,63,2025-11-02,16:26:59,+05:30
233,power_connected,28,2025-11-02,21:28:37,+05:30
233,power_disconnected,80,2025-11-02,22:03:08,+05:30
233,power_connected,77,2025-11-02,22:24:23,+05:30
233,power_disconnected,79,2025-11-02,22:28:55,+05:30
233,power_connected,23,2025-11-03,14:07:34,+05:30
233,power_disconnected,90,2025-11-03,15:03:30,+05:30
233,power_connected,17,2025-11-04,00:07:44,+05:30
233,power_disconnected,27,2025-11-04,00:18:00,+05:30
233,power_connected,18,2025-11-04,01:37:43,+05:30
233,power_disconnected,43,2025-11-04,01:56:18,+05:30
233,power_connected,41,2025-11-04,14:01:16,+05:30
233,power_disconnected,71,2025-11-04,14:19:50,+05:30
233,power_connected,37,2025-11-04,17:56:06,+05:30
233,power_disconnected,55,2025-11-04,18:10:12,+05:30
233,power_connected,24,2025-11-04,22:30:48,+05:30
233,power_disconnected,56,2025-11-04,22:56:50,+05:30
233,power_connected,54,2025-11-04,23:05:28,+05:30
233,power_disconnected,65,2025-11-04,23:13:52,+05:30
233,power_connected,16,2025-11-05,15:52:35,+05:30
233,power_disconnected,66,2025-11-05,16:38:46,+05:30
233,power_connected,27,2025-11-05,21:15:57,+05:30
233,power_disconnected,56,2025-11-05,21:40:25,+05:30
233,power_connected,17,2025-11-06,03:48:34,+05:30
233,power_disconnected,66,2025-11-06,04:29:57,+05:30
233,power_connected,27,2025-11-06,14:13:08,+05:30
233,power_disconnected,55,2025-11-06,14:42:40,+05:30
233,power_connected,37,2025-11-06,16:27:15,+05:30
233,power_disconnected,42,2025-11-06,16:30:38,+05:30
233,power_connected,16,2025-11-06,21:38:42,+05:30
233,power_disconnected,48,2025-11-06,22:04:25,+05:30
233,power_connected,36,2025-11-07,01:22:15,+05:30
233,power_disconnected,43,2025-11-07,01:26:04,+05:30
233,power_connected,32,2025-11-07,09:56:21,+05:30
233,power_disconnected,43,2025-11-07,10:02:16,+05:30
233,power_connected,35,2025-11-07,11:11:34,+05:30
233,power_disconnected,79,2025-11-07,11:47:38,+05:30
233,power_connected,48,2025-11-07,15:44:07,+05:30
233,power_disconnected,72,2025-11-07,15:58:21,+05:30
233,power_connected,27,2025-11-07,23:20:29,+05:30
233,power_disconnected,29,2025-11-07,23:22:34,+05:30
233,power_connected,14,2025-11-08,03:22:02,+05:30
233,power_disconnected,70,2025-11-08,03:59:40,+05:30
233,power_connected,25,2025-11-08,17:28:40,+05:30
233,power_disconnected,38,2025-11-08,17:36:23,+05:30
233,power_connected,5,2025-11-08,20:54:15,+05:30
233,power_disconnected,31,2025-11-08,21:09:04,+05:30
233,power_connected,28,2025-11-08,21:45:30,+05:30
233,power_disconnected,63,2025-11-08,22:09:50,+05:30
233,power_connected,37,2025-11-09,04:32:09,+05:30
233,power_disconnected,53,2025-11-09,04:40:34,+05:30
233,power_connected,36,2025-11-09,14:29:11,+05:30
233,power_disconnected,48,2025-11-09,14:35:15,+05:30
233,power_connected,22,2025-11-09,19:35:34,+05:30
233,power_disconnected,51,2025-11-09,19:51:41,+05:30
233,power_connected,41,2025-11-09,21:13:24,+05:30
233,power_disconnected,45,2025-11-09,21:17:32,+05:30
233,power_connected,36,2025-11-09,22:15:48,+05:30
233,power_disconnected,46,2025-11-09,22:21:23,+05:30
233,power_connected,39,2025-11-09,23:04:33,+05:30
233,power_disconnected,88,2025-11-09,23:35:27,+05:30
233,power_connected,33,2025-11-10,14:06:32,+05:30
233,power_disconnected,85,2025-11-10,14:37:33,+05:30
233,power_connected,20,2025-11-11,00:10:34,+05:30
233,power_disconnected,32,2025-11-11,00:16:38,+05:30
233,power_connected,18,2025-11-11,01:36:51,+05:30
233,power_disconnected,64,2025-11-11,02:08:56,+05:30
233,power_connected,31,2025-11-11,12:07:30,+05:30
233,power_disconnected,61,2025-11-11,12:24:16,+05:30
233,power_connected,36,2025-11-11,15:52:13,+05:30
233,power_disconnected,47,2025-11-11,16:00:46,+05:30
233,power_connected,32,2025-11-11,17:20:15,+05:30
233,power_disconnected,47,2025-11-11,17:31:59,+05:30
233,power_connected,15,2025-11-11,21:46:49,+05:30
233,power_disconnected,44,2025-11-11,22:07:36,+05:30
233,power_connected,29,2025-11-12,10:30:37,+05:30
233,power_disconnected,67,2025-11-12,10:55:35,+05:30
233,power_connected,28,2025-11-12,16:07:46,+05:30
233,power_disconnected,73,2025-11-12,16:33:23,+05:30
233,power_connected,69,2025-11-12,17:21:27,+05:30
233,power_disconnected,88,2025-11-12,17:37:48,+05:30
233,power_connected,67,2025-11-12,20:36:03,+05:30
233,power_disconnected,82,2025-11-12,20:47:59,+05:30
233,power_connected,32,2025-11-13,02:21:57,+05:30
233,power_disconnected,44,2025-11-13,02:31:00,+05:30
233,power_connected,20,2025-11-13,14:21:07,+05:30
233,power_disconnected,45,2025-11-13,14:37:41,+05:30
233,power_connected,30,2025-11-13,15:54:17,+05:30
233,power_disconnected,64,2025-11-13,16:23:41,+05:30
233,power_connected,59,2025-11-13,16:58:08,+05:30
233,power_disconnected,70,2025-11-13,17:05:22,+05:30
233,power_connected,21,2025-11-13,23:57:58,+05:30
233,power_disconnected,86,2025-11-14,00:40:30,+05:30
233,power_connected,23,2025-11-14,13:44:52,+05:30
233,power_disconnected,31,2025-11-14,13:51:23,+05:30
233,power_connected,15,2025-11-14,14:58:05,+05:30
233,power_disconnected,34,2025-11-14,15:20:24,+05:30
233,power_connected,22,2025-11-14,16:20:59,+05:30
233,power_disconnected,85,2025-11-14,17:00:46,+05:30""";
}

// File picker bridge
class FileResultPicker {
  static void pickCSVFile(Function(String?) callback) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final fileBytes = result.files.first.bytes;
        if (fileBytes != null) {
          callback(utf8.decode(fileBytes));
          return;
        }
      }
    } catch (e) {
      print('Error picking CSV file: $e');
    }
    callback(null);
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
          duration: const Duration(milliseconds: 800),
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
              duration: const Duration(milliseconds: 800),
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
