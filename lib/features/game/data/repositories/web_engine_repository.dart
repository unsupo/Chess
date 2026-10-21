import 'dart:math';
import 'package:chess/chess.dart' as chess_lib;
import '../../domain/repositories/chess_engine_repository.dart';

class ChessEngineRepositoryImpl implements ChessEngineRepository {
  @override
  Future<void> setBotElo(int elo) async {}

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async => 0;

  // No real engine on web to search for a forced mate — always reports
  // "none found", which is a safe (if uninformative) default: the mate
  // safety feature simply has no effect on web.
  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async =>
      null;

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async {
    final chess = chess_lib.Chess();
    chess.load(fen);
    final moves = chess.generate_moves();
    if (moves.isEmpty) return "(none)";

    // Pick a random legal move to prevent predictable play and Scholar's Mate
    final random = Random();
    final move = moves[random.nextInt(moves.length)];

    final from = chess_lib.Chess.algebraic(move.from);
    final to = chess_lib.Chess.algebraic(move.to);
    final promotion = move.promotion != null ? move.promotion!.name : '';

    return "$from$to$promotion";
  }

  @override
  Future<List<EngineMoveCandidate>> getTopMoves(
    String fen, {
    int movetimeMs = 600,
    int multiPv = 6,
    int? mateLimit,
  }) async {
    final chess = chess_lib.Chess()..load(fen);
    final moves = chess.generate_moves();
    if (moves.isEmpty) return const [];
    return [
      for (final m in moves.take(multiPv))
        EngineMoveCandidate(
          uci:
              '${chess_lib.Chess.algebraic(m.from)}${chess_lib.Chess.algebraic(m.to)}${m.promotion?.name ?? ''}',
          scoreCp: 0,
        ),
    ];
  }

  @override
  void dispose() {}
}
