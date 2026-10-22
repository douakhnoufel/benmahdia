import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../app/app_copy.dart';
import '../models/identity_document.dart';
import '../services/document_detection_service.dart';
import '../services/image_quality_service.dart';
import '../services/ocr_service.dart';
import 'results_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({required this.type, required this.arabic, super.key});

  final DocumentType type;
  final bool arabic;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  final _cropper = ImageCropper();
  final _qualityService = const ImageQualityService();
  final _ocrService = OcrService();
  final _parsers = const DocumentDetectionService();
  final _ownedPaths = <String>{};
  final _random = Random.secure();

  XFile? _selected;
  String? _previewPath;
  bool _busy = false;
  bool _checkingQuality = false;
  List<String> _qualityWarnings = const [];

  AppCopy get _copy => AppCopy(widget.arabic);
  String get _documentTitle => _copy.text(
    widget.type == DocumentType.passport ? 'passport' : 'nationalId',
  );

  @override
  void dispose() {
    unawaited(_cleanupOwned());
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    await _cleanupOwned();
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 92,
      );
      if (picked == null) return;
      if (source == ImageSource.camera ||
          await _isPlatformTemporary(picked.path)) {
        _ownedPaths.add(picked.path);
      }
      if (!mounted) return;
      setState(() {
        _selected = picked;
        _previewPath = picked.path;
        _qualityWarnings = const [];
        _checkingQuality = true;
      });
      await _inspectQuality(File(picked.path));
    } on PlatformException {
      _showMessage(_copy.text('imageError'));
    } on Exception {
      _showMessage(_copy.text('imageError'));
    }
  }

  Future<void> _inspectQuality(File file) async {
    try {
      final report = await _qualityService.inspect(file);
      if (mounted) setState(() => _qualityWarnings = report.warnings);
    } on Exception {
      if (mounted) {
        setState(() => _qualityWarnings = [_copy.text('unsupported')]);
      }
    } finally {
      if (mounted) setState(() => _checkingQuality = false);
    }
  }

  Future<void> _crop() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    try {
      final cropped = await _cropper.cropImage(
        sourcePath: _previewPath ?? selected.path,
        maxWidth: 2500,
        maxHeight: 2500,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: _copy.text('crop'),
            toolbarColor: const Color(0xFF0C6B63),
            toolbarWidgetColor: Colors.white,
          ),
          IOSUiSettings(title: _copy.text('crop')),
        ],
      );
      if (cropped == null || !mounted) return;
      _ownedPaths.add(cropped.path);
      setState(() {
        _selected = XFile(cropped.path);
        _previewPath = cropped.path;
        _checkingQuality = true;
      });
      await _inspectQuality(File(cropped.path));
    } on PlatformException {
      _showMessage(_copy.text('cropError'));
    } on Exception {
      _showMessage(_copy.text('cropError'));
    }
  }

  Future<void> _read() async {
    final selected = _selected;
    final path = _previewPath;
    if (selected == null || path == null || _busy) return;
    setState(() => _busy = true);
    IdentityDocument result;
    File? workingCopy;
    try {
      final source = File(path);
      workingCopy = await _makeWorkingCopy(source);
      _ownedPaths.add(workingCopy.path);
      final rawText = await _ocrService.recognizeFile(workingCopy.path);
      final parsed = _parsers.parse(widget.type, rawText);
      final warnings = [...parsed.warnings, ..._qualityWarnings];
      if (rawText.trim().isEmpty) warnings.add(_copy.text('emptyOcr'));
      result = IdentityDocument(
        documentType: parsed.documentType,
        surname: parsed.surname,
        givenNames: parsed.givenNames,
        documentNumber: parsed.documentNumber,
        nationality: parsed.nationality,
        issuingState: parsed.issuingState,
        sex: parsed.sex,
        dateOfBirth: parsed.dateOfBirth,
        issueDate: parsed.issueDate,
        expiryDate: parsed.expiryDate,
        mrz: parsed.mrz,
        rawOcrText: rawText,
        fieldReview: parsed.fieldReview,
        validationErrors: parsed.validationErrors,
        warnings: warnings,
      );
    } on Exception {
      result = IdentityDocument(
        documentType: widget.type,
        rawOcrText: '',
        validationErrors: const [],
        warnings: [_copy.text('processingError'), ..._qualityWarnings],
      );
    } finally {
      if (workingCopy != null) {
        await _deleteIfExists(workingCopy.path);
        _ownedPaths.remove(workingCopy.path);
      }
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    await _cleanupOwned();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResultsScreen(document: result, arabic: widget.arabic),
      ),
    );
  }

  Future<File> _makeWorkingCopy(File source) async {
    final directory = await getTemporaryDirectory();
    final extension = _safeExtension(source.path);
    final name =
        'identity_ocr_${_random.nextInt(0x7fffffff).toRadixString(16)}.$extension';
    return source.copy('${directory.path}/$name');
  }

  Future<bool> _isPlatformTemporary(String path) async {
    final candidate = File(path).absolute.path;
    final cache = (await getTemporaryDirectory()).absolute.path;
    final systemTemp = Directory.systemTemp.absolute.path;
    return _isInside(candidate, cache) || _isInside(candidate, systemTemp);
  }

  bool _isInside(String path, String parent) {
    final separator = Platform.pathSeparator;
    final normalizedParent = parent.endsWith(separator)
        ? parent
        : parent + separator;
    return path == parent || path.startsWith(normalizedParent);
  }

  String _safeExtension(String path) {
    final index = path.lastIndexOf('.');
    if (index < 0) return 'img';
    final extension = path.substring(index + 1).toLowerCase();
    return const {
          'jpg',
          'jpeg',
          'png',
          'heic',
          'webp',
          'bmp',
        }.contains(extension)
        ? extension
        : 'img';
  }

  Future<void> _cleanupOwned() async {
    final paths = _ownedPaths.toList();
    _ownedPaths.clear();
    for (final path in paths) {
      await _deleteIfExists(path);
    }
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cache cleanup is best effort; it must not interrupt the scan flow.
    }
  }

  void _retake() {
    unawaited(_cleanupOwned());
    setState(() {
      _selected = null;
      _previewPath = null;
      _qualityWarnings = const [];
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final hasImage = _previewPath != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_documentTitle),
        leading: IconButton(
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              hasImage ? copy.text('previewTitle') : copy.text('captureTitle'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              hasImage
                  ? copy.text('previewHint')
                  : copy.text('captureSubtitle'),
              style: const TextStyle(color: Color(0xFF5C6A65), height: 1.45),
            ),
            const SizedBox(height: 18),
            if (hasImage) ...[
              _ImagePreview(path: _previewPath!),
              const SizedBox(height: 14),
              _QualityCard(
                copy: copy,
                warnings: _qualityWarnings,
                checking: _checkingQuality,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _crop,
                icon: const Icon(Icons.crop_rotate_rounded),
                label: Text(copy.text('crop')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _retake,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(copy.text('retake')),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || _checkingQuality ? null : _read,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(_busy ? copy.text('reading') : copy.text('read')),
              ),
            ] else ...[
              _DocumentFrame(type: widget.type),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(copy.text('camera')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(copy.text('gallery')),
              ),
            ],
            const SizedBox(height: 16),
            _PrivacyFooter(copy: copy),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Container(
    height: 270,
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF18211F),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white70,
          size: 42,
        ),
      ),
    ),
  );
}

class _DocumentFrame extends StatelessWidget {
  const _DocumentFrame({required this.type});

  final DocumentType type;

  @override
  Widget build(BuildContext context) {
    final passport = type == DocumentType.passport;
    return Container(
      height: 245,
      decoration: BoxDecoration(
        color: const Color(0xFF17211E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.78,
          height: passport ? 188 : 122,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF70C4AF), width: 2),
            color: Colors.white.withValues(alpha: 0.04),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                passport ? Icons.menu_book_outlined : Icons.badge_outlined,
                color: const Color(0xFFB7E3D6),
                size: 32,
              ),
              if (passport) ...[
                const SizedBox(height: 25),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(color: Color(0xFFB7E3D6), thickness: 2),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(color: Color(0xFFB7E3D6), thickness: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.copy,
    required this.warnings,
    required this.checking,
  });

  final AppCopy copy;
  final List<String> warnings;
  final bool checking;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F5F2),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.text('qualityTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(copy.text('qualityIntro'), style: const TextStyle(fontSize: 12)),
        if (checking) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ] else if (warnings.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            copy.text('qualityGood'),
            style: const TextStyle(color: Color(0xFF0C6B63)),
          ),
        ] else ...[
          const SizedBox(height: 8),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFF9A5B10),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(warning, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter({required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.lock_outline, size: 18, color: Color(0xFF0C6B63)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          copy.text('privacyBody'),
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF596862),
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}
