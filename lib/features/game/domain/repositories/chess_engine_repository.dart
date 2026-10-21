import '../entities/engine_move_candidate.dart';

export '../entities/engine_move_candidate.dart';

abstract class ChessEngineRepository {
  /// Sets the bot's ELO level.
  Future<void> setBotElo(int elo);

  /// Evaluates a board state and returns the score in centipawns (cp).
  /// Positive is good for White, negative is good for Black.
  Future<int> evaluateFen(String fen, {int depth = 5});

  /// Asks the engine for the best move in UCI format (e.g., "e2e4").
  Future<String> getBestMove(String fen, {int movetimeMs = 500});

  /// Returns up to [multiPv] ranked root move candidates from the engine.
  Future<List<EngineMoveCandidate>> getTopMoves(
    String fen, {
    int movetimeMs = 600,
    int multiPv = 6,
    int? mateLimit,
  }) async {
    final best = await getBestMove(fen, movetimeMs: movetimeMs);
    if (best == '(none)' || best.isEmpty) return const [];
    return [EngineMoveCandidate(uci: best, scoreCp: 0)];
  }

  /// Forced-mate distance (in moves) for the side to move in [fen], if the
  /// engine finds one within the search budget — positive N means that
  /// side can force mate in N moves. Returns null if no forced mate is
  /// found within the budget (NOT a proof that none exists at any depth).
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500});

  void dispose();
}
