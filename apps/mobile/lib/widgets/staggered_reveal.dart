import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Reveals [children] one after another, [AppMotion.stagger] apart: each
/// fades and rises into place, or pops in with [pop]. Plays once, the first
/// time [active] is true. A controller is used because the items are
/// sequenced; for a single item use an implicit animation instead.
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.children,
    this.active = true,
    this.pop = false,
    this.direction = Axis.vertical,
    this.spacing = AppSpace.md,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final bool active;
  final bool pop;
  final Axis direction;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total(widget.children.length),
  );

  static Duration _total(int count) =>
      AppMotion.medium + AppMotion.stagger * math.max(count - 1, 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePlay();
  }

  @override
  void didUpdateWidget(StaggeredReveal old) {
    super.didUpdateWidget(old);
    _controller.duration = _total(widget.children.length);
    _maybePlay();
  }

  void _maybePlay() {
    if (!widget.active || !_controller.isDismissed) return;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.children.length;
    final total = _total(count).inMicroseconds;
    final items = <Widget>[];
    for (var i = 0; i < count; i++) {
      final start = (AppMotion.stagger * i).inMicroseconds / total;
      final end = math.min(
        (AppMotion.stagger * i + AppMotion.medium).inMicroseconds / total,
        1.0,
      );
      final fade = _controller.drive(
        CurveTween(curve: Interval(start, end, curve: AppMotion.curve)),
      );
      final child = widget.children[i];
      items.add(
        FadeTransition(
          opacity: fade,
          child: widget.pop
              ? ScaleTransition(
                  scale: _controller.drive(
                    Tween<double>(begin: 0.5, end: 1).chain(
                      CurveTween(
                        curve: Interval(start, end, curve: AppMotion.pop),
                      ),
                    ),
                  ),
                  child: child,
                )
              : SlideTransition(
                  position: fade.drive(
                    Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ),
                  ),
                  child: child,
                ),
        ),
      );
    }
    return Flex(
      direction: widget.direction,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      spacing: widget.spacing,
      children: items,
    );
  }
}
