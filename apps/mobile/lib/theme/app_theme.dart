import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData light(Locale locale) {
    final arabic = locale.languageCode == 'ar';

    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.teal500,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.teal50,
      onPrimaryContainer: AppColors.teal800,
      secondary: AppColors.sand400,
      onSecondary: AppColors.onSand,
      secondaryContainer: AppColors.sand100,
      onSecondaryContainer: AppColors.onSand,
      error: AppColors.danger,
      onError: AppColors.onPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textStrong,
      onSurfaceVariant: AppColors.textMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.sand200,
    );

    final text = _textTheme(arabic: arabic);

    // Component styles (buttons, fields, chips…) take the locale's family too,
    // otherwise they fall back to the platform font.
    TextStyle font(TextStyle style) => style.copyWith(
      fontFamily: arabic ? AppFonts.arabic : AppFonts.latin,
      fontFamilyFallback: arabic ? AppFonts.arabicFallback : null,
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: const BorderSide(color: AppColors.border),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );
    final buttonText = font(AppType.button.style());

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.lg,
        ),
        labelStyle: font(AppType.label.style()),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        helperStyle: font(
          AppType.caption.style(),
        ).copyWith(color: AppColors.textMuted),
        errorStyle: font(
          AppType.caption.style(),
        ).copyWith(color: AppColors.danger),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.teal500, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.teal500,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.teal300,
          disabledForegroundColor: AppColors.onPrimary,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.teal700,
          side: const BorderSide(color: AppColors.teal500, width: 1.5),
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.teal700,
          minimumSize: const Size(44, 44),
          textStyle: buttonText,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.teal50,
        side: const BorderSide(color: AppColors.border),
        checkmarkColor: AppColors.teal500,
        labelStyle: font(AppType.label.style()),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      ),
      // Bottom nav (DESIGN.md): the active tab sits on a teal.50 pill in
      // teal.700, inactive ones in text.body, so labels stay readable.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.teal50,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.teal700
                : AppColors.textBody,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => font(AppType.caption.style()).copyWith(
            color: states.contains(WidgetState.selected)
                ? AppColors.teal700
                : AppColors.textBody,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.teal500,
        linearTrackColor: AppColors.teal100,
        circularTrackColor: AppColors.teal100,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: font(
          AppType.body.style(),
        ).copyWith(color: AppColors.textStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      ),
    );
  }

  static TextTheme _textTheme({required bool arabic}) {
    final latin = !arabic;
    TextStyle s(TypeSpec spec, {bool heading = false}) =>
        spec.style(latinHeading: latin && heading);

    final raw = TextTheme(
      displayLarge: s(AppType.display, heading: true),
      headlineLarge: s(AppType.h1, heading: true),
      headlineMedium: s(AppType.h2, heading: true),
      titleLarge: s(AppType.h3, heading: true),
      bodyLarge: s(AppType.bodyLg),
      bodyMedium: s(AppType.body),
      bodySmall: s(AppType.caption).copyWith(color: AppColors.textMuted),
      labelMedium: s(AppType.label),
      labelLarge: s(AppType.button),
    );

    return raw.apply(
      fontFamily: arabic ? AppFonts.arabic : AppFonts.latin,
      fontFamilyFallback: arabic ? AppFonts.arabicFallback : null,
      bodyColor: AppColors.textBody,
      displayColor: AppColors.textStrong,
    );
  }
}
