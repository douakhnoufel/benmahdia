import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const IdentityOcrApp());
}

class IdentityOcrApp extends StatefulWidget {
  const IdentityOcrApp({super.key});

  @override
  State<IdentityOcrApp> createState() => _IdentityOcrAppState();
}

class _IdentityOcrAppState extends State<IdentityOcrApp> {
  bool _arabic = true;

  @override
  Widget build(BuildContext context) {
    const deepTeal = Color(0xFF0C6B63);
    final scheme = ColorScheme.fromSeed(
      seedColor: deepTeal,
      brightness: Brightness.light,
      surface: const Color(0xFFFCFBF8),
    );
    return MaterialApp(
      title: 'Algerian Identity OCR',
      debugShowCheckedModeBanner: false,
      locale: Locale(_arabic ? 'ar' : 'fr'),
      supportedLocales: const [Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFFCFBF8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFCFBF8),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDCE5E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDCE5E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: deepTeal, width: 1.6),
          ),
        ),
      ),
      home: HomeScreen(
        arabic: _arabic,
        onLanguageChanged: () => setState(() => _arabic = !_arabic),
      ),
    );
  }
}
