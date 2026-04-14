import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/game/presentation/pages/game_page.dart';

void main() {
  runApp(const ProviderScope(child: AntiBlunderApp()));
}

class AntiBlunderApp extends StatelessWidget {
  const AntiBlunderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Blunder Chess',
      theme: ThemeData.dark(),
      home: const GamePage(),
    );
  }
}