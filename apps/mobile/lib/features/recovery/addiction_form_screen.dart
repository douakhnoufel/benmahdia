import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_format.dart';
import 'option_cards.dart';
import 'recovery_models.dart';

/// What the patient enters for one addiction.
/// A [profile] sets the type; without one ("other substance"), [type] is
/// set and tracking is generic.
typedef AddictionEntry = ({
  AddictionType? type,
  SubstanceProfile? profile,
  String? substance,
  DateTime cleanSince,
});

/// "What are you recovering from?": the substance (one of the clinic's
/// profiles, or another substance and its type), the exact product
/// (optional) and the day of the last use. The clinic sets the small goals
/// (PRD 5.6); the patient does not pick one here. The doctor reviews it
/// afterwards.
class AddictionFormScreen extends StatefulWidget {
  const AddictionFormScreen({
    super.key,
    required this.today,
    required this.profiles,
    required this.onSave,
  });

  final DateTime today;
  final List<ProfileSpec> profiles;

  /// One entry per substance the patient ticked.
  final Future<void> Function(List<AddictionEntry> entries) onSave;

  @override
  State<AddictionFormScreen> createState() => _AddictionFormScreenState();
}

class _AddictionFormScreenState extends State<AddictionFormScreen> {
  final _substance = TextEditingController();
  AddictionType? _type;
  final Set<SubstanceProfile> _profileSet = {};
  bool _other = false;
  late DateTime _since = dayOf(widget.today);
  bool _saving = false;

  @override
  void dispose() {
    _substance.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dayOf(widget.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: _since,
      firstDate: DateTime(today.year - 30),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _since = picked);
  }

  bool get _ready => _profileSet.isNotEmpty || (_other && _type != null);

  /// The exact product only makes sense for a single substance.
  bool get _single => _profileSet.length + (_other ? 1 : 0) == 1;

  Future<void> _save() async {
    setState(() => _saving = true);
    final substance = _substance.text.trim();
    try {
      await widget.onSave([
        for (final p in _profileSet)
          (
            type: null,
            profile: p,
            substance: _single && substance.isNotEmpty ? substance : null,
            cleanSince: _since,
          ),
        if (_other)
          (
            type: _type,
            profile: null,
            substance: _single && substance.isNotEmpty ? substance : null,
            cleanSince: _since,
          ),
      ]);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenHorizontal,
          0,
          AppSpace.screenHorizontal,
          AppSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.addictionFormTitle, style: text.headlineLarge),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(l10n.addictionFormBody, style: text.bodyLarge),
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.addictionGoalsAuto,
              style: text.bodyMedium?.copyWith(color: AppColors.textBody),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(l10n.substanceLabel, style: text.labelMedium),
            const SizedBox(height: AppSpace.sm),
            OptionGrid(
              children: [
                for (final p in widget.profiles)
                  OptionCard(
                    icon: substanceIcon(p.profile),
                    label: p.name.of(lang),
                    selected: _profileSet.contains(p.profile),
                    onTap: () => setState(() {
                      if (!_profileSet.remove(p.profile)) {
                        _profileSet.add(p.profile);
                      }
                    }),
                  ),
                OptionCard(
                  icon: substanceIcon(null),
                  label: l10n.substanceOther,
                  selected: _other,
                  onTap: () => setState(() => _other = !_other),
                ),
              ],
            ),
            if (_other) ...[
              const SizedBox(height: AppSpace.xl),
              Text(l10n.addictionTypeLabel, style: text.labelMedium),
              const SizedBox(height: AppSpace.sm),
              OptionGrid(
                children: [
                  for (final t in AddictionType.values)
                    OptionCard(
                      icon: addictionTypeIcon(t),
                      label: l10n.addictionType(t.name),
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    ),
                ],
              ),
            ],
            if (_profileSet.length + (_other ? 1 : 0) <= 1) ...[
              const SizedBox(height: AppSpace.xl),
              TextField(
                controller: _substance,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.addictionSubstance,
                  hintText: l10n.addictionSubstanceHint,
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            Text(l10n.addictionCleanSince, style: text.labelMedium),
            const SizedBox(height: AppSpace.sm),
            Semantics(
              button: true,
              label: '${l10n.addictionCleanSince} ${l10n.longDate(_since)}',
              excludeSemantics: true,
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(l10n.longDate(_since)),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            FilledButton(
              onPressed: !_ready || _saving ? null : _save,
              child: Text(l10n.addictionSave),
            ),
          ],
        ),
      ),
    );
  }
}
