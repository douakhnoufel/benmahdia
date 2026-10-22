import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';

/// Shared layout of the in-app cameras: live preview under a dimmed frame,
/// a close button, a status line and actions at the bottom. When camera
/// access was refused, it explains how to allow it instead.
class CameraScaffold extends StatelessWidget {
  const CameraScaffold({
    super.key,
    required this.title,
    required this.denied,
    required this.preview,
    required this.overlay,
    required this.status,
    required this.actions,
    required this.onRetry,
    this.hint,
    this.statusColor,
  });

  final String title;
  final bool denied;
  final Widget? preview;
  final Widget overlay;
  final String status;
  final String? hint;
  final Color? statusColor;
  final List<Widget> actions;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final onDark = text.bodyMedium?.copyWith(color: AppColors.onPrimary);

    return Scaffold(
      backgroundColor: AppColors.teal900,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!denied) ...[?preview, overlay],
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpace.xs,
                    AppSpace.xs,
                    AppSpace.screenHorizontal,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: l10n.cameraClose,
                        color: AppColors.onPrimary,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: text.titleLarge?.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (denied)
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      spacing: AppSpace.lg,
                      children: [
                        const Icon(
                          Icons.no_photography_outlined,
                          size: 48,
                          color: AppColors.onPrimary,
                        ),
                        Text(
                          l10n.cameraDenied,
                          textAlign: TextAlign.center,
                          style: onDark,
                        ),
                        FilledButton(
                          onPressed: onRetry,
                          child: Text(l10n.cameraRetry),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.onPrimary,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.scanTypeInstead),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.screenHorizontal,
                      0,
                      AppSpace.screenHorizontal,
                      AppSpace.lg,
                    ),
                    child: Column(
                      spacing: AppSpace.md,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.lg,
                              vertical: AppSpace.sm,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor ?? AppColors.teal800,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Text(
                              status,
                              textAlign: TextAlign.center,
                              style: onDark?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (hint case final h?)
                          Text(
                            h,
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.teal100,
                            ),
                          ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpace.lg,
                          runSpacing: AppSpace.sm,
                          children: actions,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The camera preview filling the screen (cropped, never stretched).
class CameraPreviewCover extends StatelessWidget {
  const CameraPreviewCover({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // previewSize is in landscape; the screen is portrait.
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Dims everything but a rounded window shaped like the document, with
/// corner marks and a scan line passing over it (still under reduced
/// motion).
class DocumentFrame extends StatefulWidget {
  const DocumentFrame({
    super.key,
    required this.aspectRatio,
    required this.scanning,
  });

  final double aspectRatio;
  final bool scanning;

  @override
  State<DocumentFrame> createState() => _DocumentFrameState();
}

class _DocumentFrameState extends State<DocumentFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _line = AnimationController(
    vsync: this,
    duration: AppMotion.scan,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) || !widget.scanning) {
      _line.stop();
    } else if (!_line.isAnimating) {
      _line.repeat();
    }
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _line,
      builder: (context, _) => CustomPaint(
        painter: _WindowPainter(
          aspectRatio: widget.aspectRatio,
          line: AppMotion.reduced(context) ? null : _line.value,
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter({required this.aspectRatio, required this.line});

  final double aspectRatio;
  final double? line;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - 2 * AppSpace.xl;
    final height = width / aspectRatio;
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: width,
      height: height,
    );
    final rounded = RRect.fromRectAndRadius(
      window,
      const Radius.circular(AppRadius.field),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rounded),
      ),
      Paint()..color = AppColors.overlay,
    );

    final corner = Paint()
      ..color = AppColors.teal500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const arm = 28.0;
    for (final (x, y, sx, sy) in [
      (window.left, window.top, 1.0, 1.0),
      (window.right, window.top, -1.0, 1.0),
      (window.left, window.bottom, 1.0, -1.0),
      (window.right, window.bottom, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(Offset(x, y), Offset(x + arm * sx, y), corner)
        ..drawLine(Offset(x, y), Offset(x, y + arm * sy), corner);
    }

    if (line case final t?) {
      final y = window.top + window.height * t;
      canvas.drawLine(
        Offset(window.left + AppSpace.md, y),
        Offset(window.right - AppSpace.md, y),
        Paint()
          ..color = AppColors.teal300
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.line != line || old.aspectRatio != aspectRatio;
}

/// Dims everything but an oval for the face; its rim turns green when the
/// face is well placed.
class FaceOval extends StatelessWidget {
  const FaceOval({super.key, required this.good});

  final bool good;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _OvalPainter(good: good));
}

class _OvalPainter extends CustomPainter {
  _OvalPainter({required this.good});

  final bool good;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.68;
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.4),
      width: width,
      height: width * 1.3,
    );
    canvas
      ..drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addOval(oval),
        ),
        Paint()..color = AppColors.overlay,
      )
      ..drawOval(
        oval,
        Paint()
          ..color = good ? AppColors.success : AppColors.onPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = good ? 4 : 2,
      );
  }

  @override
  bool shouldRepaint(_OvalPainter old) => old.good != good;
}
