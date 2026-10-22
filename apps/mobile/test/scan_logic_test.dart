import 'dart:ui';

import 'package:benmahdia_mobile/features/profile/id_text_parser.dart';
import 'package:benmahdia_mobile/features/profile/identity_models.dart';
import 'package:benmahdia_mobile/features/profile/scan_logic.dart';
import 'package:flutter_test/flutter_test.dart';

// The ICAO 9303 specimen passport (a fictional person).
const _line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const _line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';
final _today = DateTime(2026, 10, 22);

void main() {
  group('MRZ', () {
    test('check digits follow ICAO 9303', () {
      expect(mrzCheckDigit('L898902C3'), 6);
      expect(mrzCheckDigit('740812'), 2);
      expect(mrzCheckDigit('120415'), 9);
    });

    test('reads number, birth date and name from a passport', () {
      final read = parseMrz('Some header\n$_line1\n$_line2\n', today: _today);
      expect(read, isNotNull);
      expect(read!.idNumber, 'L898902C3');
      expect(read.birthDate, DateTime(1974, 8, 12));
      expect(read.fullName, 'ERIKSSON ANNA MARIA');
    });

    test('copes with OCR spaces, « and letters in digit fields', () {
      final noisy = _line2
          .replaceFirst('7408122', '74O8l22')
          .replaceAll('<<<<<', '«« <');
      final read = parseMrz(
        '$_line1\n${noisy.substring(0, 30)} ${noisy.substring(30)}',
        today: _today,
      );
      expect(read?.birthDate, DateTime(1974, 8, 12));
    });

    test('refuses a line whose check digit does not match', () {
      final wrong = _line2.replaceFirst('L898902C36', 'L898902C35');
      expect(parseMrz('$_line1\n$wrong', today: _today), isNull);
    });

    test('a birth year in the future goes back a century', () {
      // 25 → 2025, 30 → 1930 when today is 2026.
      String line(String birth) {
        final b = birth + mrzCheckDigit(birth).toString();
        return 'L898902C36UTO${b}F1204159ZE184226B<<<<<10';
      }

      expect(
        parseMrz(line('250101'), today: _today)?.birthDate,
        DateTime(2025),
      );
      expect(
        parseMrz(line('300101'), today: _today)?.birthDate,
        DateTime(1930),
      );
    });
  });

  group('live frames', () {
    test('a national ID needs the 18-digit number and a birth date', () {
      expect(
        readFrame(
          '123456789012345678 1990-05-17',
          IdDocType.nationalId,
          today: _today,
        )?.idNumber,
        '123456789012345678',
      );
      expect(
        readFrame('1234567890 1990-05-17', IdDocType.nationalId, today: _today),
        isNull,
      );
      expect(
        readFrame('123456789012345678', IdDocType.nationalId, today: _today),
        isNull,
      );
    });

    test('a passport frame needs valid machine-readable lines', () {
      expect(
        readFrame('$_line1\n$_line2', IdDocType.passport, today: _today),
        isNotNull,
      );
      expect(
        readFrame(
          '123456789012345678 1990-05-17',
          IdDocType.passport,
          today: _today,
        ),
        isNull,
      );
    });

    test('a read is accepted only when two frames agree', () {
      final a = ScannedId(idNumber: 'A1', birthDate: DateTime(1990));
      final b = ScannedId(idNumber: 'B2', birthDate: DateTime(1990));
      final s = ScanStabilizer();
      expect(s.add(a), isNull);
      expect(s.add(null), isNull);
      expect(s.add(b), isNull);
      expect(s.add(b), b);
    });
  });

  group('Algerian documents only', () {
    test('the issuing country comes from the first line', () {
      final utopia = parseMrz('$_line1\n$_line2', today: _today)!;
      expect(utopia.issuer, 'UTO');
      expect(isAcceptedPassport(utopia), isFalse);

      final dz = parseMrz(
        '${_line1.replaceFirst('UTO', 'DZA')}\n${_line2.replaceFirst('UTO', 'DZA')}',
        today: _today,
      )!;
      expect(dz.issuer, 'DZA');
      expect(isAcceptedPassport(dz), isTrue);
    });
  });

  group('face framing', () {
    const image = Size(720, 1280);
    test('no face, two faces, too small, off centre, good', () {
      expect(faceFit([], image), FaceFit.none);
      final good = Rect.fromCenter(
        center: const Offset(360, 640),
        width: 320,
        height: 400,
      );
      expect(faceFit([good, good], image), FaceFit.many);
      expect(
        faceFit([
          Rect.fromCenter(
            center: const Offset(360, 640),
            width: 120,
            height: 150,
          ),
        ], image),
        FaceFit.tooSmall,
      );
      expect(
        faceFit([good.shift(const Offset(250, 0))], image),
        FaceFit.offCenter,
      );
      expect(faceFit([good], image), FaceFit.good);
    });
  });
}
