import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:chess_teacher/features/game/domain/repositories/chess_engine_repository.dart';
import 'package:chess_teacher/features/game/domain/usecases/attempt_move_usecase.dart';
import 'package:chess_teacher/features/game/presentation/providers/game_provider.dart';
import 'package:chess_teacher/main.dart';

class _FakeEngine extends ChessEngineRepository {
  @override
  Future<void> setBotElo(int elo) async {}

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async => 0;

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async =>
      'e7e5';

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async =>
      null;

  @override
  void dispose() {}
}

Widget _buildApp() {
  final engine = _FakeEngine();
  return ProviderScope(
    overrides: [
      engineRepositoryProvider.overrideWithValue(engine),
      attemptMoveUseCaseProvider.overrideWithValue(AttemptMoveUseCase(engine)),
    ],
    child: const ChessApp(),
  );
}

void main() {
  group('GamePage widget', () {
    testWidgets('renders Martin bot panel', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.text('Martin'), findsOneWidget);
    });

    testWidgets('renders You player panel', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('renders difficulty slider', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      // The sidebar also has a second Slider (mate-safety N), hence the key.
      expect(find.byKey(const ValueKey('difficultySlider')), findsOneWidget);
    });

    testWidgets('renders New Game button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.text('New Game'), findsOneWidget);
    });

    testWidgets('ELO badge shows default Beginner 900 label', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.textContaining('900'), findsWidgets);
    });

    testWidgets('difficulty label shows Trying to Lose at the slider floor', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Drag slider to the leftmost position (0 ELO, the slider's floor).
      // Keyed because the sidebar also has a second Slider (mate-safety N).
      final slider = find.byKey(const ValueKey('difficultySlider'));
      final sliderBox = tester.getRect(slider);
      await tester.tapAt(Offset(sliderBox.left + 2, sliderBox.center.dy));
      await tester.pump();

      // findsWidgets, not findsOneWidget: the side-panel layout shows the
      // elo label in both the bot panel header and the sidebar badge.
      expect(find.textContaining('Trying to Lose'), findsWidgets);
    });

    testWidgets('opens FEN / PGN dialog showing FEN, PGN, and copy buttons', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      expect(find.text('FEN / PGN'), findsOneWidget);
      expect(find.byKey(const ValueKey('fenTextField')), findsOneWidget);
      expect(find.byKey(const ValueKey('pgnTextField')), findsOneWidget);
      expect(find.byKey(const ValueKey('copyFenButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('copyPgnButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('loadFenSubmitButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('loadPgnSubmitButton')), findsOneWidget);
    });

    testWidgets('loads PGN from FEN / PGN dialog', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('pgnTextField')),
        '1. e4 e5 *',
      );
      await tester.tap(find.byKey(const ValueKey('loadPgnSubmitButton')));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ChessApp));
      final container = ProviderScope.containerOf(element);
      final gameState = container.read(gameProvider);
      expect(gameState.sanMoves, ['e4', 'e5']);
    });

    testWidgets('shows captured pieces and scores for both sides', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byKey(const ValueKey('botCapturedBar')), findsOneWidget);
      expect(find.byKey(const ValueKey('playerCapturedBar')), findsOneWidget);
      expect(find.text('0 pts'), findsNWidgets(2));
    });

    testWidgets(
      'renders 8px-aligned board, resize handle, clocks, and selectors',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        expect(find.byKey(const ValueKey('boardResizeHandle')), findsOneWidget);
        expect(find.byKey(const ValueKey('botClockBadge')), findsOneWidget);
        expect(find.byKey(const ValueKey('playerClockBadge')), findsOneWidget);
        expect(find.byKey(const ValueKey('botPanelCrowns')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('moveHistoryFeedbackBar')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('evalScorePill')), findsOneWidget);

        // Select 1 min Bullet time control
        await tester.tap(find.byKey(const ValueKey('timeControl_60')));
        await tester.pump();
        expect(find.text('1:00'), findsNWidgets(2));

        // Switch play side to Black
        await tester.tap(find.byKey(const ValueKey('playSide_black')));
        await tester.pump();
        expect(find.text('Playing as Black'), findsOneWidget);
      },
    );

    testWidgets('renders SAN move chips and jumps to ply when tapped', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final element = tester.element(find.byType(ChessApp));
      final container = ProviderScope.containerOf(element);
      container.read(gameProvider.notifier).loadPgn('1. e4 e5 *');
      await tester.pump();

      expect(find.byKey(const ValueKey('movePly_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('movePly_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('openingNameLabel')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('movePly_1')));
      await tester.pump();
      expect(container.read(gameProvider).currentPly, 1);
    });

    testWidgets(
      'renders eval bar and graph by default, and the toggle hides them',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        // The eval bar always renders; the graph needs 2+ history points
        // (one played move) before it has a line to draw.
        expect(find.byKey(const ValueKey('evalBar')), findsOneWidget);
        expect(find.byKey(const ValueKey('evalGraph')), findsNothing);

        final element = tester.element(find.byType(ChessApp));
        final container = ProviderScope.containerOf(element);
        container.read(gameProvider.notifier).loadPgn('1. e4 e5 *');
        await tester.pump();
        expect(find.byKey(const ValueKey('evalGraph')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('evalBarToggle')));
        await tester.pump();

        expect(find.byKey(const ValueKey('evalBar')), findsNothing);
        expect(find.byKey(const ValueKey('evalGraph')), findsNothing);
      },
    );

    testWidgets('opening selector starts the Italian Game and enforces it', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('openingSelector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Italian Game').last);
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ChessApp));
      final container = ProviderScope.containerOf(element);
      expect(container.read(gameProvider).selectedOpening?.id, 'italian');
      expect(container.read(gameProvider).fen, chess_lib.Chess().fen);
    });
  });
}
