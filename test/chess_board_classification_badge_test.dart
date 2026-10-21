import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as ch;
import 'package:chess_teacher/core/widgets/chess_board/chess_board_widget.dart';

void main() {
  const boardSize = 400.0;
  final sq = ChessBoardWidget.snapTo8Px(boardSize) / 8;
  final aligned = ChessBoardWidget.snapTo8Px(boardSize);

  testWidgets('renders a classification badge with the given symbol at the '
      'badge square', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChessBoardWidget(
            fen: ch.Chess.DEFAULT_POSITION,
            size: boardSize,
            badgeSquare: 'd4',
            badgeSymbol: '??',
            badgeColor: Colors.red,
            onMove: (_, _, {promotion}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('??'), findsOneWidget);

    // d4 (white-down): file=3, rank=4 -> col=3, row=4.
    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('moveClassificationBadge')),
    );
    final squareLeft = 3 * sq;
    final squareTop = 4 * sq;
    // Anchored at the square's top-right corner, floating half outside it.
    expect(badgeRect.center.dx, closeTo(squareLeft + sq, badgeRect.width));
    expect(badgeRect.center.dy, closeTo(squareTop, badgeRect.height));
  });

  testWidgets('shows no badge when badgeSquare is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChessBoardWidget(
            fen: ch.Chess.DEFAULT_POSITION,
            size: boardSize,
            onMove: (_, _, {promotion}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('moveClassificationBadge')), findsNothing);
  });

  testWidgets('tucks the badge down when its square is on the board\'s top '
      'row, so it never renders above the board', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChessBoardWidget(
            fen: ch.Chess.DEFAULT_POSITION,
            size: boardSize,
            badgeSquare: 'd8', // row 0 (top) in white-down orientation
            badgeSymbol: '!!',
            badgeColor: Colors.teal,
            onMove: (_, _, {promotion}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('moveClassificationBadge')),
    );
    expect(badgeRect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('tucks the badge left when its square is on the board\'s '
      'rightmost column, so it never renders past the board', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChessBoardWidget(
            fen: ch.Chess.DEFAULT_POSITION,
            size: boardSize,
            badgeSquare: 'h4', // col 7 (rightmost) in white-down orientation
            badgeSymbol: '?',
            badgeColor: Colors.orange,
            onMove: (_, _, {promotion}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('moveClassificationBadge')),
    );
    expect(badgeRect.right, lessThanOrEqualTo(aligned));
  });
}
