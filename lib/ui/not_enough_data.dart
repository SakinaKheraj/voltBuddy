import 'package:flutter/material.dart';
import 'package:voltbuddy/widgets/pet_renderer.dart';

/// Screen displayed while the SQLite database does not yet have enough
/// battery records (fewer than two). It re‑uses the existing `PetRenderer`
/// widget with default arguments and draws a dark, semi‑transparent
/// overlay with a short status text.
class NotEnoughDataScreen extends StatelessWidget {
  const NotEnoughDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Full‑screen background
      body: Stack(
        children: [
          // The regular pet UI – using placeholder defaults.
          const PetRenderer(
            species: 'cat',
            rankIndex: 0,
            batch: 1,
            healthState: 'thriving',
            speechText: '',
            speechVisible: false,
            floatingTexts: [],
            glowTrigger: 0,
          ),
          // Semi‑transparent overlay with the message.
          Container(
            color: Colors.black.withOpacity(0.5),
            alignment: Alignment.center,
            child: const Text(
              'Collecting data…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
