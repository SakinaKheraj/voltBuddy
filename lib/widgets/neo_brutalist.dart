import 'package:flutter/material.dart';

class NeoColors {
  static const primary = Color(0xFFF9A215);
  static const rpgText = Color(0xFF3D405B);
  static const rpgAccent = Color(0xFF2A9D8F);
  static const rpgBg = Color(0xFFF4F1DE);
  static const rpgSurface = Color(0xFF81B29A);
  static const rpgMuted = Color(0xFFE07A5F);
  static const rpgGold = Color(0xFFFACC15);
  static const rpgSilver = Color(0xFF9CA3AF);
  static const rpgRoyal = Color(0xFF6B21A8);
  static const rpgDuke = Color(0xFF991B1B);
  static const rpgBad = Color(0xFFDC2626);
}

class NeoCard extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final Offset shadowOffset;
  final Color shadowColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const NeoCard({
    super.key,
    required this.child,
    this.backgroundColor = Colors.white,
    this.borderColor = NeoColors.rpgText,
    this.borderWidth = 4.0,
    this.borderRadius = 12.0,
    this.shadowOffset = const Offset(4, 4),
    this.shadowColor = NeoColors.rpgText,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: shadowOffset != Offset.zero
            ? [
                BoxShadow(
                  color: shadowColor,
                  offset: shadowOffset,
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - borderWidth),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(12.0),
          child: child,
        ),
      ),
    );
  }
}

class NeoButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final Offset shadowOffset;
  final Color shadowColor;
  final EdgeInsetsGeometry padding;

  const NeoButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.backgroundColor = Colors.white,
    this.borderColor = NeoColors.rpgText,
    this.borderWidth = 3.0,
    this.borderRadius = 12.0,
    this.shadowOffset = const Offset(3, 3),
    this.shadowColor = NeoColors.rpgText,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  });

  @override
  State<NeoButton> createState() => _NeoButtonState();
}

class _NeoButtonState extends State<NeoButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onPressed != null) {
          _controller.animateTo(1.0, duration: const Duration(milliseconds: 60), curve: Curves.easeIn);
        }
      },
      onTapUp: (_) {
        if (widget.onPressed != null) {
          _controller.animateTo(0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutBack);
          widget.onPressed?.call();
        }
      },
      onTapCancel: () {
        if (widget.onPressed != null) {
          _controller.animateTo(0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutBack);
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final val = _anim.value;
          return Transform.translate(
            offset: Offset(val * widget.shadowOffset.dx, val * widget.shadowOffset.dy),
            child: Container(
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: widget.borderColor,
                  width: widget.borderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.shadowColor,
                    offset: Offset(
                      widget.shadowOffset.dx * (1.0 - val),
                      widget.shadowOffset.dy * (1.0 - val),
                    ),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Padding(
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}
