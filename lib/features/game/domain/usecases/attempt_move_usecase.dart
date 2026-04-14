import '../entities/move_result.dart';
import '../repositories/chess_engine_repository.dart';

class AttemptMoveUseCase {
  final ChessEngineRepository _repository;
  final int blunderThresholdCp = 300; // 3 pawns

  AttemptMoveUseCase(this._repository);

  Future<MoveResult> execute({
    required String currentFen,
    required String newFen, 
  }) async {
    // 1. Evaluate current vs new position with higher depth (12)
    final currentEval = await _repository.evaluateFen(currentFen, depth: 12);
    final newEval = await _repository.evaluateFen(newFen, depth: 12);

    // UCI engine evaluation is ALWAYS relative to the side whose turn it is.
    // currentFen is evaluated from the mover's perspective.
    // newFen is evaluated from the opponent's perspective.
    // Therefore, the mover's advantage after the move is `-newEval`.
    final delta = -newEval - currentEval;

    // 2. Did the evaluation drop by more than the threshold?
    if (delta < -blunderThresholdCp) {
      return MoveResult.blunder;
    }

    return MoveResult.accepted;
  }
}
