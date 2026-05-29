import 'package:flutter/material.dart';
import 'package:voltbuddy/data/battery_db.dart';
import 'package:voltbuddy/ui/not_enough_data.dart';
import 'package:voltbuddy/widgets/pet_renderer.dart';

/// The entry point widget used in `MaterialApp.home`.
/// It checks how many battery records are stored.
/// * If fewer than 2 records → shows a semi‑transparent overlay (`NotEnoughDataScreen`).
/// * Otherwise → shows the normal `PetRenderer` UI.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: BatteryDb().count(),
      builder: (context, snapshot) {
        // While waiting for the DB query
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Not enough entries – show placeholder overlay
        if (snapshot.data! < 2) {
          return const NotEnoughDataScreen();
        }
        // Enough data – render the normal UI. Use default args for now.
        return const PetRenderer(
          species: 'cat',
          rankIndex: 0,
          batch: 1,
          healthState: 'thriving',
          speechText: '',
          speechVisible: false,
          floatingTexts: [],
          glowTrigger: 0,
        );
      },
    );
  }
}
