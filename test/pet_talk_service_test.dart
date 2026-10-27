import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:voltbuddy/services/pet_talk_service.dart';

void main() {
  const talk = PetTalkService();

  String say({
    String health = 'thriving',
    String persona = 'regular',
    bool charging = false,
    int level = 50,
    int overcharges = 0,
    int criticals = 0,
    int seed = 1,
  }) =>
      talk.line(
        healthState: health,
        persona: persona,
        rankName: 'Knight',
        isCharging: charging,
        batteryLevel: level,
        overcharges: overcharges,
        criticalStarts: criticals,
        random: math.Random(seed),
      );

  test('asks to unplug when charging at 85% or more', () {
    for (var seed = 0; seed < 10; seed++) {
      expect(say(charging: true, level: 90, seed: seed).toLowerCase(),
          anyOf(contains('unplug'), contains('85%')));
    }
  });

  test('blames the habit that is actually hurting the pet', () {
    for (var seed = 0; seed < 10; seed++) {
      expect(say(health: 'sick', overcharges: 5, criticals: 1, seed: seed),
          anyOf(contains('100%'), contains('85%'), contains('overnight')));
      expect(say(health: 'tired', overcharges: 0, criticals: 4, seed: seed),
          anyOf(contains('20%'), contains('low')));
    }
  });

  test('fills in the rank and never leaves a placeholder', () {
    for (var seed = 0; seed < 20; seed++) {
      expect(say(seed: seed), isNot(contains('{rank}')));
    }
  });

  test('uses the selected persona', () {
    final genz = {
      for (var seed = 0; seed < 20; seed++)
        say(persona: 'genz', charging: true, level: 90, seed: seed)
    };
    final regular = {
      for (var seed = 0; seed < 20; seed++)
        say(persona: 'regular', charging: true, level: 90, seed: seed)
    };
    expect(genz.intersection(regular), isEmpty);
  });
}
