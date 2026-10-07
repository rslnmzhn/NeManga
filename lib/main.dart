import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Настройка прозрачности системных статус-баров для современного вида
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F1115),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NeMangaApp());
}

class NeMangaApp extends StatelessWidget {
  const NeMangaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeManga',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF), // Фиолетово-индиго акцент
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF16191E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F1115),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF16191E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
