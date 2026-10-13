import 'package:flutter/material.dart';

/// Design tokens from docs/DESIGN.md. Widgets read these (directly or via
/// [AppTheme]); never use inline hex, px, radius or shadow literals.
abstract final class AppColors {
  // Brand — teal
  static const teal50 = Color(0xFFEAF7F5);
  static const teal100 = Color(0xFFCDEAE6);
  static const teal200 = Color(0xFFA6DBD4);
  static const teal300 = Color(0xFF6FC5BB);
  static const teal400 = Color(0xFF39AB9F);
  static const teal500 = Color(0xFF0F9E92);
  static const teal600 = Color(0xFF0C8578);
  static const teal700 = Color(0xFF0A6A60);
  static const teal800 = Color(0xFF084F48);
  static const teal900 = Color(0xFF063A35);

  // Neutral — sand
  static const sand50 = Color(0xFFFBF8F3);
  static const sand100 = Color(0xFFF4EDE1);
  static const sand200 = Color(0xFFEADFCB);
  static const sand300 = Color(0xFFDFCFB2);
  static const sand400 = Color(0xFFCDB68E);
  static const sand500 = Color(0xFFB9995F);

  // Ink & lines
  static const surface = Color(0xFFFFFFFF);
  static const background = sand50;
  static const textStrong = Color(0xFF10302C);
  static const textBody = Color(0xFF3A4B48);
  static const textMuted = Color(0xFF6B7A77);
  static const border = Color(0xFFE5E0D6);
  static const overlay = Color(0x7310302C); // rgba(16,48,44,0.45)

  // Semantic
  static const success = Color(0xFF2E9E6B);
  static const warning = Color(0xFFD98A2B);
  static const danger = Color(0xFFD7524C);
  static const info = teal500;
  static const onPrimary = Color(0xFFFFFFFF);
  static const onSand = Color(0xFF10302C);

  /// Background tint for badges/snackbars: semantic color at ~12% alpha.
  static Color tint(Color semantic) => semantic.withValues(alpha: 0.12);
}

/// 4 px grid.
abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  static const screenHorizontal = 20.0;
  static const cardGap = 12.0;
  static const sectionGap = 24.0;
}

abstract final class AppRadius {
  static const field = 12.0;
  static const button = 14.0;
  static const card = 20.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

/// Soft, low, teal-tinted. No hard or dark drop shadows.
abstract final class AppShadows {
  static const sm = [
    BoxShadow(
      color: Color(0x0A10302C), // 0.04
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];
  static const card = [
    BoxShadow(
      color: Color(0x0F10302C), // 0.06
      offset: Offset(0, 4),
      blurRadius: 16,
    ),
  ];
  static const lg = [
    BoxShadow(
      color: Color(0x1A10302C), // 0.10
      offset: Offset(0, 12),
      blurRadius: 32,
    ),
  ];
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 600);
  static const stagger = Duration(milliseconds: 70);
  static const curve = Curves.easeOutCubic;

  /// Collapses every animation to zero when the OS asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// Font families. Arabic UI uses Cairo (IBM Plex Sans Arabic as fallback);
/// Latin/French uses Inter. Both must be bundled as assets (no runtime fetch).
abstract final class AppFonts {
  static const arabic = 'Cairo';
  static const arabicFallback = ['IBMPlexSansArabic'];
  static const latin = 'Inter';
}

/// Type scale (size / line height / weight). Family and colour are applied by
/// [AppTheme] per locale.
abstract final class AppType {
  static const display = TypeSpec(34, 40, FontWeight.w700);
  static const h1 = TypeSpec(28, 36, FontWeight.w700);
  static const h2 = TypeSpec(22, 30, FontWeight.w600);
  static const h3 = TypeSpec(18, 26, FontWeight.w600);
  static const bodyLg = TypeSpec(17, 26, FontWeight.w400);
  static const body = TypeSpec(15, 24, FontWeight.w400);
  static const label = TypeSpec(14, 20, FontWeight.w500);
  static const caption = TypeSpec(13, 18, FontWeight.w400);
  static const button = TypeSpec(16, 20, FontWeight.w600);
}

class TypeSpec {
  const TypeSpec(this.size, this.lineHeight, this.weight);

  final double size;
  final double lineHeight;
  final FontWeight weight;

  /// [latinHeading] adds the -0.01em tracking used for Latin headings only;
  /// Arabic always keeps 0 letter-spacing.
  TextStyle style({bool latinHeading = false}) => TextStyle(
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: latinHeading ? -0.01 * size : 0,
  );
}
