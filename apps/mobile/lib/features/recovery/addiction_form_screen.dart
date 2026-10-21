import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_format.dart';
import 'recovery_models.dart';

/// What the patient enters for one addiction.
typedef AddictionEntry = ({
  AddictionType type,
  String? substance,
  DateTime cleanSince,
});

/// "What are you recovering from?": the type, the exact substance (optional)
/// and the day of the last use. The doctor reviews it afterwards.
class AddictionFormScreen extends StatefulWidget {
  const AddictionFormScreen({
    super.key,
    required this.today,
    required this.onSave,
  });

  final DateTime today;
  final Future<void> Function(AddictionEntry entry) onSave;

  @override
  State<AddictionFormScreen> createState() => _AddictionFormScreenState();
}

class _AddictionFormScreenState extends State<AddictionFormScreen> {
  final _substance = TextEditingController();
  AddictionType? _type;
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
    if (picked != null) setState(() => _since = picked);
  }

  Future<void> _save(AddictionType type) async {
    setState(() => _saving = true);
    final substance = _substance.text.trim();
    try {
      await widget.onSave((
        type: type,
        substance: substance.isEmpty ? null : substance,
        cleanSince: _since,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final type = _type;

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenHorizontal,
          0,
          AppSpace.screenHorizontal,
          AppSpace.xl,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(l10n.addictionFormTitle, style: text.headlineLarge),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(l10n.addictionFormBody, style: text.bodyLarge),
          const SizedBox(height: AppSpace.xl),
          Text(l10n.addictionTypeLabel, style: text.labelMedium),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final t in AddictionType.values)
                ChoiceChip(
                  label: Text(l10n.addictionType(t.name)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          TextField(
            controller: _substance,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.addictionSubstance,
              hintText: l10n.addictionSubstanceHint,
            ),
          ),
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
            onPressed: type == null || _saving ? null : () => _save(type),
            child: Text(l10n.addictionSave),
          ),
        ],
      ),
    );
  }
}
