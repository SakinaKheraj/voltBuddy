import 'dart:convert';
import 'package:flutter/services.dart';

class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  String _currentLocale = 'genz'; // Default to Gen Z as in HTML
  Map<String, Map<String, String>> _locales = {
    'regular': _fallbackRegular,
    'genz': _fallbackGenz,
  };

  String get currentLocale => _currentLocale;

  set locale(String value) {
    if (value == 'regular' || value == 'genz') {
      _currentLocale = value;
    }
  }

  Future<void> init() async {
    try {
      final regStr = await rootBundle.loadString('regular.json');
      final regMap = json.decode(regStr) as Map<String, dynamic>;
      _locales['regular'] = regMap.map((key, val) => MapEntry(key, val.toString()));
    } catch (e) {
      print('Warning: Could not load regular.json asset: $e');
    }

    try {
      final genzStr = await rootBundle.loadString('genz.json');
      final genzMap = json.decode(genzStr) as Map<String, dynamic>;
      _locales['genz'] = genzMap.map((key, val) => MapEntry(key, val.toString()));
    } catch (e) {
      print('Warning: Could not load genz.json asset: $e');
    }
  }

  String translate(String key, {String? defaultVal, Map<String, String>? variables}) {
    String text = _locales[_currentLocale]?[key] ?? defaultVal ?? key;
    if (variables != null) {
      variables.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }

  static final Map<String, String> _fallbackRegular = {
    "title": "ChargePet - Timeline & Data Engine",
    "week_label": "Week {num}",
    "cat_btn": "🐱 Cat",
    "dog_btn": "🐶 Dog",
    "rabbit_btn": "🐰 Rabbit",
    "talk_btn": "Talk ✨",
    "battery_health": "Battery Health (HP)",
    "exp_rank_up": "Exp to Rank Up",
    "tab_stats": "Stats",
    "tab_tips": "Tips",
    "tab_logs": "Logs",
    "tab_sandbox": "Dev",
    "journey_map": "Journey Map",
    "path_emperor": "Path to Emperor",
    "run_sim_stats_msg": "Run the simulation in the Logs tab first to build your Journey Map!",
    "pets_advice": "Pet's Advice",
    "ask_advice_btn": "Ask Pet for Advice ✨",
    "run_sim_tips_msg": "Run the simulation in the Logs tab first to receive personalized advice!",
    "general_wisdom": "General Wisdom",
    "rule_20_80_title": "The Golden Rule: 20-80",
    "rule_20_80_desc": "Keep your pet's energy between 20% and 80%. Going to 100% causes stress, and dropping below 20% makes them starve!",
    "night_charge_title": "Beware the Night Charge",
    "night_charge_desc": "Leaving your pet plugged in overnight guarantees severe overcharge damage. Avoid it to keep HP high.",
    "csv_import": "CSV Import",
    "load_csv": "Load CSV",
    "run_simulation": "Run Simulation",
    "tier_progression": "7-Tier Rank Progression",
    "good_charge": "Good Charge (+XP)",
    "overcharge": "Overcharge (-HP)",
    "state_thriving": "Thriving",
    "state_tired": "Tired",
    "state_sick": "Sick",
    "sys_prompt_talk": "You are a companion pet. You speak like a primitive caveman with simple, broken English (e.g., 'Me happy!', 'You charge night many days, me burn!'). Do not break character. Do not use complex words.",
    "sys_prompt_advice": "You are a companion pet. You speak like a primitive caveman with simple, broken English (e.g., 'You charge night many days, me hurt. Do 20 to 80 charge.'). Give actionable tips to the user about their charging habits. Use simple markdown for bolding (**text**).",
    "status_thriving": "Status: Thriving",
    "status_tired": "Status: Tired",
    "status_critical": "Status: Critical",
    "msg_overcharge_penalty": "Overcharge Penalty",
    "msg_critical_starvation": "Critical Starvation",
    "msg_perfect_charge": "Perfect Charge!",
    "msg_standard_charge": "Standard Charge",
    "alert_csv_loaded": "CSV Loaded!",
    "alert_sandbox": "Sandbox Unlocked!",
    "week_complete": "{week} Complete",
    "xp_earned": "XP Earned: ",
    "weeks_away": "~{weeks} Weeks Away",
    "emperor": "You are an Emperor!",
    "rank_1": "Recruit",
    "rank_2": "Squire",
    "rank_3": "Knight",
    "rank_4": "Captain",
    "rank_5": "Lord",
    "rank_6": "Duke",
    "rank_7": "Emperor",
    "asset_label": "Asset: {rank_name} {species} (Batch {batch})",
    "level_label": "RANK {id}",
    "final_rank": "Final Rank: {rank_name}",
    "thinking": "Thinking...",
    "stat_perfect": "Perfect",
    "stat_overcharges": "Overcharges",
    "charging_heatmap": "Charging Heatmap",
    "heatmap_sessions": "🔢 Sessions",
    "heatmap_quality": "⭐ Quality",
    "heatmap_score": "📊 Score",
    "heatmap_less": "Less",
    "heatmap_more": "More",
    "heatmap_overcharge": "overcharge",
    "heatmap_critical": "critical",
    "heatmap_standard": "standard",
    "log_1_label": "Log 1 — Normal Charging",
    "log_2_label": "Log 2 — Bad Charging",
    "log_3_label": "Log 3 — Good Charging",
    "run_sim_log_1": "Run Simulation — Log 1",
    "run_sim_log_2": "Run Simulation — Log 2",
    "run_sim_log_3": "Run Simulation — Log 3",
    "or_try": "or try"
  };

  static final Map<String, String> _fallbackGenz = {
    "title": "VoltBuddy - Vibing & Data",
    "week_label": "Week {num}",
    "cat_btn": "🐱 Kitty",
    "dog_btn": "🐶 Doggo",
    "rabbit_btn": "🐰 Bunbun",
    "talk_btn": "Vibe Check ✨",
    "battery_health": "Battery Vibes (HP)",
    "exp_rank_up": "Clout to Level Up",
    "tab_stats": "Receipts",
    "tab_tips": "Tea",
    "tab_logs": "Logs",
    "tab_sandbox": "Dev",
    "journey_map": "Vibe Check History",
    "path_emperor": "Path to GOAT",
    "run_sim_stats_msg": "Run the sim in the Logs tab first to get your receipts, bestie!",
    "pets_advice": "Spill the Tea",
    "ask_advice_btn": "Ask Pet for Tea ✨",
    "run_sim_tips_msg": "Run the sim first so I can spill the tea!",
    "general_wisdom": "Main Character Energy",
    "rule_20_80_title": "The Golden Rule: 20-80 fr",
    "rule_20_80_desc": "Keep your pet's energy between 20% and 80%. Going to 100% is toxic, and dropping below 20% is literally starving them!",
    "night_charge_title": "Night Charging is an Ick",
    "night_charge_desc": "Leaving it plugged in overnight is major red flag energy. Avoid it to keep HP high.",
    "csv_import": "Drop the CSV",
    "load_csv": "Load Receipts",
    "run_simulation": "Send It",
    "tier_progression": "7-Tier Flex Progression",
    "good_charge": "W Charge (+Clout)",
    "overcharge": "L Charge (-Vibes)",
    "state_thriving": "Bussin",
    "state_tired": "Mid",
    "state_sick": "Down Bad",
    "sys_prompt_talk": "You are a companion pet. You speak like a GenZ teenager who uses a lot of slang like 'no cap', 'fr fr', 'bruh', 'sus', and 'bussin'. Do not break character.",
    "sys_prompt_advice": "You are a companion pet. You speak like a GenZ teenager. Give actionable advice about their charging in slang. Use simple markdown for bolding (**text**).",
    "status_thriving": "Vibe: Bussin",
    "status_tired": "Vibe: Mid",
    "status_critical": "Vibe: Down Bad",
    "msg_overcharge_penalty": "Big Yikes",
    "msg_critical_starvation": "Starving Fr",
    "msg_perfect_charge": "W Charge!",
    "msg_standard_charge": "It's giving charge",
    "alert_csv_loaded": "Receipts Dropped!",
    "alert_sandbox": "Dev Mode Unlocked No Cap!",
    "week_complete": "{week} in the bag",
    "xp_earned": "Clout Gained: ",
    "weeks_away": "~{weeks} Weeks to GOAT",
    "emperor": "You are the GOAT fr!",
    "rank_1": "NPC",
    "rank_2": "Lurker",
    "rank_3": "Based",
    "rank_4": "Verified",
    "rank_5": "Main Character",
    "rank_6": "Sigma",
    "rank_7": "The GOAT",
    "asset_label": "Drip: {rank_name} {species} (Drop {batch})",
    "level_label": "LEVEL {id}",
    "final_rank": "Final Clout: {rank_name}",
    "thinking": "Cooking...",
    "stat_perfect": "W's",
    "stat_overcharges": "L's",
    "charging_heatmap": "Vibe Map",
    "heatmap_sessions": "🔢 Sesh Count",
    "heatmap_quality": "⭐ Vibes",
    "heatmap_score": "📊 Receipts",
    "heatmap_less": "Mid",
    "heatmap_more": "Bussin",
    "heatmap_overcharge": "L charge",
    "heatmap_critical": "starving",
    "heatmap_standard": "ok ig",
    "log_1_label": "Log 1 — Mid Charging",
    "log_2_label": "Log 2 — Down Bad Charging",
    "log_3_label": "Log 3 — W Charging",
    "run_sim_log_1": "Send It — Log 1",
    "run_sim_log_2": "Send It — Log 2",
    "run_sim_log_3": "Send It — Log 3",
    "or_try": "or vibe with"
  };
}
