import 'dart:ui';

import 'id_text_parser.dart';
import 'identity_models.dart';

/// The only documents accepted: the Algerian national ID card and the
/// Algerian passport.
const algeria = 'DZA';

/// What a live camera frame of [type] gives, or null when it is not a full,
/// trustworthy read yet: a passport needs valid machine-readable lines, a
/// national ID card its 18-digit number and a birth date. A passport from
/// another country comes back with its [ScannedId.issuer]: see
/// [isAcceptedPassport].
ScannedId? readFrame(String text, IdDocType type, {required DateTime today}) {
  switch (type) {
    case IdDocType.passport:
      return parseMrz(text, today: today);
    case IdDocType.nationalId:
      final read = parseIdText(text, today: today);
      final number = read.idNumber;
      if (number == null || number.length != 18 || read.birthDate == null) {
        return null;
      }
      return read;
  }
}

/// Whether a passport read is an Algerian passport.
bool isAcceptedPassport(ScannedId read) => read.issuer == algeria;

/// Accepts a read only once the same result came from [needed] frames in a
/// row, so one misread frame never fills the form.
class ScanStabilizer {
  ScanStabilizer({this.needed = 2});

  final int needed;
  ScannedId? _last;
  int _count = 0;

  ScannedId? add(ScannedId? read) {
    if (read == null) return null;
    if (read == _last) {
      _count++;
    } else {
      _last = read;
      _count = 1;
    }
    return _count >= needed ? read : null;
  }
}

/// How the face sits in the selfie frame. This only checks framing: it says
/// nothing about whether the person is live.
enum FaceFit { none, many, tooSmall, offCenter, good }

/// [faces] are face boxes in an upright image of [image] size.
FaceFit faceFit(List<Rect> faces, Size image) {
  if (faces.isEmpty) return FaceFit.none;
  if (faces.length > 1) return FaceFit.many;
  final face = faces.single;
  if (face.width < image.width * 0.3) return FaceFit.tooSmall;
  final dx = (face.center.dx - image.width / 2).abs();
  final dy = (face.center.dy - image.height / 2).abs();
  if (dx > image.width * 0.18 || dy > image.height * 0.22) {
    return FaceFit.offCenter;
  }
  return FaceFit.good;
}
