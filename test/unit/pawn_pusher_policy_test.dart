import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/engine_move_candidate.dart';
import 'package:chess_teacher/features/game/domain/usecases/pawn_pusher_policy.dart';

void main() {
  group('PawnPusherPolicy', () {
    test('Prioritizes a safe pawn push over a higher-scored quiet piece move', () {
      final chess = chess_lib.Chess();
      final chosen = PawnPusherPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'g1f3', scoreCp: 40),
          EngineMoveCandidate(uci: 'b1c3', scoreCp: 35),
          EngineMoveCandidate(uci: 'd2d4', scoreCp: 20),
        ],
      );
      expect(chosen, 'd2d4');
    });

    test('Discovers a safe pawn push even when Stockfish MultiPV only returns piece moves', () {
      final chess = chess_lib.Chess();
      final chosen = PawnPusherPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'g1f3', scoreCp: 35),
          EngineMoveCandidate(uci: 'b1c3', scoreCp: 30),
        ],
      );
      // Should pick a safe pawn push (e.g. d2d4 or e2e4) rather than g1f3/b1c3
      expect(
        chosen,
        isIn(['d2d4', 'e2e4', 'c2c4', 'f2f4']),
      );
    });

    test('Strongly prefers a pawn push that kicks an enemy Knight or advances a passed pawn', () {
      // White pawn on e4 can push e4e5 kicking Black's Knight on f6
      const fen = 'rnbqkb1r/ppp2ppp/5n2/3p4/4P3/2N5/PPPP1PPP/R1BQKBNR w KQkq - 0 4';
      final chosen = PawnPusherPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'a2a3', scoreCp: 10),
          EngineMoveCandidate(uci: 'e4e5', scoreCp: 0),
        ],
      );
      expect(chosen, 'e4e5');
    });

    test('Does not push an undefended pawn straight into a free enemy capture', () {
      // White pawn on e4: if pushed to e5, Black's d6 pawn and f6 Knight can capture it,
      // while d2d3 supports e4 safely.
      const fen = 'rnbqkb1r/ppp2ppp/3p1n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3';
      final chosen = PawnPusherPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'e4e5', scoreCp: -90), // Blunders e5 pawn
          EngineMoveCandidate(uci: 'd2d3', scoreCp: 10), // Safe supporting pawn push
        ],
      );
      expect(chosen, 'd2d3');
    });
  });
}
