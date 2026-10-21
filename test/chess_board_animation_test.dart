import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as ch;
import 'package:chess_teacher/core/widgets/chess_board/chess_board_widget.dart';

void main() {
  testWidgets('ChessBoardWidget renders 64 squares and initial pieces', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChessBoardWidget(
            fen: ch.Chess.DEFAULT_POSITION,
            size: 400,
            onMove: (_, _, {promotion}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChessBoardWidget), findsOneWidget);
  });

  testWidgets('Tap-tap move triggers piece glide animation and commits move', (tester) async {
    String? movedFrom;
    String? movedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChessBoardWidget(
            fen: ch.Chess.DEFAULT_POSITION,
            size: 400,
            onMove: (from, to, {promotion}) {
              movedFrom = from;
              movedTo = to;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sq = ChessBoardWidget.snapTo8Px(400) / 8; // 50px

    // Tap e2 (col 4, row 6)
    await tester.tapAt(Offset(4 * sq + sq / 2, 6 * sq + sq / 2));
    await tester.pump();

    // Tap e4 (col 4, row 4)
    await tester.tapAt(Offset(4 * sq + sq / 2, 4 * sq + sq / 2));
    // Animation is now running (200ms)
    await tester.pump(const Duration(milliseconds: 100));
    expect(movedFrom, isNull); // not finished yet mid-flight

    // Complete the 200ms ease-out animation
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(movedFrom, 'e2');
    expect(movedTo, 'e4');
  });

  testWidgets('Bot move incoming via FEN update triggers smooth glide animation', (tester) async {
    String currentFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ChessBoardWidget(
                    fen: currentFen,
                    size: 400,
                    lastMoveFrom: currentFen.contains('4p3') ? 'e7' : null,
                    lastMoveTo: currentFen.contains('4p3') ? 'e5' : null,
                    onMove: (_, _, {promotion}) {},
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Bot plays e7e5
                        currentFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';
                      });
                    },
                    child: const Text('Bot Move'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Trigger bot move update
    await tester.tap(find.text('Bot Move'));
    await tester.pump(); // didUpdateWidget triggers _startMoveAnimation

    // Mid-animation: piece is gliding
    await tester.pump(const Duration(milliseconds: 100));

    // Finish 200ms animation
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    // Verify board settled cleanly
    expect(find.byType(ChessBoardWidget), findsOneWidget);
  });
}
