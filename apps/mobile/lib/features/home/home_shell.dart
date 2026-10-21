import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_flow.dart';
import '../companion/companion_screen.dart';
import '../recovery/recovery_screen.dart';
import 'home_scope.dart';

/// Replaces everything (welcome, sign-in) with the signed-in app.
void openHome(BuildContext context, {HomeTab tab = HomeTab.recovery}) {
  unawaited(
    Navigator.of(context).pushAndRemoveUntil<void>(
      appRoute(HomeShell(initial: tab), reduced: AppMotion.reduced(context)),
      (route) => false,
    ),
  );
}

/// The signed-in app: appointments, recovery and the companion behind a
/// bottom bar. Each tab keeps its state while another is shown. Recovery is
/// the home tab (PRD 5: the reason patients open the app every day).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initial = HomeTab.recovery});

  final HomeTab initial;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late HomeTab _tab = widget.initial;

  /// Bumped to rebuild the appointment and recovery tabs from fresh data.
  int _generation = 0;

  void _select(HomeTab tab) => setState(() => _tab = tab);

  void _refresh() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HomeShellScope(
      select: _select,
      refresh: _refresh,
      child: Scaffold(
        body: IndexedStack(
          index: _tab.index,
          children: [
            AppointmentsGate(
              key: ValueKey('appointments$_generation'),
              showBack: false,
            ),
            RecoveryScreen(key: ValueKey('recovery$_generation')),
            const CompanionScreen(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) => _select(HomeTab.values[i]),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.calendar_month_outlined),
                selectedIcon: const Icon(Icons.calendar_month_rounded),
                label: l10n.navAppointments,
              ),
              NavigationDestination(
                icon: const Icon(Icons.wb_twilight_rounded),
                label: l10n.navRecovery,
              ),
              NavigationDestination(
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: const Icon(Icons.chat_bubble_rounded),
                label: l10n.navCompanion,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
