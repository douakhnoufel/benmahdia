import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// AR / FR switch. Changing it flips the whole app's direction; the indicator
/// slides to the new side.
class LangToggle extends ConsumerWidget {
  const LangToggle({super.key});

  static const _arabic = Locale('ar');
  static const _french = Locale('fr');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(localeProvider);
    final isArabic = selected.languageCode == 'ar';
    final notifier = ref.read(localeProvider.notifier);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: AppColors.sand100,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.curve,
            alignment: AlignmentDirectional(isArabic ? -1 : 1, 0),
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.sm,
                ),
              ),
            ),
          ),
          Row(
            children: [
              _Segment(
                label: l10n.langArabic,
                selected: isArabic,
                onTap: () => notifier.set(_arabic),
              ),
              _Segment(
                label: l10n.langFrench,
                selected: !isArabic,
                onTap: () => notifier.set(_french),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? AppColors.teal700 : AppColors.textMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
