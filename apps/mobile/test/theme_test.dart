import 'package:benmahdia_mobile/theme/app_theme.dart';
import 'package:benmahdia_mobile/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('maps teal/sand tokens onto the color scheme', () {
      final theme = AppTheme.light(const Locale('ar'));
      expect(theme.colorScheme.primary, AppColors.teal500);
      expect(theme.colorScheme.onPrimary, AppColors.onPrimary);
      expect(theme.colorScheme.secondary, AppColors.sand400);
      expect(theme.colorScheme.error, AppColors.danger);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });

    test('Arabic uses Cairo, French uses Inter', () {
      final ar = AppTheme.light(const Locale('ar'));
      final fr = AppTheme.light(const Locale('fr'));
      expect(ar.textTheme.bodyMedium?.fontFamily, AppFonts.arabic);
      expect(fr.textTheme.bodyMedium?.fontFamily, AppFonts.latin);
    });

    test('type scale matches DESIGN.md', () {
      final t = AppTheme.light(const Locale('ar')).textTheme;
      expect(t.displayLarge?.fontSize, 34);
      expect(t.displayLarge?.height, closeTo(40 / 34, 1e-6));
      expect(t.bodyMedium?.fontSize, 15);
      expect(t.bodySmall?.fontSize, 13);
      expect(t.labelLarge?.fontWeight, FontWeight.w600);
    });

    test('Latin headings get -0.01em tracking, Arabic stays at 0', () {
      final ar = AppTheme.light(const Locale('ar')).textTheme;
      final fr = AppTheme.light(const Locale('fr')).textTheme;
      expect(ar.headlineLarge?.letterSpacing, 0);
      expect(fr.headlineLarge?.letterSpacing, closeTo(-0.28, 1e-6));
    });

    test('primary button is 52 high with button radius', () {
      final style = AppTheme.light(const Locale('ar')).filledButtonTheme.style!;
      expect(style.minimumSize?.resolve({}), const Size.fromHeight(52));
      final shape = style.shape?.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(AppRadius.button));
    });
  });

  test('tint is the semantic color at 12% alpha', () {
    expect(AppColors.tint(AppColors.danger).a, closeTo(0.12, 1e-3));
  });
}
