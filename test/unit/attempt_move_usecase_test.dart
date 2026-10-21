import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/move_result.dart';
import 'package:chess_teacher/features/game/domain/repositories/chess_engine_repository.dart';
import 'package:chess_teacher/features/game/domain/usecases/attempt_move_usecase.dart';

class _FakeEngine extends ChessEngineRepository {
  final int currentEval;
  final int newEval;

  _FakeEngine({required this.currentEval, required this.newEval});

  int _callCount = 0;

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async {
    return _callCount++ == 0 ? currentEval : newEval;
  }

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async =>
      'e2e4';

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async =>
      null;

  @override
  Future<void> setBotElo(int elo) async {}

  @override
  void dispose() {}
}

void main() {
  const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  const afterE4Fen =
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

  group('AttemptMoveUseCase', () {
    test('returns accepted when eval drop is within threshold', () async {
      // currentEval=20 (slight white edge), newEval=-10 (opponent perspective)
      // delta = -(-10) - 20 = 10 - 20 = -10 cp — well within 300 cp
      final usecase = AttemptMoveUseCase(
        _FakeEngine(currentEval: 20, newEval: -10),
      );
      final result = await usecase.execute(
        currentFen: startFen,
        newFen: afterE4Fen,
      );
      expect(result, MoveResult.accepted);
    });

    test('returns blunder when eval drops more than 300 cp', () async {
      // currentEval=50, newEval=400 (opponent now has big advantage)
      // delta = -(400) - 50 = -450 — exceeds -300 threshold
      final usecase = AttemptMoveUseCase(
        _FakeEngine(currentEval: 50, newEval: 400),
      );
      final result = await usecase.execute(
        currentFen: startFen,
        newFen: afterE4Fen,
      );
      expect(result, MoveResult.blunder);
    });

    test('returns accepted when positions are equal', () async {
      final usecase = AttemptMoveUseCase(
        _FakeEngine(currentEval: 0, newEval: 0),
      );
      final result = await usecase.execute(
        currentFen: startFen,
        newFen: afterE4Fen,
      );
      expect(result, MoveResult.accepted);
    });

    test('returns accepted when move improves position', () async {
      // currentEval=-100 (white losing), newEval=-200 (opponent perspective, so +200 for white after)
      // delta = -(-200) - (-100) = 200 + 100 = 300 — exactly at threshold, not a blunder
      final usecase = AttemptMoveUseCase(
        _FakeEngine(currentEval: -100, newEval: -200),
      );
      final result = await usecase.execute(
        currentFen: startFen,
        newFen: afterE4Fen,
      );
      expect(result, MoveResult.accepted);
    });
  });
}
