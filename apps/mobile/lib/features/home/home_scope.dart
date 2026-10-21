import 'package:flutter/widgets.dart';

/// The three tabs of the signed-in app, in bar order.
enum HomeTab { appointments, recovery, companion }

/// Lets a screen inside the home shell switch tabs, or reload the tabs after
/// it changed something they show (e.g. a new booking).
class HomeShellScope extends InheritedWidget {
  const HomeShellScope({
    super.key,
    required this.select,
    required this.refresh,
    required super.child,
  });

  final ValueChanged<HomeTab> select;
  final VoidCallback refresh;

  /// The enclosing shell, or null outside it (e.g. in a test of one screen).
  static HomeShellScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeShellScope>();

  @override
  bool updateShouldNotify(HomeShellScope oldWidget) => false;
}
