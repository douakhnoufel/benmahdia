import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// The stream format ML Kit reads on each platform.
ImageFormatGroup get mlKitFormatGroup =>
    Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Turns a live camera frame into an ML Kit image, in memory. Null when the
/// frame's format or rotation can't be read.
InputImage? inputImageOf(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation orientation,
) {
  final sensor = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensor);
  } else if (Platform.isAndroid) {
    final device = _orientations[orientation];
    if (device == null) return null;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
    rotation = InputImageRotationValue.fromRawValue(degrees);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null ||
      (Platform.isAndroid && format != InputImageFormat.nv21) ||
      (Platform.isIOS && format != InputImageFormat.bgra8888) ||
      image.planes.length != 1) {
    return null;
  }
  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

/// The frame's size as the recognizer sees it (upright).
Size uprightSize(InputImage image) {
  final meta = image.metadata!;
  final turned =
      meta.rotation == InputImageRotation.rotation90deg ||
      meta.rotation == InputImageRotation.rotation270deg;
  return turned ? Size(meta.size.height, meta.size.width) : meta.size;
}

/// Whether the camera failed because the patient refused access.
bool isAccessDenied(CameraException e) => e.code.startsWith('CameraAccess');
