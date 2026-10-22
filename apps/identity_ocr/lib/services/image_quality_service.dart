import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageQualityReport {
  const ImageQualityReport({
    required this.width,
    required this.height,
    required this.averageBrightness,
    required this.highlightRatio,
    required this.laplacianVariance,
    required this.warnings,
  });

  final int width;
  final int height;
  final double averageBrightness;
  final double highlightRatio;
  final double laplacianVariance;
  final List<String> warnings;
}

class ImageQualityService {
  const ImageQualityService();

  Future<ImageQualityReport> inspect(File file) async {
    final bytes = await file.readAsBytes();
    final stats = await compute(_inspectBytes, bytes);
    return ImageQualityReport(
      width: stats[0] as int,
      height: stats[1] as int,
      averageBrightness: stats[2] as double,
      highlightRatio: stats[3] as double,
      laplacianVariance: stats[4] as double,
      warnings: (stats[5] as List<Object?>).cast<String>(),
    );
  }
}

/// Heuristics only. Thresholds have not been calibrated against real
/// Algerian identity documents and must never be treated as pass/fail proof.
List<Object?> _inspectBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format.');
  }
  final oriented = img.bakeOrientation(decoded);
  final sampleWidth = oriented.width > 320 ? 320 : oriented.width;
  final sample = img.copyResize(oriented, width: sampleWidth);
  final warnings = <String>[];
  if (oriented.width < 500 || oriented.height < 350) {
    warnings.add(
      'Image resolution is low; small document text may be unreadable.',
    );
  }

  var brightnessTotal = 0.0;
  var highlightCount = 0;
  final luminance = List<double>.filled(sample.width * sample.height, 0);
  for (var y = 0; y < sample.height; y++) {
    for (var x = 0; x < sample.width; x++) {
      final pixel = sample.getPixel(x, y);
      final red = pixel.r.toDouble();
      final green = pixel.g.toDouble();
      final blue = pixel.b.toDouble();
      final value = 0.299 * red + 0.587 * green + 0.114 * blue;
      final index = y * sample.width + x;
      luminance[index] = value;
      brightnessTotal += value;
      if (red > 245 && green > 245 && blue > 245) highlightCount++;
    }
  }
  final pixelCount = sample.width * sample.height;
  final brightness = brightnessTotal / pixelCount;
  final highlightRatio = highlightCount / pixelCount;
  if (brightness < 55) warnings.add('Image may be too dark.');
  if (brightness > 225) warnings.add('Image may be overexposed.');
  if (highlightRatio > 0.15) {
    warnings.add('Strong glare may hide printed text.');
  }

  var laplacianTotal = 0.0;
  var laplacianSquaredTotal = 0.0;
  var edgeCount = 0;
  for (var y = 1; y < sample.height - 1; y += 2) {
    for (var x = 1; x < sample.width - 1; x += 2) {
      final center = luminance[y * sample.width + x];
      final laplacian =
          luminance[(y - 1) * sample.width + x] +
          luminance[(y + 1) * sample.width + x] +
          luminance[y * sample.width + x - 1] +
          luminance[y * sample.width + x + 1] -
          4 * center;
      laplacianTotal += laplacian;
      laplacianSquaredTotal += laplacian * laplacian;
      edgeCount++;
    }
  }
  final mean = edgeCount == 0 ? 0 : laplacianTotal / edgeCount;
  final variance = edgeCount == 0
      ? 0
      : (laplacianSquaredTotal / edgeCount) - mean * mean;
  if (variance < 20) warnings.add('Image may be blurry.');

  return [
    oriented.width,
    oriented.height,
    brightness,
    highlightRatio,
    variance,
    warnings,
  ];
}
