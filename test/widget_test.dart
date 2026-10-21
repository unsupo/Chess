import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineRepositoryProvider.overrideWithValue(engine),
          attemptMoveUseCaseProvider.overrideWithValue(
            AttemptMoveUseCase(engine),
          ),
        ],
        child: const ChessApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Martin'), findsOneWidget);
  });
}
