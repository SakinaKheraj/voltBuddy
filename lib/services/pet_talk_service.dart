import 'dart:math' as math;

/// Offline replies for the pet's Talk button (Google Play build).
///
/// The Play build ships without a Gemini key, so the pet answers from
/// pre-written lines chosen by its situation: charging state, health and
/// which bad habit (overcharging or deep discharge) is hurting it.
class PetTalkService {
  const PetTalkService();

  String line({
    required String healthState, // thriving, tired, sick
    required String persona, // genz, regular
    required String rankName,
    required bool isCharging,
    required int batteryLevel,
    required int overcharges,
    required int criticalStarts,
    math.Random? random,
  }) {
    final rng = random ?? math.Random();
    final genz = persona == 'genz';

    final List<String> options;
    if (isCharging && batteryLevel >= 85) {
      options = genz ? _genzUnplug : _regularUnplug;
    } else if (isCharging) {
      options = genz ? _genzCharging : _regularCharging;
    } else if (healthState == 'thriving') {
      options = (genz ? _genzThriving : _regularThriving)
          .map((l) => l.replaceAll('{rank}', rankName))
          .toList();
    } else if (overcharges >= criticalStarts) {
      options = genz ? _genzOvercharge : _regularOvercharge;
    } else {
      options = genz ? _genzLowBattery : _regularLowBattery;
    }
    return options[rng.nextInt(options.length)];
  }

  static const _genzUnplug = [
    "85% hit. Unplug me rn, no cap.",
    "Bestie, unplug. We're in the danger zone now.",
    "This charge is giving overcooked. Unplug pls.",
    "85% is the vibe. 100% is a red flag.",
  ];
  static const _regularUnplug = [
    "We've reached 85%. Please unplug me now.",
    "That's enough charge. Unplugging now keeps me healthy.",
    "Stopping around 85% protects my battery. Time to unplug.",
  ];

  static const _genzCharging = [
    "Charging up... feeling the power fr.",
    "Snack time! Stop me around 85% though.",
    "Plugged in and thriving. Don't let me hit 100.",
  ];
  static const _regularCharging = [
    "Charging nicely. Please stop around 85%.",
    "Thanks for the charge! Unplug me before 85% if you can.",
    "Energy coming in. Remember the 20-85% rule.",
  ];

  static const _genzThriving = [
    "{rank} status. Your charging habits are bussin.",
    "Main character energy. Keep charging like this.",
    "No notes. This battery care is elite.",
    "Healthy, happy, unbothered. W charging.",
  ];
  static const _regularThriving = [
    "I'm a proud {rank}. Your charging habits are excellent.",
    "Feeling great! Keep charging between 20% and 85%.",
    "Battery health looks strong. Thank you!",
  ];

  static const _genzOvercharge = [
    "Ngl, leaving me at 100% is lowkey hurting me.",
    "Overnight charging is giving pain. Unplug earlier pls.",
    "Too many full charges. My HP is down bad.",
  ];
  static const _regularOvercharge = [
    "Charging to 100% too often is wearing me out.",
    "Please unplug around 85% instead of charging to full.",
    "Long overnight charges hurt my battery health.",
  ];

  static const _genzLowBattery = [
    "You let me hit single digits again. Not cool.",
    "Starving fr. Plug me in before 20%.",
    "Running on fumes is not the vibe. Charge me sooner.",
  ];
  static const _regularLowBattery = [
    "I'm tired. Please charge me before I drop below 20%.",
    "Letting the battery run very low stresses it.",
    "A top-up before 20% would really help me.",
  ];
}
