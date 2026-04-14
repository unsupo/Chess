abstract class ChessEngineRepository {
  /// Sets the bot's ELO level.
  Future<void> setBotElo(int elo);
  
  /// Evaluates a board state and returns the score in centipawns (cp).
  /// Positive is good for White, negative is good for Black.
  Future<int> evaluateFen(String fen, {int depth = 5});
  
  /// Asks the engine for the best move in UCI format (e.g., "e2e4").
  Future<String> getBestMove(String fen, {int movetimeMs = 500});
  
  void dispose();
}
