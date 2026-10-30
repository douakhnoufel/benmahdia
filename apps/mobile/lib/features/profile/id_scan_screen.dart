import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'camera_frames.dart';
import 'camera_widgets.dart';
import 'id_text_parser.dart';
import 'identity_models.dart';
import 'scan_logic.dart';

/// What the scanner hands back.
sealed class IdScanResult {
  const IdScanResult();
}

final class IdScanRead extends IdScanResult {
  const IdScanRead(this.id);

  final ScannedId id;
}

final class IdScanCameraUnavailable extends IdScanResult {
  const IdScanCameraUnavailable();
}

/// Full-screen back camera with a frame shaped like the document. Frames are
/// read live, in memory, by on-device text recognition; when the same
/// details come back twice in a row, the screen closes with them. No picture
/// is ever written to the phone.
class IdScanScreen extends StatefulWidget {
  const IdScanScreen({super.key, required this.type});

  final IdDocType type;

  @override
  State<IdScanScreen> createState() => _IdScanScreenState();
}

class _IdScanScreenState extends State<IdScanScreen>
    with WidgetsBindingObserver {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _stabilizer = ScanStabilizer();
  CameraController? _camera;
  bool _busy = false;
  bool _done = false;
  bool _denied = false;
  bool _torch = false;
  bool _seenText = false;
  bool _foreign = false;
  bool _slow = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slowTimer?.cancel();
    unawaited(_stop());
    unawaited(_recognizer.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_stop());
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (cameras.isEmpty) throw CameraException('NoCamera', null);
      final camera = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: mlKitFormatGroup,
      );
      await camera.initialize();
      if (!mounted) { unawaited(camera.dispose()); return; }
      await camera.startImageStream((frame) => _onFrame(camera, frame));
      setState(() => _camera = camera);
    } on CameraException catch (e) {
      if (!mounted) return;
      if (isAccessDenied(e)) {
        setState(() => _denied = true);
      } else {
        Navigator.of(context).pop(const IdScanCameraUnavailable());
      }
    }
  }

  Future<void> _stop() async {
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    if (camera.value.isStreamingImages) await camera.stopImageStream();
    await camera.dispose();
  }

  Future<void> _onFrame(CameraController camera, CameraImage frame) async {
    final now = DateTime.now();
    if (_busy || _done || now.difference(_lastFrame).inMilliseconds < 300) {
      return;
    }
    _busy = true;
    _lastFrame = now;
    try {
      final image = inputImageOf(
        frame,
        camera.description,
        camera.value.deviceOrientation,
      );
      if (image == null) return;
      final text = (await _recognizer.processImage(image)).text;
      if (!mounted || _done) return;
      if (text.trim().length > 20 && !_seenText) {
        setState(() => _seenText = true);
      }
      var frameRead = readFrame(text, widget.type, today: DateTime.now());
      if (frameRead != null &&
          widget.type == IdDocType.passport &&
          !isAcceptedPassport(frameRead)) {
        frameRead = null;
        if (!_foreign) setState(() => _foreign = true);
      }
      final read = _stabilizer.add(frameRead);
      if (read != null) {
        _done = true;
        await _stop();
        if (mounted) Navigator.of(context).pop(IdScanRead(read));
      }
    } on Exception {
      // A frame that can't be read is skipped; the next one is tried.
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    final on = !_torch;
    try {
      await camera.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      setState(() => _torch = on);
    } on CameraException {
      // No torch on this phone.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final passport = widget.type == IdDocType.passport;
    final camera = _camera;
    final status = _foreign
        ? l10n.scanNotAlgerian
        : _seenText
        ? l10n.scanHold
        : passport
        ? l10n.scanPlacePassport
        : l10n.scanPlaceCard;

    return CameraScaffold(
      title: passport ? l10n.profileDocPassport : l10n.profileDocNationalId,
      denied: _denied,
      preview: camera == null ? null : CameraPreviewCover(controller: camera),
      overlay: DocumentFrame(
        // ID-1 card 85.6 × 54 mm; passport data page 125 × 88 mm.
        aspectRatio: passport ? 125 / 88 : 85.6 / 54,
        scanning: !_done,
      ),
      status: status,
      hint: _slow ? l10n.scanSlow : l10n.scanPrivacy,
      actions: [
        if (camera != null)
          IconButton.filledTonal(
            tooltip: _torch ? l10n.scanTorchOff : l10n.scanTorchOn,
            onPressed: _toggleTorch,
            icon: Icon(
              _torch
                  ? Icons.flashlight_off_rounded
                  : Icons.flashlight_on_rounded,
            ),
          ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.scanTypeInstead),
        ),
      ],
      onRetry: () {
        setState(() => _denied = false);
        unawaited(_start());
      },
    );
  }
}
