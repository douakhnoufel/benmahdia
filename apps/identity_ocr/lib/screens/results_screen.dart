import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_copy.dart';
import '../models/identity_document.dart';
import '../services/date_parser.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    required this.document,
    required this.arabic,
    super.key,
  });

  final IdentityDocument document;
  final bool arabic;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final Map<IdentityField, TextEditingController> _controllers;
  bool _reviewed = false;
  bool _showRawText = false;

  AppCopy get _copy => AppCopy(widget.arabic);

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    _controllers = {
      IdentityField.surname: TextEditingController(
        text: document.surname ?? '',
      ),
      IdentityField.givenNames: TextEditingController(
        text: document.givenNames ?? '',
      ),
      IdentityField.documentNumber: TextEditingController(
        text: document.documentNumber ?? '',
      ),
      IdentityField.nationality: TextEditingController(
        text: document.nationality ?? '',
      ),
      IdentityField.issuingState: TextEditingController(
        text: document.issuingState ?? '',
      ),
      IdentityField.sex: TextEditingController(text: document.sex ?? ''),
      IdentityField.dateOfBirth: TextEditingController(
        text: _dateInput(IdentityField.dateOfBirth, document.dateOfBirth),
      ),
      IdentityField.issueDate: TextEditingController(
        text: _dateInput(IdentityField.issueDate, document.issueDate),
      ),
      IdentityField.expiryDate: TextEditingController(
        text: _dateInput(IdentityField.expiryDate, document.expiryDate),
      ),
    };
  }

  String _dateInput(IdentityField field, DateTime? date) {
    if (date != null) return dateToIso(date);
    return widget.document.fieldReview[field]?.originalRecognizedValue ?? '';
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _label(IdentityField field) => switch (field) {
    IdentityField.surname => _copy.text('surname'),
    IdentityField.givenNames => _copy.text('givenNames'),
    IdentityField.documentNumber => _copy.text('documentNumber'),
    IdentityField.nationality => _copy.text('nationality'),
    IdentityField.issuingState => _copy.text('issuingState'),
    IdentityField.sex => _copy.text('sex'),
    IdentityField.dateOfBirth => _copy.text('dateOfBirth'),
    IdentityField.issueDate => _copy.text('issueDate'),
    IdentityField.expiryDate => _copy.text('expiryDate'),
  };

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final fields = <IdentityField>[
      IdentityField.surname,
      IdentityField.givenNames,
      IdentityField.documentNumber,
      IdentityField.nationality,
      if (widget.document.issuingState != null) IdentityField.issuingState,
      IdentityField.sex,
      IdentityField.dateOfBirth,
      IdentityField.issueDate,
      IdentityField.expiryDate,
    ];
    final hasFields = _controllers.values.any(
      (controller) => controller.text.trim().isNotEmpty,
    );
    return Scaffold(
      appBar: AppBar(title: Text(copy.text('resultsTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(
              copy.text('resultsSubtitle'),
              style: const TextStyle(color: Color(0xFF596862), height: 1.45),
            ),
            const SizedBox(height: 14),
            _InfoBanner(text: copy.text('authenticity'), warning: true),
            if (widget.document.validationErrors.isNotEmpty) ...[
              const SizedBox(height: 14),
              _MessageList(
                title: copy.text('validation'),
                messages: widget.document.validationErrors,
                error: true,
              ),
            ],
            if (widget.document.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _MessageList(
                title: copy.text('warnings'),
                messages: widget.document.warnings,
                error: false,
              ),
            ],
            const SizedBox(height: 18),
            for (final field in fields) ...[
              _EditableField(
                label: _label(field),
                hint: _isDate(field) ? copy.text('dateHint') : null,
                controller: _controllers[field]!,
                review: widget.document.fieldReview[field],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.document.mrz != null) ...[
              const SizedBox(height: 3),
              _CopyExpandable(
                label: 'MRZ · ICAO 9303',
                text: widget.document.mrz!,
              ),
            ],
            if (widget.document.rawOcrText.isNotEmpty) ...[
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _showRawText,
                onChanged: (value) =>
                    setState(() => _showRawText = value ?? false),
                title: Text(copy.text('rawText')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_showRawText)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E6E2)),
                  ),
                  child: SelectableText(widget.document.rawOcrText),
                ),
            ],
            if (!hasFields) ...[
              const SizedBox(height: 8),
              _InfoBanner(text: copy.text('manual'), warning: false),
            ],
            const SizedBox(height: 18),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _reviewed,
              onChanged: (value) => setState(() => _reviewed = value ?? false),
              title: Text(copy.text('reviewCheck')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _reviewed ? _confirmAndCopy : null,
              icon: const Icon(Icons.content_copy_rounded),
              label: Text(copy.text('copy')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(copy.text('newScan')),
            ),
          ],
        ),
      ),
    );
  }

  bool _isDate(IdentityField field) =>
      field == IdentityField.dateOfBirth ||
      field == IdentityField.issueDate ||
      field == IdentityField.expiryDate;

  Future<void> _confirmAndCopy() async {
    final lines = <String>[];
    for (final entry in _controllers.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      var value = raw;
      if (_isDate(entry.key)) {
        final parsed = parseDocumentDate(raw, dayFirst: true);
        if (parsed.value != null) value = dateToIso(parsed.value);
      }
      lines.add('${_label(entry.key)}: $value');
    }
    if (lines.isEmpty) {
      _showMessage(_copy.text('manual'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) _showMessage(_copy.text('copied'));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.controller,
    required this.review,
    this.hint,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final FieldReview? review;

  @override
  Widget build(BuildContext context) {
    final uncertain = review?.level == ReviewLevel.uncertain;
    final unknown =
        review?.level == ReviewLevel.unknown ||
        (review == null && controller.text.isEmpty);
    final message = uncertain
        ? review?.reason ?? 'Review this recognized value.'
        : unknown
        ? 'Unknown — enter a value if available.'
        : 'Review before confirming.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              uncertain || unknown
                  ? Icons.error_outline_rounded
                  : Icons.fact_check_outlined,
              size: 15,
              color: uncertain || unknown
                  ? const Color(0xFF9A5B10)
                  : const Color(0xFF0C6B63),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  color: uncertain || unknown
                      ? const Color(0xFF87520F)
                      : const Color(0xFF53645E),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text, required this.warning});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF4DE) : const Color(0xFFEAF4EF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
          color: warning ? const Color(0xFF8A5A12) : const Color(0xFF0C6B63),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    ),
  );
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.title,
    required this.messages,
    required this.error,
  });

  final String title;
  final List<String> messages;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFECE8) : const Color(0xFFFFF4DE),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $message', style: const TextStyle(height: 1.35)),
          ),
      ],
    ),
  );
}

class _CopyExpandable extends StatelessWidget {
  const _CopyExpandable({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(label),
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(text),
      ),
    ],
  );
}
