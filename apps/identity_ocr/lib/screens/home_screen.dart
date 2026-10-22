import 'package:flutter/material.dart';

import '../app/app_copy.dart';
import '../models/identity_document.dart';
import 'capture_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.arabic,
    required this.onLanguageChanged,
    super.key,
  });

  final bool arabic;
  final VoidCallback onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy(arabic);
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: onLanguageChanged,
            child: Text(copy.text('language')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
          children: [
            _BrandTag(label: copy.text('brand')),
            const SizedBox(height: 18),
            Text(
              copy.text('title'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              copy.text('subtitle'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF52645F),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            _PrivacyNotice(copy: copy),
            const SizedBox(height: 14),
            _EngineNotice(copy: copy),
            const SizedBox(height: 26),
            _DocumentChoice(
              icon: Icons.badge_outlined,
              title: copy.text('nationalId'),
              subtitle: copy.text('nationalIdBody'),
              onTap: () => _openCapture(context, DocumentType.nationalId),
            ),
            const SizedBox(height: 12),
            _DocumentChoice(
              icon: Icons.menu_book_outlined,
              title: copy.text('passport'),
              subtitle: copy.text('passportBody'),
              onTap: () => _openCapture(context, DocumentType.passport),
            ),
            const SizedBox(height: 20),
            Text(
              copy.text('sourceFooter'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: const Color(0xFF73817D)),
            ),
          ],
        ),
      ),
    );
  }

  void _openCapture(BuildContext context, DocumentType type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureScreen(type: type, arabic: arabic),
      ),
    );
  }
}

class _BrandTag extends StatelessWidget {
  const _BrandTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFE5F2EE),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF0C6B63),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4EF),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD7EAE1)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline_rounded, color: Color(0xFF0C6B63)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('privacyTitle'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                copy.text('privacyBody'),
                style: const TextStyle(height: 1.4, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EngineNotice extends StatelessWidget {
  const _EngineNotice({required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4DE),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFF8A5A12)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            copy.text('arabicLimit'),
            style: const TextStyle(height: 1.4, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class _DocumentChoice extends StatelessWidget {
  const _DocumentChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E9E5)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4EF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF0C6B63), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF62716C),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 15),
          ],
        ),
      ),
    ),
  );
}
