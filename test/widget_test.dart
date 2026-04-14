import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_teacher/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: AntiBlunderApp()));

    // Verify the AppBar title exists
    expect(find.text('Anti-Blunder Chess'), findsOneWidget);
  });
}
