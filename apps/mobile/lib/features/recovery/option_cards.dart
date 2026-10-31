import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import 'recovery_models.dart';

/// Icon shown on a substance card.
IconData substanceIcon(SubstanceProfile? profile) => switch (profile) {
  SubstanceProfile.nicotine => Icons.smoking_rooms_rounded,
  SubstanceProfile.thc => Icons.grass_rounded,
  SubstanceProfile.pregabalin => Icons.medication_rounded,
  SubstanceProfile.buprenorphine => Icons.medication_liquid_rounded,
  SubstanceProfile.cocaine => Icons.ac_unit_rounded,
  SubstanceProfile.amphetamines => Icons.bolt_rounded,
  null => Icons.more_horiz_rounded,
};

/// Icon shown on an addiction-type card (the "other substance" path).
IconData addictionTypeIcon(AddictionType type) => switch (type) {
  AddictionType.opioids => Icons.medication_liquid_rounded,
  AddictionType.cannabis => Icons.grass_rounded,
  AddictionType.alcohol => Icons.local_bar_rounded,
  AddictionType.tobacco => Icons.smoking_rooms_rounded,
  AddictionType.pills => Icons.medication_rounded,
  AddictionType.stimulants => Icons.bolt_rounded,
  AddictionType.gambling => Icons.casino_rounded,
  AddictionType.other => Icons.more_horiz_rounded,
};

/// Icon shown on a habit card.
IconData habitIcon(HabitKind kind) => switch (kind) {
  HabitKind.sport => Icons.directions_run_rounded,
  HabitKind.brushTeeth => Icons.mood_rounded,
  HabitKind.water => Icons.water_drop_rounded,
  HabitKind.reading => Icons.menu_book_rounded,
  HabitKind.callFamily => Icons.call_rounded,
  HabitKind.sleep => Icons.bedtime_rounded,
  HabitKind.custom => Icons.edit_rounded,
};

/// One choice in an [OptionGrid]: icon, name and a check when selected.
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = selected ? AppColors.teal700 : AppColors.textBody;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.teal50 : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          side: BorderSide(
            color: selected ? AppColors.teal500 : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.md,
              ),
              child: Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      label,
                      style: text.titleMedium?.copyWith(color: color),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: AppColors.teal600,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two columns of [OptionCard]s (one column on very narrow screens).
class OptionGrid extends StatelessWidget {
  const OptionGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth < 280 ? 1 : 2;
        final width = (box.maxWidth - AppSpace.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}
