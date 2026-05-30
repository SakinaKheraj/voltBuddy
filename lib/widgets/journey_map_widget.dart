import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/simulation_models.dart';
import '../services/localization_service.dart';
import 'neo_brutalist.dart';


class JourneyMapWidget extends StatelessWidget {
  final Map<String, WeeklyMetrics> weeklyStats;
  final int totalXp;
  final double xpPerWeek;
  final int totalWeeks;

  const JourneyMapWidget({
    super.key,
    required this.weeklyStats,
    required this.totalXp,
    required this.xpPerWeek,
    required this.totalWeeks,
  });

  Color _getNodeColor(int stars) {
    if (stars == 3) return NeoColors.rpgGold;
    if (stars == 2) return NeoColors.primary;
    return NeoColors.rpgMuted;
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService();
    final sortedKeys = weeklyStats.keys.toList()
      ..sort((a, b) {
        final aNum = weeklyStats[a]?.weekNum ?? 0;
        final bNum = weeklyStats[b]?.weekNum ?? 0;
        return aNum.compareTo(bNum); // Chronological order
      });

    if (sortedKeys.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.map, color: NeoColors.rpgText, size: 20.0),
              const SizedBox(width: 8),
              Text(
                loc.translate('vibe_check_history', defaultVal: 'Vibe Check History').toUpperCase(),
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
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: NeoColors.rpgBg,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: NeoColors.rpgText,
                width: 2.0,
                style: BorderStyle.none, // simple dashed box in web
              ),
            ),
            child: Column(
          children: [
            // Simulates dashed border by using a simple border decoration
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: NeoColors.rpgText.withOpacity(0.3),
                  width: 2.0,
                ),
                borderRadius: BorderRadius.circular(12.0),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  loc.translate('run_sim_stats_msg',
                      defaultVal: 'Run the simulation in the Logs tab first to build your Journey Map!'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.bold,
                    color: NeoColors.rpgText.withOpacity(0.6),
                    fontSize: 13.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

    // Path to Legend / Path to GOAT
    const int maxXPNeeded = 600;
    final double weeksLeftDouble = xpPerWeek > 0 ? (maxXPNeeded - totalXp) / xpPerWeek : -1;
    final String weeksLeftText = weeksLeftDouble < 0
        ? "∞"
        : weeksLeftDouble <= 0
            ? "0"
            : weeksLeftDouble.ceil().toString();

    final String predictionText = totalXp >= maxXPNeeded
        ? loc.translate('emperor', defaultVal: 'You are an Emperor!')
        : loc.translate('weeks_away', defaultVal: '~{weeks} Weeks Away').replaceAll('{weeks}', weeksLeftText);

    final double progressPct = math.min(100.0, (totalXp / maxXPNeeded) * 100.0) / 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.map, color: NeoColors.rpgText, size: 20.0),
            const SizedBox(width: 8),
            Text(
              loc.translate('vibe_check_history', defaultVal: 'Vibe Check History').toUpperCase(),
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

        // Path to Legend Banner
        NeoCard(
          backgroundColor: NeoColors.rpgSurface,
          borderWidth: 3.0,
          shadowOffset: const Offset(2, 2),
          child: Column(
            children: [
              Text(
                loc.translate('path_emperor', defaultVal: 'Path to Emperor').toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.bold,
                  fontSize: 11.0,
                  color: Colors.white.withOpacity(0.8),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                predictionText.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  fontSize: 16.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              // Custom progress bar
              Container(
                height: 10.0,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: NeoColors.rpgText, width: 1.5),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progressPct,
                  child: Container(
                    decoration: BoxDecoration(
                      color: NeoColors.rpgGold,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Timeline Path list
        Stack(
          children: [
            // Vertical Line
            Positioned(
              left: 22,
              top: 24,
              bottom: 24,
              child: Container(
                width: 6,
                decoration: BoxDecoration(
                  color: NeoColors.rpgText.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Week Nodes
            ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: sortedKeys.length,
              itemBuilder: (context, idx) {
                final key = sortedKeys[idx];
                final stats = weeklyStats[key]!;
                final nodeColor = _getNodeColor(stats.stars);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Node Badge
                      Container(
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: nodeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: NeoColors.rpgText, width: 3.5),
                          boxShadow: const [
                            BoxShadow(
                              color: NeoColors.rpgText,
                              offset: Offset(2, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            "W${stats.weekNum}",
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.w900,
                              fontSize: 12.0,
                              color: Colors.white,
                            ),

                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Node Card Content
                      Expanded(
                        child: NeoCard(
                          borderWidth: 3.0,
                          shadowOffset: const Offset(3, 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Title & Stars
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    loc.translate('week_complete',
                                            defaultVal: '{week} Complete')
                                        .replaceAll('{week}', key)
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'Space Grotesk',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: NeoColors.rpgText.withOpacity(0.6),
                                    ),
                                  ),
                                  // 3 Star Rating
                                  Row(
                                    children: List.generate(3, (starIdx) {
                                      final filled = starIdx < stats.stars;
                                      return Icon(
                                        Icons.star,
                                        size: 16.0,
                                        color: filled ? NeoColors.rpgGold : Colors.grey[300],
                                        shadows: filled
                                            ? const [
                                                Shadow(
                                                  color: NeoColors.rpgText,
                                                  offset: Offset(1, 1),
                                                  blurRadius: 0,
                                                )
                                              ]
                                            : const [
                                                Shadow(
                                                  color: Colors.grey,
                                                  offset: Offset(1, 1),
                                                  blurRadius: 0,
                                                )
                                              ],
                                      );
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Grid stats
                              Row(
                                children: [
                                  // Perfect charges
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD1FAE5),
                                        borderRadius: BorderRadius.circular(6.0),
                                        border: Border.all(color: const Color(0xFF065F46), width: 1.5),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            loc.translate('stat_perfect', defaultVal: 'Perfect').toUpperCase(),
                                            style: const TextStyle(
                                              fontFamily: 'Space Grotesk',
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xAA065F46),
                                            ),
                                          ),
                                          Text(
                                            "${stats.perf}",
                                            style: const TextStyle(
                                              fontFamily: 'Space Grotesk',
                                              fontSize: 13.0,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF065F46),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Overcharges
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(6.0),
                                        border: Border.all(color: NeoColors.rpgBad, width: 1.5),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            loc.translate('stat_overcharges', defaultVal: 'Overcharges').toUpperCase(),
                                            style: const TextStyle(
                                              fontFamily: 'Space Grotesk',
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xAADC2626),
                                            ),
                                          ),
                                          Text(
                                            "${stats.over}",
                                            style: const TextStyle(
                                              fontFamily: 'Space Grotesk',
                                              fontSize: 13.0,
                                              fontWeight: FontWeight.w900,
                                              color: NeoColors.rpgBad,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // XP Earned Banner
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 6.0),
                                decoration: BoxDecoration(
                                  color: NeoColors.rpgBg,
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(color: NeoColors.rpgText, width: 1.5),
                                ),
                                child: Center(
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 10.0,
                                        fontWeight: FontWeight.bold,
                                        color: NeoColors.rpgText,
                                      ),
                                      children: [
                                        TextSpan(text: "${loc.translate('xp_earned', defaultVal: 'XP Earned:')} "),
                                        TextSpan(
                                          text: "+${stats.xp}",
                                          style: const TextStyle(
                                            color: NeoColors.primary,
                                            fontSize: 13.0,
                                            fontWeight: FontWeight.w900,
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
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
