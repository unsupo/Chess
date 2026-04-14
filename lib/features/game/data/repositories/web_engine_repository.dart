import 'dart:math';
import 'package:chess/chess.dart' as chess_lib;
import '../../domain/repositories/chess_engine_repository.dart';

class ChessEngineRepositoryImpl implements ChessEngineRepository {
  @override
  Future<void> setBotElo(int elo) async {}

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async => 0;

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
  void dispose() {}
}
