import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'neo_brutalist.dart';

class FloatingTextModel {
  final String text;
  final Color color;
  final double xOffset; // horizontal scatter
  final double yOffset; // vertical base offset
  final UniqueKey id = UniqueKey();

  FloatingTextModel({
    required this.text,
    required this.color,
    required this.xOffset,
    required this.yOffset,
  });
}

class PetRenderer extends StatefulWidget {
  final String species; // cat, dog, rabbit
  final int rankIndex; // 0 to 6
  final int batch; // 1 to 5
  final String healthState; // thriving, tired, sick
  final String speechText;
  final bool speechVisible;
  final List<FloatingTextModel> floatingTexts;

  const PetRenderer({
    super.key,
    required this.species,
    required this.rankIndex,
    required this.batch,
    required this.healthState,
    required this.speechText,
    required this.speechVisible,
    required this.floatingTexts,
  });

  @override
  State<PetRenderer> createState() => _PetRendererState();
}

class _PetRendererState extends State<PetRenderer>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  late AnimationController _auraController;
  late Animation<double> _auraScaleAnimation;
  late Animation<double> _auraOpacityAnimation;

  late AnimationController _breathController;
  late Animation<double> _breathAnimation;

  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  Timer? _blinkTimer;

  late AnimationController _wiggleController;
  late Animation<double> _wiggleAnimation;
  Timer? _wiggleTimer;

  late AnimationController _transitionController;
  late Animation<double> _transitionScale;

  late AnimationController _speciesChangeController;
  late Animation<double> _speciesChangeScale;
  late Animation<double> _speciesChangeGlow;

  @override
  void initState() {
    super.initState();

    // Floating/Bouncing
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: 0.0, end: -8.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    // Shaking (for sick state)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 4.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.linear),
    );

    // Aura Pulsing
    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _auraScaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _auraController, curve: Curves.easeInOut),
    );
    _auraOpacityAnimation = Tween<double>(begin: 0.4, end: 0.7).animate(
      CurvedAnimation(parent: _auraController, curve: Curves.easeInOut),
    );

    // Breathing/Squish
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _breathAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    // Blinking
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    _blinkTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _blinkController.forward().then((_) => _blinkController.reverse());
      }
    });

    // Ear wiggles
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _wiggleAnimation = Tween<double>(begin: 0.0, end: 0.12).animate(
      CurvedAnimation(parent: _wiggleController, curve: Curves.easeInOut),
    );
    _wiggleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && math.Random().nextBool()) {
        _wiggleController.forward().then((_) => _wiggleController.reverse());
      }
    });

    // Transitions scale burst
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _transitionScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 70),
    ]).animate(_transitionController);

    // Species change scale and glow sequence
    _speciesChangeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _speciesChangeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.4).chain(CurveTween(curve: Curves.easeOut)), weight: 12),
      TweenSequenceItem(tween: Tween<double>(begin: 1.4, end: 1.4), weight: 68),
      TweenSequenceItem(tween: Tween<double>(begin: 1.4, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
    ]).animate(_speciesChangeController);

    _speciesChangeGlow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 12),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 68),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
    ]).animate(_speciesChangeController);

    _updateStateControllers();
  }

  @override
  void didUpdateWidget(PetRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final speciesChanged = oldWidget.species != widget.species;
    final otherChanged = oldWidget.rankIndex != widget.rankIndex ||
        oldWidget.healthState != widget.healthState;

    if (speciesChanged) {
      _speciesChangeController.forward(from: 0.0);
    } else if (otherChanged) {
      _transitionController.forward(from: 0.0);
    }
    _updateStateControllers();
  }

  void _updateStateControllers() {
    if (widget.healthState == 'sick') {
      _shakeController.repeat(reverse: true);
    } else {
      _shakeController.stop();
      _shakeController.reset();
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _shakeController.dispose();
    _auraController.dispose();
    _breathController.dispose();
    _blinkController.dispose();
    _wiggleController.dispose();
    _transitionController.dispose();
    _speciesChangeController.dispose();
    _blinkTimer?.cancel();
    _wiggleTimer?.cancel();
    super.dispose();
  }

  String _getMood() {
    if (widget.healthState == 'sick') {
      return 'overheated';
    } else if (widget.healthState == 'tired') {
      return 'sleepy';
    } else {
      if (widget.rankIndex >= 6) return 'evolved';
      return 'happy';
    }
  }

  Color _getAuraColor() {
    if (widget.healthState == 'sick') {
      return NeoColors.rpgMuted;
    } else if (widget.healthState == 'tired') {
      return Colors.grey.shade400;
    }
    return NeoColors.rpgGold;
  }

  ColorFilter _getColorFilter() {
    if (widget.healthState == 'tired') {
      // Grayscale(40%) + Brightness(90%)
      return const ColorFilter.matrix(<double>[
        0.6165, 0.2575, 0.0260, 0, 0,
        0.0765, 0.7975, 0.0260, 0, 0,
        0.0765, 0.2575, 0.5660, 0, 0,
        0,      0,      0,      1, 0,
      ]);
    } else if (widget.healthState == 'sick') {
      // Grayscale(70%) + Sepia(50%) + Hue-Rotate(-50deg) + Saturate(3)
      return const ColorFilter.matrix(<double>[
        0.52, 0.41, 0.07, 0, 0,
        0.33, 0.72, 0.15, 0, 0,
        0.15, 0.25, 0.55, 0, 0,
        0,    0,    0,    1, 0,
      ]);
    }
    return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // ARCADE DECORATIVE SHADOW UNDERNEATH
            Positioned(
              bottom: 25,
              child: Opacity(
                opacity: 0.15 - (_floatAnimation.value * 0.005),
                child: Transform.scale(
                  scale: 1.0 + (_floatAnimation.value * 0.02) + (_breathAnimation.value * 0.04),
                  child: Container(
                    width: 100,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.black26,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),

            // PULSING AURA
            AnimatedBuilder(
              animation: _auraController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _auraScaleAnimation.value,
                  child: Opacity(
                    opacity: _auraOpacityAnimation.value,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _getAuraColor().withValues(alpha: 0.5),
                            _getAuraColor().withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // SPECIES CHANGE GOLDEN GLOW (Strong golden radial glow)
            AnimatedBuilder(
              animation: _speciesChangeGlow,
              builder: (context, child) {
                final glowVal = _speciesChangeGlow.value;
                if (glowVal == 0.0) return const SizedBox.shrink();
                return Opacity(
                  opacity: glowVal,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFFEE58).withValues(alpha: 0.9), // Bright yellow/gold
                          NeoColors.rpgGold.withValues(alpha: 0.6),      // Golden color
                          NeoColors.rpgGold.withValues(alpha: 0.0),      // Fade out
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),

            // SPEECH BUBBLE
            if (widget.speechVisible)
              Positioned(
                top: -35,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  builder: (context, val, child) {
                    final floatOffset = _floatAnimation.value * 0.5;
                    return Transform.translate(
                      offset: Offset(0, floatOffset),
                      child: Transform.scale(
                        scale: val,
                        child: child,
                      ),
                    );
                  },
                  child: NeoCard(
                    backgroundColor: Colors.white,
                    borderWidth: 3.0,
                    borderRadius: 16.0,
                    shadowOffset: const Offset(3, 3),
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    width: 220,
                    child: Center(
                      child: Text(
                        widget.speechText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.bold,
                          fontSize: 12.0,
                          color: NeoColors.rpgText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // FLOATING TEXT OVERLAYS
            ...widget.floatingTexts.map((ft) {
              return FloatingOverlayText(
                key: ft.id,
                text: ft.text,
                color: ft.color,
                xOffset: ft.xOffset,
                yOffset: ft.yOffset,
              );
            }),

            // MAIN PET STAGE (FLOAT + SHAKE + SQUISH + TRANSITION BURST)
            AnimatedBuilder(
              animation: Listenable.merge([
                _floatAnimation,
                _shakeAnimation,
                _breathAnimation,
                _transitionScale,
                _speciesChangeScale,
                _speciesChangeGlow,
              ]),
              child: ColorFiltered(
                colorFilter: _getColorFilter(),
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: Center(
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // EARS (Absolute positioned behind face)
                          _buildEars(),

                          // FACE BASE (The main orange circle)
                          _buildFaceBase(),

                          // EQUIPMENT LAYERS
                          _buildEquipment(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              builder: (context, cachedChild) {
                double yVal = widget.healthState == 'tired' ? 5.0 : _floatAnimation.value;
                double xVal = 0.0;
                if (widget.healthState == 'sick') {
                  xVal = _shakeAnimation.value * (math.sin(DateTime.now().millisecondsSinceEpoch / 25) > 0 ? 1 : -1);
                }

                final double totalScale = _transitionScale.value * _speciesChangeScale.value;

                return Transform.scale(
                  scale: totalScale,
                  child: Transform.translate(
                    offset: Offset(xVal, yVal),
                    child: cachedChild,
                  ),
                );
              },
            ),



          ],
        ),
      ),
    );
  }

  Widget _buildEars() {
    final double wiggleVal = _wiggleAnimation.value * 50; // rotation wiggle in degrees

    switch (widget.species) {
      case 'dog':
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Left ear
            Positioned(
              top: 10,
              left: -15,
              child: Transform.rotate(
                angle: (15 - wiggleVal) * math.pi / 180,
                child: Container(
                  width: 32,
                  height: 48,
                  decoration: BoxDecoration(
                    color: NeoColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(0),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
              ),
            ),
            // Right ear
            Positioned(
              top: 10,
              right: -15,
              child: Transform.rotate(
                angle: (-15 + wiggleVal) * math.pi / 180,
                child: Container(
                  width: 32,
                  height: 48,
                  decoration: BoxDecoration(
                    color: NeoColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(0),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'rabbit':
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Left ear
            Positioned(
              top: -45,
              left: 20,
              child: Transform.rotate(
                angle: (-5 - wiggleVal * 0.5) * math.pi / 180,
                child: Container(
                  width: 20,
                  height: 70,
                  decoration: BoxDecoration(
                    color: NeoColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border.all(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
              ),
            ),
            // Right ear
            Positioned(
              top: -45,
              right: 20,
              child: Transform.rotate(
                angle: (5 + wiggleVal * 0.5) * math.pi / 180,
                child: Container(
                  width: 20,
                  height: 70,
                  decoration: BoxDecoration(
                    color: NeoColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border.all(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'cat':
      default:
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Left ear
            Positioned(
              top: -12,
              left: -8,
              child: Transform.rotate(
                angle: (-12 - wiggleVal) * math.pi / 180,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NeoColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                    ),
                    border: Border.all(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
              ),
            ),
            // Right ear
            Positioned(
              top: -12,
              right: -8,
              child: Transform.rotate(
                angle: (12 + wiggleVal) * math.pi / 180,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NeoColors.primary,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                    ),
                    border: Border.all(color: NeoColors.rpgText, width: 4.0),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildFaceBase() {
    final mood = _getMood();
    final double eyeHeight = (mood == 'sleepy' ? 3.0 : 16.0) * _blinkAnimation.value;

    Widget mouth;
    if (mood == 'overheated') {
      // Gasping open mouth
      mouth = Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          color: NeoColors.rpgText,
          shape: BoxShape.circle,
        ),
      );
    } else if (mood == 'sleepy') {
      // Sleek tiny curved mouth
      mouth = Container(
        width: 12,
        height: 8,
        decoration: BoxDecoration(
          border: const Border(
            bottom: BorderSide(color: NeoColors.rpgText, width: 3.0),
          ),
          borderRadius: BorderRadius.circular(999.0),
        ),
      );
    } else if (widget.healthState == 'sick') {
      // Sad face rotate
      mouth = Transform.translate(
        offset: const Offset(0, 5),
        child: Transform.rotate(
          angle: math.pi,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: NeoColors.rpgText, width: 4.0),
              ),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    } else {
      mouth = Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: NeoColors.rpgText, width: 4.0),
          ),
          shape: BoxShape.circle,
        ),
      );
    }

    Widget snout;
    switch (widget.species) {
      case 'dog':
        snout = Container(
          width: 24,
          height: 14,
          decoration: BoxDecoration(
            color: NeoColors.rpgText,
            borderRadius: BorderRadius.circular(8.0),
          ),
        );
        break;
      case 'rabbit':
        snout = Container(
          width: 8,
          height: 6,
          decoration: const BoxDecoration(
            color: NeoColors.rpgText,
            shape: BoxShape.circle,
          ),
        );
        break;
      case 'cat':
      default:
        snout = Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(
            color: NeoColors.rpgText,
            borderRadius: BorderRadius.circular(999.0),
          ),
        );
        break;
    }

    // Left and Right eyes with dynamic wiggles / stress angles
    Widget leftEye = Container(
      width: 12,
      height: eyeHeight,
      decoration: BoxDecoration(
        color: NeoColors.rpgText,
        borderRadius: BorderRadius.circular(999.0),
      ),
    );
    Widget rightEye = Container(
      width: 12,
      height: eyeHeight,
      decoration: BoxDecoration(
        color: NeoColors.rpgText,
        borderRadius: BorderRadius.circular(999.0),
      ),
    );

    if (mood == 'overheated') {
      leftEye = Transform.rotate(
        angle: -15 * math.pi / 180,
        child: leftEye,
      );
      rightEye = Transform.rotate(
        angle: 15 * math.pi / 180,
        child: rightEye,
      );
    }

    // Breathing squish scales
    double scaleX = 1.0 + _breathAnimation.value * 0.03;
    double scaleY = 1.0 - _breathAnimation.value * 0.03;

    return Transform(
      transform: Matrix4.identity()..scale(scaleX, scaleY),
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: NeoColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: NeoColors.rpgText, width: 4.0),
          boxShadow: const [
            BoxShadow(
              color: NeoColors.rpgText,
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // STRIPES (Only for cat species)
            if (widget.species == 'cat')
              Positioned(
                top: 8,
                child: Opacity(
                  opacity: 0.3,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 24,
                        decoration: BoxDecoration(
                          color: NeoColors.rpgText,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 32,
                        decoration: BoxDecoration(
                          color: NeoColors.rpgText,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 24,
                        decoration: BoxDecoration(
                          color: NeoColors.rpgText,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // EYES & SNOUT
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    leftEye,
                    const SizedBox(width: 32),
                    rightEye,
                  ],
                ),
                const SizedBox(height: 8),
                snout,
                mouth,
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipment() {
    switch (widget.batch) {
      case 1:
        // Batch 1: brown platform under pet
        return Positioned(
          bottom: -8,
          child: Container(
            width: 128,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5A2B),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(999)),
              border: Border.all(color: NeoColors.rpgText, width: 4.0),
            ),
          ),
        );
      case 2:
        // Batch 2: silver helmet at top, silver cowl below
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Standard/Spike
            Positioned(
              top: -48,
              left: 64, // center it (width is 32)
              child: Container(
                width: 32,
                height: 40,
                decoration: BoxDecoration(
                  color: NeoColors.rpgMuted,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Helmet body
            Positioned(
              top: -16,
              left: 10,
              child: Container(
                width: 140,
                height: 64,
                decoration: BoxDecoration(
                  color: NeoColors.rpgSilver,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Cowl at bottom
            Positioned(
              bottom: -8,
              left: 10,
              child: Container(
                width: 140,
                height: 48,
                decoration: BoxDecoration(
                  color: NeoColors.rpgText,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    2,
                    (_) => Container(
                      width: 8,
                      height: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: NeoColors.rpgSilver,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 3:
        // Batch 3: shoulder plates, green wings
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Left wing
            Positioned(
              bottom: -16,
              left: -24,
              child: Container(
                width: 48,
                height: 96,
                decoration: BoxDecoration(
                  color: NeoColors.rpgSurface,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Right wing
            Positioned(
              bottom: -16,
              right: -24,
              child: Container(
                width: 48,
                height: 96,
                decoration: BoxDecoration(
                  color: NeoColors.rpgSurface,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Shoulder plates
            Positioned(
              top: 24,
              left: 16,
              child: Container(
                width: 128,
                height: 56,
                decoration: BoxDecoration(
                  color: NeoColors.rpgSilver,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
                child: Center(
                  child: Container(
                    width: 64,
                    height: 8,
                    color: NeoColors.rpgText,
                  ),
                ),
              ),
            ),
          ],
        );
      case 4:
        // Batch 4: crown, cape, medallion
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Crown plume
            Positioned(
              top: -16,
              left: 64,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Crown
            Positioned(
              top: 8,
              left: 15,
              child: Container(
                width: 130,
                height: 60,
                decoration: BoxDecoration(
                  color: NeoColors.rpgGold,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Left cape
            Positioned(
              bottom: -24,
              left: -32,
              child: Container(
                width: 64,
                height: 112,
                decoration: BoxDecoration(
                  color: NeoColors.rpgDuke,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Right cape
            Positioned(
              bottom: -24,
              right: -32,
              child: Container(
                width: 64,
                height: 112,
                decoration: BoxDecoration(
                  color: NeoColors.rpgDuke,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
              ),
            ),
            // Medallion cowl
            Positioned(
              bottom: -8,
              left: 10,
              child: Container(
                width: 140,
                height: 50,
                decoration: BoxDecoration(
                  color: NeoColors.rpgSilver,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: NeoColors.rpgGold,
                      shape: BoxShape.circle,
                      border: Border.all(color: NeoColors.rpgText, width: 4.0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 5:
        // Batch 5: emperor peaks, purple royal cape
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Emperor Crown peaks
            Positioned(
              top: -32,
              left: 40,
              child: Row(
                children: [
                  Transform(
                    transform: Matrix4.skewX(0.2),
                    child: Container(
                      width: 32,
                      height: 48,
                      decoration: BoxDecoration(
                        color: NeoColors.rpgGold,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        border: Border.all(color: NeoColors.rpgText, width: 4.0),
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 64,
                    decoration: BoxDecoration(
                      color: NeoColors.rpgGold,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      border: Border.all(color: NeoColors.rpgText, width: 4.0),
                    ),
                  ),
                  Transform(
                    transform: Matrix4.skewX(-0.2),
                    child: Container(
                      width: 32,
                      height: 48,
                      decoration: BoxDecoration(
                        color: NeoColors.rpgGold,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        border: Border.all(color: NeoColors.rpgText, width: 4.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Purple Royal Cape
            Positioned(
              bottom: -16,
              left: -12,
              child: Container(
                width: 184,
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                decoration: BoxDecoration(
                  color: NeoColors.rpgRoyal,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(999)),
                  border: Border.all(color: NeoColors.rpgText, width: 4.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    2,
                    (_) => Container(
                      width: 24,
                      height: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border.symmetric(
                          vertical: BorderSide(color: NeoColors.rpgText, width: 4.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class FloatingOverlayText extends StatefulWidget {
  final String text;
  final Color color;
  final double xOffset;
  final double yOffset;

  const FloatingOverlayText({
    super.key,
    required this.text,
    required this.color,
    required this.xOffset,
    required this.yOffset,
  });

  @override
  State<FloatingOverlayText> createState() => _FloatingOverlayTextState();
}

class _FloatingOverlayTextState extends State<FloatingOverlayText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnim;
  late Animation<double> _opacityAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _yAnim = Tween<double>(begin: 0.0, end: -40.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0)),
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: 108 + widget.yOffset + _yAnim.value, // adjusted from 48 to 108 to account for 280 vs 160 base height
          left: 140 + widget.xOffset, // adjusted from 80 to 140 to center in 280 width
          child: Opacity(
            opacity: _opacityAnim.value,
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: Text(
                widget.text,
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w900,
                  fontSize: 24.0,
                  color: widget.color,
                  shadows: const [
                    Shadow(
                      color: NeoColors.rpgText,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

