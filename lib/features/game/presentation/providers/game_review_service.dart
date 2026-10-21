// The post-game eval cache extracted out of `GameNotifier` — see
// docs/features/refactor_05_game_notifier_facade.md. Owns `_fenEvalCache`
// and the engine calls needed to fill gaps in it.
//
// Deliberately does *not* own `GameNotifier._computeGameReview`'s two-phase
// orchestration (set a preliminary summary from cache immediately, then
// asynchronously fill gaps and set a refined one) — that reads/writes
// `GameState` and checks `mounted`, which are genuine state-coordination
// concerns this class has no business knowing about, same reasoning as
// `ClockService` not owning `tickClock`'s elapsed-time-to-state math. Only
// the cache and the "evaluate this one FEN if it isn't cached yet"
// operation move out.
import 'package:chess/chess.dart' as chess_lib;
import '../../domain/repositories/chess_engine_repository.dart';
import '../../domain/usecases/game_review_analyzer.dart';

class GameReviewService {
  final ChessEngineRepository _engine;
  final Map<String, int> _fenEvalCache = {
    GameReviewAnalyzer.fenKey(chess_lib.Chess.DEFAULT_POSITION): 20,
  };

  GameReviewService(this._engine);

  void recordEval(String fen, int cp) =>
      _fenEvalCache[GameReviewAnalyzer.fenKey(fen)] = cp;

  bool containsEval(String fen) =>
      _fenEvalCache.containsKey(GameReviewAnalyzer.fenKey(fen));

  /// Defensive copy — callers (`GameState.evalByFenKey`) must not be able
  /// to mutate this service's live cache.
  Map<String, int> get evalByFenKey => Map<String, int>.from(_fenEvalCache);

  /// Evaluates [fen] via the engine and records the result, unless it's
  /// already cached.
  Future<void> ensureEvaluated(String fen) async {
    if (containsEval(fen)) return;
    final score = await _engine.evaluateFen(fen);
    recordEval(fen, score);
  }

  GameReviewSummary analyze({
    required String initialFen,
    required List<String> sanMoves,
    required int botElo,
    required bool humanIsWhite,
  }) => GameReviewAnalyzer.analyze(
    initialFen: initialFen,
    sanMoves: sanMoves,
    evalByFenKey: evalByFenKey,
    botElo: botElo,
    humanIsWhite: humanIsWhite,
  );
}
