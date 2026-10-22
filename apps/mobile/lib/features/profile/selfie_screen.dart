import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'camera_frames.dart';
import 'camera_widgets.dart';
import 'scan_logic.dart';

/// The largest selfie the server accepts.
const maxSelfieBytes = 2 * 1024 * 1024;

/// Front camera with a face oval. Frames are checked live (one face,
/// centred, close enough) and the shutter only works when the face is well
/// placed. This is a framing check, not a liveness check (PRD 4.2). The
/// photo is shown before it is used; its temporary file is deleted at once.
class SelfieScreen extends StatefulWidget {
  const SelfieScreen({super.key});

  @override
  State<SelfieScreen> createState() => _SelfieScreenState();
}

class _SelfieScreenState extends State<SelfieScreen>
    with WidgetsBindingObserver {
  final _faces = FaceDetector(options: FaceDetectorOptions(minFaceSize: 0.15));
  CameraController? _camera;
  FaceFit _fit = FaceFit.none;
  Uint8List? _shot;
  bool _busy = false;
  bool _taking = false;
  bool _denied = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    unawaited(_faces.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_stop());
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        _shot == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', null);
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final camera = CameraController(
        front.isNotEmpty ? front.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: mlKitFormatGroup,
      );
      await camera.initialize();
      if (!mounted) return camera.dispose();
      await camera.startImageStream((frame) => _onFrame(camera, frame));
      setState(() {
        _camera = camera;
        _fit = FaceFit.none;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      if (isAccessDenied(e)) {
        setState(() => _denied = true);
      } else {
        Navigator.of(context).pop();
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
    if (_busy || _taking || now.difference(_lastFrame).inMilliseconds < 250) {
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
      final faces = await _faces.processImage(image);
      final fit = faceFit([
        for (final f in faces) f.boundingBox,
      ], uprightSize(image));
      if (mounted && fit != _fit) setState(() => _fit = fit);
    } on Exception {
      // Skip this frame.
    } finally {
      _busy = false;
    }
  }

  Future<void> _take() async {
    final camera = _camera;
    if (camera == null || _fit != FaceFit.good || _taking) return;
    setState(() => _taking = true);
    XFile? file;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      await _stop();
      if (!mounted) return;
      setState(() => _shot = bytes.length <= maxSelfieBytes ? bytes : null);
      if (_shot == null) unawaited(_start());
    } on CameraException {
      if (mounted) unawaited(_restartStream());
    } finally {
      if (file != null) {
        try {
          await File(file.path).delete();
        } on FileSystemException {
          // Already gone.
        }
      }
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<void> _restartStream() async {
    final camera = _camera;
    if (camera == null || camera.value.isStreamingImages) return;
    await camera.startImageStream((frame) => _onFrame(camera, frame));
  }

  void _retake() {
    setState(() => _shot = null);
    unawaited(_start());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shot = _shot;
    final camera = _camera;
    final good = _fit == FaceFit.good;
    final status = shot != null
        ? l10n.selfieCheck
        : switch (_fit) {
            FaceFit.none => l10n.selfieNoFace,
            FaceFit.many => l10n.selfieOneFace,
            FaceFit.tooSmall => l10n.selfieCloser,
            FaceFit.offCenter => l10n.selfieCenter,
            FaceFit.good => l10n.selfieReady,
          };

    return CameraScaffold(
      title: l10n.selfieCamTitle,
      denied: _denied,
      preview: shot != null
          ? Image.memory(shot, fit: BoxFit.cover, gaplessPlayback: true)
          : camera == null
          ? null
          : CameraPreviewCover(controller: camera),
      overlay: FaceOval(good: shot != null || good),
      status: status,
      statusColor: shot == null && good ? AppColors.success : null,
      hint: l10n.selfieCamPrivacy,
      actions: shot != null
          ? [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: AppColors.onPrimary,
                  side: const BorderSide(color: AppColors.onPrimary),
                ),
                onPressed: _retake,
                child: Text(l10n.profileSelfieRetake),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: () => Navigator.of(context).pop(shot),
                child: Text(l10n.selfieUse),
              ),
            ]
          : [
              Semantics(
                button: true,
                enabled: good,
                label: l10n.selfieTake,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: good ? _take : null,
                  child: AnimatedContainer(
                    duration: AppMotion.of(context, AppMotion.fast),
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.onPrimary, width: 4),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: good
                            ? AppColors.onPrimary
                            : AppColors.onPrimary.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
      onRetry: () {
        setState(() => _denied = false);
        unawaited(_start());
      },
    );
  }
}
