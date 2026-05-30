import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/simulation_models.dart';
import '../services/localization_service.dart';
import 'neo_brutalist.dart';


class HeatmapWidget extends StatefulWidget {
  final Map<String, DailyMetrics> dailyData;
  final GlobalMetrics globalMetrics;
  final String initialMode;
  final Function(DailyMetrics, String) onDaySelected;
  final VoidCallback onDayDismissed;

  const HeatmapWidget({
    super.key,
    required this.dailyData,
    required this.globalMetrics,
    this.initialMode = 'score',
    required this.onDaySelected,
    required this.onDayDismissed,
  });

  @override
  State<HeatmapWidget> createState() => _HeatmapWidgetState();
}

class _HeatmapWidgetState extends State<HeatmapWidget> {
  late String _mode;
  OverlayEntry? _popoverEntry;
  final Map<String, LayerLink> _layerLinks = {};

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _dismissPopover();
    super.dispose();
  }

  void _dismissPopover() {
    if (_popoverEntry != null) {
      _popoverEntry!.remove();
      _popoverEntry = null;
      widget.onDayDismissed();
    }
  }

  Color _getHeatmapColor(DailyMetrics? dayInfo, String mode) {
    if (dayInfo == null) return const Color(0xFFE8E5D1); // empty day color

    if (mode == 'sessions') {
      final count = dayInfo.sessions;
      if (count == 0) return const Color(0xFF9CA3AF);
      if (count == 1) return const Color(0xFFF9A215);
      if (count == 2) return const Color(0xFF81B29A);
      return const Color(0xFFFACC15);
    }

    if (mode == 'quality') {
      if (dayInfo.overcharges > 0) return const Color(0xFFE07A5F);
      if (dayInfo.criticals > 0) return const Color(0xFFF9A215);
      if (dayInfo.perfects == dayInfo.sessions) return const Color(0xFFFACC15);
      return const Color(0xFF81B29A);
    }

    // mode == 'score'
    final avg = dayInfo.averageScore;
    if (avg >= 90) return const Color(0xFFFACC15);
    if (avg >= 65) return const Color(0xFF81B29A);
    if (avg >= 40) return const Color(0xFFF9A215);
    return const Color(0xFFE07A5F);
  }

  void _showPopover(BuildContext cellContext, DailyMetrics dayInfo, GlobalKey cellKey, LayerLink link) {
    _dismissPopover();

    final RenderBox renderBox = cellKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);

    final loc = LocalizationService();

    final dateObj = DateTime.parse('${dayInfo.date} 00:00:00');
    final dateFormatted = "${_weekdayName(dateObj.weekday)}, ${_monthName(dateObj.month)} ${dateObj.day}";
    final avg = dayInfo.averageScore.round();
    final dayRankName = dayInfo.rankName ?? loc.translate("rank_1", defaultVal: "Recruit");
    final dayRankId = dayInfo.rankAtEndOfDay != null ? dayInfo.rankAtEndOfDay! + 1 : 1;

    final screenWidth = MediaQuery.of(cellContext).size.width;
    const popoverWidth = 220.0;
    const popoverHeight = 115.0;

    final containerWidth = math.min(screenWidth, 480.0);
    final containerLeft = (screenWidth - containerWidth) / 2;
    final containerRight = containerLeft + containerWidth;

    double idealGlobalLeft = position.dx + size.width / 2 - popoverWidth / 2;
    final double minLeft = containerLeft + 12.0;
    final double maxLeft = math.max(minLeft, containerRight - popoverWidth - 12.0);
    double clampedGlobalLeft = idealGlobalLeft.clamp(minLeft, maxLeft);
    double targetRelativeX = clampedGlobalLeft - position.dx;

    double targetRelativeY = -popoverHeight - 8.0;
    if (position.dy < 180.0) {
      targetRelativeY = size.height + 8.0;
    }

    _popoverEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Click outside dismisser
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissPopover,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Popover body
            CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              offset: Offset(targetRelativeX, targetRelativeY),
              child: Material(
                color: Colors.transparent,
                child: NeoCard(
                  width: popoverWidth,
                  height: popoverHeight,
                  backgroundColor: Colors.white,
                  borderWidth: 3.0,
                  borderRadius: 12.0,
                  shadowOffset: const Offset(3, 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dateFormatted.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.bold,
                          fontSize: 10.0,
                          color: NeoColors.rpgText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            "${dayInfo.sessions}",
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.w900,
                              fontSize: 15.0,
                              color: NeoColors.primary,
                            ),
                          ),
                          Text(
                            " session${dayInfo.sessions != 1 ? 's' : ''}",
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.bold,
                              fontSize: 11.0,
                              color: NeoColors.rpgText.withValues(alpha: 0.7),
                            ),
                          ),
                          if (_mode == 'score') ...[
                            const SizedBox(width: 8),
                            Text(
                              "$avg",
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontWeight: FontWeight.w900,
                                fontSize: 15.0,
                                color: _getHeatmapColor(dayInfo, 'score'),
                              ),
                            ),
                            Text(
                              " avg score",
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontWeight: FontWeight.bold,
                                fontSize: 11.0,
                                color: NeoColors.rpgText.withValues(alpha: 0.7),
                              ),
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 2.0,
                        children: [
                          if (dayInfo.perfects > 0)
                            Text(
                              "✦ ${dayInfo.perfects} ${loc.translate('stat_perfect', defaultVal: 'perfect')}",
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          if (dayInfo.overcharges > 0)
                            Text(
                              "⚠ ${dayInfo.overcharges} ${loc.translate('heatmap_overcharge', defaultVal: 'overcharge')}",
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          if (dayInfo.criticals > 0)
                            Text(
                              "▼ ${dayInfo.criticals} ${loc.translate('heatmap_critical', defaultVal: 'critical')}",
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC2410C),
                              ),
                            ),
                        ],
                      ),
                      const Divider(color: Colors.black26, height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "⚔ ${loc.translate('level_label', defaultVal: 'RANK {id}').replaceAll('{id}', '$dayRankId')}: $dayRankName",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                color: NeoColors.rpgText,
                              ),
                            ),
                          ),
                          Text(
                            "${dayInfo.hpAtEndOfDay ?? '?'} HP",
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 9.0,
                              fontWeight: FontWeight.bold,
                              color: (dayInfo.hpAtEndOfDay ?? 100) > 60
                                  ? const Color(0xFF81B29A)
                                  : (dayInfo.hpAtEndOfDay ?? 100) > 30
                                      ? const Color(0xFFF9A215)
                                      : const Color(0xFFE07A5F),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(cellContext).insert(_popoverEntry!);
    widget.onDaySelected(dayInfo, _getDayComment(dayInfo));
  }

  String _weekdayName(int day) {
    const list = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return list[math.min(6, math.max(0, day - 1))];
  }

  String _monthName(int month) {
    const list = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return list[math.min(11, math.max(0, month - 1))];
  }

  String _getDayComment(DailyMetrics dayInfo) {
    final loc = LocalizationService();
    String category = 'good';
    if (dayInfo.overcharges > 0 && dayInfo.perfects > 0) {
      category = 'mixed';
    } else if (dayInfo.overcharges > 0) {
      category = 'bad';
    } else if (dayInfo.criticals > 0) {
      category = 'critical';
    } else if (dayInfo.perfects == dayInfo.sessions) {
      category = 'perfect';
    }

    final pool = loc.currentLocale == 'genz'
        ? _dayCommentsGenz[category]!
        : _dayCommentsRegular[category]!;
    final random = math.Random();
    return pool[random.nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService();

    final dateKeys = widget.dailyData.keys.toList()..sort();
    if (dateKeys.isEmpty) return const SizedBox.shrink();

    final firstDate = DateTime.parse('${dateKeys.first} 00:00:00');
    final lastDate = DateTime.parse('${dateKeys.last} 00:00:00');

    // Adjust firstDate back to nearest preceding Monday
    final firstDow = firstDate.weekday; // 1 (Mon) to 7 (Sun)
    final mondayOffset = 1 - firstDow;
    final startMonday = firstDate.add(Duration(days: mondayOffset));

    final List<DateTime> allDays = [];
    DateTime cursor = startMonday;
    while (cursor.isBefore(lastDate) || cursor.isAtSameMomentAs(lastDate)) {
      allDays.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    while (allDays.length % 7 != 0) {
      allDays.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    final List<List<DateTime>> weeks = [];
    for (int i = 0; i < allDays.length; i += 7) {
      weeks.add(allDays.sublist(i, i + 7));
    }

    // Grid elements count = 1 label + 7 days = 8 columns
    final List<Widget> gridItems = [];
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    // Rows: Week row labels on left, then 7 day cells
    for (int weekIdx = 0; weekIdx < weeks.length; weekIdx++) {
      final week = weeks[weekIdx];
      // Left month label
      final monthStr = _monthName(week[0].month);
      final prevMonthStr = weekIdx > 0 ? _monthName(weeks[weekIdx - 1][0].month) : '';
      final showMonth = (weekIdx == 0 || monthStr != prevMonthStr);

      gridItems.add(
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Text(
              showMonth ? monthStr.toUpperCase() : '',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 9.0,
                fontWeight: FontWeight.bold,
                color: NeoColors.rpgText.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      );

      for (var day in week) {
        final dateStr = day.toString().substring(0, 10);
        final dayInfo = widget.dailyData[dateStr];
        final cellColor = _getHeatmapColor(dayInfo, _mode);
        final cellKey = GlobalKey();
        final link = _layerLinks.putIfAbsent(dateStr, () => LayerLink());

        gridItems.add(
          Builder(
            builder: (cellContext) {
              return CompositedTransformTarget(
                link: link,
                child: _HeatmapCell(
                  key: cellKey,
                  color: cellColor,
                  hasData: dayInfo != null,
                  onTap: dayInfo != null ? () => _showPopover(cellContext, dayInfo, cellKey, link) : null,
                ),
              );
            },
          ),
        );
      }
    }

    final totalDays = dateKeys.length;
    final totalSessions = widget.globalMetrics.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Visual Header mimicking reference screenshot
        Row(
          children: [
            const Icon(Icons.grid_view, color: NeoColors.rpgText, size: 20.0),
            const SizedBox(width: 8),
            Text(
              loc.translate('charging_heatmap', defaultVal: 'Charging Heatmap').toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w900,
                fontSize: 16.0,
                color: NeoColors.rpgText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _buildToggleButton('sessions', loc.translate('heatmap_sessions', defaultVal: 'Sessions'), Icons.format_list_numbered, Colors.blue),
            _buildToggleButton('quality', loc.translate('heatmap_quality', defaultVal: 'Quality'), Icons.star, Colors.amber),
            _buildToggleButton('score', loc.translate('heatmap_score', defaultVal: 'Score'), Icons.bar_chart, Colors.green),
          ],
        ),
        const SizedBox(height: 6),
        // Heatmap Grid Box
        NeoCard(
          backgroundColor: NeoColors.rpgBg,
          borderWidth: 3.0,
          shadowOffset: const Offset(2, 2),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final cellSize = (totalWidth - 28) / 8;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(width: cellSize + 4),
                          for (int i = 0; i < 7; i++) ...[
                            SizedBox(
                              width: cellSize,
                              child: Center(
                                child: Text(
                                  dayLabels[i],
                                  style: TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.bold,
                                    color: NeoColors.rpgText.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                            if (i < 6) const SizedBox(width: 4),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      GridView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: gridItems.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: 1,
                        ),
                        itemBuilder: (context, index) {
                          return gridItems[index];
                        },
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 10),
              // Legend & Summary Row
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          loc.translate('heatmap_less', defaultVal: 'Less'),
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                            color: NeoColors.rpgText.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildLegendSwatch(const Color(0xFF9CA3AF)),
                        _buildLegendSwatch(const Color(0xFFE07A5F)),
                        _buildLegendSwatch(const Color(0xFFF9A215)),
                        _buildLegendSwatch(const Color(0xFF81B29A)),
                        _buildLegendSwatch(const Color(0xFFFACC15)),
                        const SizedBox(width: 4),
                        Text(
                          loc.translate('heatmap_more', defaultVal: 'More'),
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                            color: NeoColors.rpgText.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),

                    Text(
                      "$totalDays ACTIVE DAYS · $totalSessions SESSIONS",
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 9.0,
                        fontWeight: FontWeight.bold,
                        color: NeoColors.rpgText.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendSwatch(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.0),
        border: Border.all(color: NeoColors.rpgText, width: 1.0),
      ),
    );
  }

  Widget _buildToggleButton(String buttonMode, String label, IconData icon, Color iconColor) {
    final active = _mode == buttonMode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = buttonMode;
        });
        _dismissPopover();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NeoColors.rpgText : Colors.white,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: NeoColors.rpgText, width: 2.0),
          boxShadow: active
              ? null
              : const [
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
            Icon(
              icon,
              size: 13.0,
              color: active ? Colors.white : iconColor,
            ),
            const SizedBox(width: 5),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: active ? Colors.white : NeoColors.rpgText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const Map<String, List<String>> _dayCommentsRegular = {
    'perfect': [
      "Me remember this day! You charge good, me belly full!",
      "This day me so happy! 20 to 80, perfect!",
      "Me dance this day! You best human!",
      "Good day! Me strong like ox! You charge right!",
      "Me purr all day! You finally learn!",
    ],
    'good': [
      "This day okay. Me not complain. Could be better though.",
      "Me feel decent this day. You try, me see that.",
      "Not bad day! Me have enough food. Me content.",
      "This day me nap peacefully. You charge okay.",
      "Me remember... was fine day. Me survive!",
    ],
    'bad': [
      "This day you BURN me! Too much charge, me hurt!",
      "Ugh! Me remember pain! You overcharge, me suffer!",
      "Bad day! You plug all night, me belly explode!",
      "Me cry this day! Why you do 100%?! WHY?!",
      "This day me feel fire inside! Stop overcharge!",
    ],
    'critical': [
      "Me STARVE this day! You let battery die!",
      "This day me almost gone! You forget me exist?!",
      "Me so hungry this day... me see darkness...",
      "You let me drop to nothing! Me weak, me scared!",
      "This day me beg for food. You no listen!",
    ],
    'mixed': [
      "This day confusing! Sometimes good, sometimes you hurt me!",
      "Me not know how feel this day. Up and down!",
      "Weird day! You charge good then burn me. Make up mind!",
      "This day give me headache. Good then bad then good...",
      "Me dizzy this day! You all over the place!",
    ],
  };

  static const Map<String, List<String>> _dayCommentsGenz = {
    'perfect': [
      "Yooo this day was bussin no cap! 20-80 perfection fr fr!",
      "This day? Main character energy! You ate!",
      "Slay day! Me was THRIVING bestie!",
      "This was peak performance no cap! You understood the assignment!",
      "W day! Me living my best life fr!",
    ],
    'good': [
      "This day was aight, not gonna lie. It was giving mid.",
      "Decent vibes this day tbh. Could be more bussin tho.",
      "This day? It was okay I guess. Me survived.",
      "Not the worst day, not the best. It's giving neutral.",
      "Meh day. Me vibed but nothing special fr.",
    ],
    'bad': [
      "This day was TOXIC bruh! You burned me alive!",
      "Overcharge?! That's a HUGE L bestie, not cool!",
      "This day was down bad fr! You did me dirty!",
      "Major red flag energy this day! 100% is NOT it!",
      "Bruh this day was sus! Why you tryna fry me?!",
    ],
    'critical': [
      "This day me was STARVING fr fr! You ghosted me!",
      "Me almost unalived this day! Zero energy, zero vibes!",
      "You left me on read AND uncharged?! Down bad fr!",
      "This day was giving starvation core. NOT the vibe!",
      "Me was literally fading this day. Touch grass and charge me!",
    ],
    'mixed': [
      "This day was giving chaos energy tbh! Up and down fr!",
      "Bruh this day was a whole rollercoaster no cap!",
      "Mixed signals much?! Good then bad then good, bestie pick a lane!",
      "This day was lowkey confusing. Me couldn't even!",
      "Emotional damage this day fr! Make up your mind!",
    ],
  };
}

class _HeatmapCell extends StatefulWidget {
  final Color color;
  final bool hasData;
  final VoidCallback? onTap;

  const _HeatmapCell({
    super.key,
    required this.color,
    required this.hasData,
    this.onTap,
  });

  @override
  State<_HeatmapCell> createState() => _HeatmapCellState();
}

class _HeatmapCellState extends State<_HeatmapCell> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _clickController;
  late Animation<double> _clickScaleAnimation;

  @override
  void initState() {
    super.initState();
    _clickController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _clickScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60.0,
      ),
    ]).animate(_clickController);
  }

  @override
  void dispose() {
    _clickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          _clickController.forward(from: 0.0);
          if (widget.onTap != null) {
            widget.onTap!();
          }
        },
        child: AnimatedBuilder(
          animation: _clickScaleAnimation,
          builder: (context, child) {
            final baseScale = _isHovered || _isPressed ? 1.05 : 1.0;
            final clickScale = _clickScaleAnimation.value;
            final totalScale = baseScale * clickScale;
            return Transform.scale(
              scale: totalScale,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(6.5),
                  border: Border.all(
                    color: (_isHovered || _isPressed)
                        ? NeoColors.primary
                        : (widget.hasData ? NeoColors.rpgText : const Color(0xFFD1CBB8)),
                    width: (_isHovered || _isPressed)
                        ? 2.0
                        : (widget.hasData ? 2.0 : 1.0),
                  ),
                  boxShadow: (_isHovered || _isPressed)
                      ? [
                          BoxShadow(
                            color: NeoColors.rpgText.withValues(alpha: 0.3),
                            offset: const Offset(2, 2),
                            blurRadius: 2,
                          )
                        ]
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
