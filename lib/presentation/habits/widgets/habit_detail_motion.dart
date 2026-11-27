import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Scales its child down to 0.95 while pressed (140 ms).
/// Skips animation when [MediaQuery.disableAnimations] is true.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final bool enabled;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.semanticsLabel,
    this.enabled = true,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scaled = AnimatedScale(
      scale: (!reduceMotion && _pressed && widget.enabled) ? 0.95 : 1.0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.enabled && widget.onTap != null
          ? () => setState(() => _pressed = false)
          : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: scaled,
    );

    if (widget.semanticsLabel != null) {
      result = Semantics(
        button: true,
        enabled: widget.enabled && widget.onTap != null,
        label: widget.semanticsLabel,
        child: result,
      );
    }
    return result;
  }
}

/// Fades and slides a card up 14 pt on first build (550 ms, staggered by 50 ms
/// per [index]). Runs once only and is skipped under reduced motion.
class StaggeredEntrance extends StatefulWidget {
  final int index;
  final Widget child;

  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 14),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
      return;
    }
    final delay = Duration(milliseconds: widget.index * 50);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(offset: _slide.value, child: child),
      ),
      child: widget.child,
    );
  }
}

/// Wraps the Today progress ring with the goal-reached celebration:
/// 1 → 1.12 → 1 overshoot scale (600 ms) + 12-dot radial burst (800 ms).
class GoalCelebrationWrapper extends StatefulWidget {
  final int celebrationTick;
  final List<Color> burstColors;
  final Widget child;

  const GoalCelebrationWrapper({
    super.key,
    required this.celebrationTick,
    required this.burstColors,
    required this.child,
  });

  @override
  State<GoalCelebrationWrapper> createState() => _GoalCelebrationWrapperState();
}

class _GoalCelebrationWrapperState extends State<GoalCelebrationWrapper>
    with TickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final AnimationController _burstCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_scaleCtrl);
  }

  @override
  void didUpdateWidget(covariant GoalCelebrationWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.celebrationTick > oldWidget.celebrationTick &&
        !MediaQuery.of(context).disableAnimations) {
      _scaleCtrl.forward(from: 0);
      _burstCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _burstCtrl,
          builder: (context, _) {
            if (_burstCtrl.value == 0 || _burstCtrl.value == 1) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: CustomPaint(
                size: const Size(84, 84),
                painter: _BurstPainter(
                  progress: _burstCtrl.value,
                  colors: widget.burstColors,
                ),
              ),
            );
          },
        ),
        ScaleTransition(scale: _scaleAnim, child: widget.child),
      ],
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _BurstPainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOutCubic.transform(progress);
    final opacity = (1.0 - Curves.easeIn.transform(progress)).clamp(0.0, 1.0);
    const count = 12;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final maxRadius = i.isEven ? 74.0 : 54.0;
      final radius = 34.0 + (maxRadius - 34.0) * eased;
      final pos = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final dotRadius = (1.0 - 0.4 * progress) * (i.isEven ? 4.0 : 3.0);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: opacity);
      canvas.drawCircle(pos, dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.colors != colors;
}
