import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/game/presentation/pages/game_page.dart';

void main() {
  runApp(const ProviderScope(child: ChessApp()));
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Trainer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A2B1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7BBF44),
          surface: Color(0xFF243324),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF7BBF44),
          thumbColor: Color(0xFF7BBF44),
          inactiveTrackColor: Color(0xFF2E4A2E),
          overlayColor: Color(0x287BBF44),
          trackHeight: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7BBF44),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      home: const GamePage(),
    );
  }
}
