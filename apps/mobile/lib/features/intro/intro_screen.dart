import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/entrance.dart';
import '../../widgets/lang_toggle.dart';
import '../../widgets/page_dots.dart';
import 'intro_art.dart';

/// Three swipeable intro slides (day counter, companion, doctor). Each slide's
/// picture and copy fade and rise in when it becomes the current page; the
/// pager dot stretches to follow. Skip or the last button calls [onDone].
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  static const _count = 3;

  final _pages = PageController();
  int _index = 0;

  bool get _last => _index == _count - 1;

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    if (AppMotion.reduced(context)) {
      _pages.jumpToPage(_index + 1);
    } else {
      unawaited(
        _pages.nextPage(duration: AppMotion.medium, curve: AppMotion.curve),
      );
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fast = AppMotion.of(context, AppMotion.fast);
    final label = _last ? l10n.introStart : l10n.introNext;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenHorizontal,
                    AppSpace.md,
                    AppSpace.screenHorizontal,
                    0,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 150, child: LangToggle()),
                      const Spacer(),
                      IgnorePointer(
                        ignoring: _last,
                        child: AnimatedOpacity(
                          opacity: _last ? 0 : 1,
                          duration: fast,
                          child: TextButton(
                            onPressed: widget.onDone,
                            child: Text(l10n.introSkip),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      _IntroPage(
                        active: _index == 0,
                        art: StreakArt(active: _index == 0),
                        title: l10n.intro1Title,
                        body: l10n.intro1Body,
                      ),
                      _IntroPage(
                        active: _index == 1,
                        art: CompanionArt(active: _index == 1),
                        title: l10n.intro2Title,
                        body: l10n.intro2Body,
                      ),
                      _IntroPage(
                        active: _index == 2,
                        art: DoctorArt(active: _index == 2),
                        title: l10n.intro3Title,
                        body: l10n.intro3Body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                PageDots(
                  count: _count,
                  index: _index,
                  semanticLabel: l10n.introPageOf(_index + 1, _count),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenHorizontal,
                    AppSpace.xl,
                    AppSpace.screenHorizontal,
                    AppSpace.xl,
                  ),
                  child: FilledButton(
                    onPressed: _next,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: fast,
                          child: Text(label, key: ValueKey(label)),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        // arrow_forward mirrors itself in RTL.
                        const Icon(Icons.arrow_forward, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.active,
    required this.art,
    required this.title,
    required this.body,
  });

  final bool active;
  final Widget art;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.screenHorizontal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Entrance(visible: active, child: art),
          ),
          const SizedBox(height: AppSpace.xl),
          Entrance(
            visible: active,
            offset: AppSpace.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: text.headlineLarge),
                ),
                const SizedBox(height: AppSpace.md),
                Text(body, style: text.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
