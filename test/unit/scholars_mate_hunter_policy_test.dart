import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/engine_move_candidate.dart';
import 'package:chess_teacher/features/game/domain/usecases/scholars_mate_hunter_policy.dart';

void main() {
  group('ScholarsMateHunterPolicy', () {
    test('Phase 1: Plays 1. e4 -> 2. Qh5 -> 3. Bc4 -> 4. Qxf7# when undefended', () {
      final chess = chess_lib.Chess();

      // Move 1: White plays e2e4
      final m1 = ScholarsMateHunterPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'g1f3', scoreCp: 30),
          EngineMoveCandidate(uci: 'e2e4', scoreCp: 25),
        ],
      );
      expect(m1, 'e2e4');
      chess.move({'from': 'e2', 'to': 'e4'});

      // Black replies 1... e5
      chess.move({'from': 'e7', 'to': 'e5'});

      // Move 2: White plays d1h5 (Wayward Queen) even when Stockfish prefers g1f3
      final m2 = ScholarsMateHunterPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'g1f3', scoreCp: 35),
          EngineMoveCandidate(uci: 'd1h5', scoreCp: -55),
        ],
      );
      expect(m2, 'd1h5');
      chess.move({'from': 'd1', 'to': 'h5'});

      // Black replies 2... Nc6
      chess.move({'from': 'b8', 'to': 'c6'});

      // Move 3: White plays f1c4 to complete the Scholar's Mate battery on f7
      final m3 = ScholarsMateHunterPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'f1c4', scoreCp: -40),
          EngineMoveCandidate(uci: 'g1f3', scoreCp: 0),
        ],
      );
      expect(m3, 'f1c4');
      chess.move({'from': 'f1', 'to': 'c4'});

      // Black blunders 3... Nf6??
      chess.move({'from': 'g8', 'to': 'f6'});

      // Move 4 (Phase 0): White immediately executes Qxf7# (`h5f7`)
      final m4 = ScholarsMateHunterPolicy.selectMove(
        fen: chess.fen,
        candidates: const [],
      );
      expect(m4, 'h5f7');
    });

    test('Phase 1 defense handling: Pivots 4. Qf3 (`h5f3`) when Black plays 3... g6', () {
      final chess = chess_lib.Chess();
      for (final m in [
        {'from': 'e2', 'to': 'e4'},
        {'from': 'e7', 'to': 'e5'},
        {'from': 'd1', 'to': 'h5'},
        {'from': 'b8', 'to': 'c6'},
        {'from': 'f1', 'to': 'c4'},
        {'from': 'g7', 'to': 'g6'}, // Attacks Queen on h5 and blocks f7!
      ]) {
        chess.move(m);
      }

      // Queen on h5 is attacked by g6 pawn; bot must not hang Queen, and
      // instead pivots to f3 (`h5f3`) renewing the Mate-in-1 threat on f7!
      final reply = ScholarsMateHunterPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'h5d1', scoreCp: 0),
          EngineMoveCandidate(uci: 'h5f3', scoreCp: -20),
        ],
      );
      expect(reply, 'h5f3');
    });

    test('Phase 1 safety: Does NOT play Bc4 if Queen on h5 is attacked by 2... Nf6, takes Qxe5+ instead', () {
      final chess = chess_lib.Chess();
      for (final m in [
        {'from': 'e2', 'to': 'e4'},
        {'from': 'e7', 'to': 'e5'},
        {'from': 'd1', 'to': 'h5'},
        {'from': 'g8', 'to': 'f6'}, // Attacks Queen on h5, leaves e5 undefended
      ]) {
        chess.move(m);
      }

      final reply = ScholarsMateHunterPolicy.selectMove(
        fen: chess.fen,
        candidates: const [
          EngineMoveCandidate(uci: 'h5e5', scoreCp: 220),
          EngineMoveCandidate(uci: 'f1c4', scoreCp: -700),
        ],
      );
      expect(reply, 'h5e5');
    });

    test('Phase 2: Always picks the shortest forced mate when multiple mate lines exist', () {
      const fen = '6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1';
      final chosen = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'd1d7', scoreCp: 10000, mateIn: 3),
          EngineMoveCandidate(uci: 'd1d8', scoreCp: 10000, mateIn: 1),
        ],
      );
      expect(chosen, 'd1d8');
    });

    test('Phase 3: Prefers direct check / mate-threat over quiet move and avoids Queen trade', () {
      // Position where White can trade Queens (d1d8), play a quiet move (a2a3),
      // or play a checking/king-zone attacking move.
      const fen = 'r2q1rk1/ppp2ppp/2n5/8/2B5/5Q2/PPPP1PPP/R1B1K2R w KQ - 0 8';
      final chosen = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'a2a3', scoreCp: 50), // Quiet move
          EngineMoveCandidate(uci: 'f3f7', scoreCp: 20), // Check into King zone!
        ],
      );
      expect(chosen, 'f3f7');
    });

    test('Avoids stalemate and position repetition when non-drawing moves exist', () {
      // White to move: e6f7 stalemates Black (7k/5B2/6P1/8/8/8/8/5K2 b - - 0 1),
      // whereas e6d5 keeps the game going without drawing.
      const fen = '7k/8/4B1P1/8/8/8/8/5K2 w - - 0 1';
      final chosen = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'e6f7', scoreCp: 0), // Stalemates Black!
          EngineMoveCandidate(uci: 'e6d5', scoreCp: 400), // Keeps pressing
        ],
      );
      expect(chosen, 'e6d5');

      // Position repetition avoidance: if e6c4 would repeat a previously seen
      // position, prefer e6d5 even when e6c4 is slightly higher Cp.
      const afterC4Key = '7k/8/6P1/8/2B5/8/8/5K2 b - -';
      final chosenNonRepeat = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'e6c4', scoreCp: 420),
          EngineMoveCandidate(uci: 'e6d5', scoreCp: 400),
        ],
        positionCounts: {afterC4Key: 1},
      );
      expect(chosenNonRepeat, 'e6d5');
    });

    test('Phase 0.5: Finds guaranteed Forced Mate-in-2 in pure Dart even with empty engine candidates', () {
      // White to move: 1. Qh6 forces 2. Qg7# against ALL legal Black moves.
      const mateIn2Fen = '6k1/3p1p1p/5Bp1/8/8/8/3Q1PPP/6K1 w - - 0 1';
      final mate2 = ScholarsMateHunterPolicy.findForcedMateIn2(mateIn2Fen);
      expect(mate2, 'd2h6');
    });

    test('Discovers safe Cheese Mate-in-1 trap in middlegame even when omitted from Stockfish MultiPV candidates', () {
      // Move 15 (past opening book): White has Bishop on c4; Stockfish only
      // returns quiet moves (a2a3, h2h3), but d1f3 / d1h5 lines up a direct
      // Qxf7# cheese mate threat against almost all Black moves!
      const fen = 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 4 15';
      final chosen = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: const [
          EngineMoveCandidate(uci: 'a2a3', scoreCp: 20),
          EngineMoveCandidate(uci: 'h2h3', scoreCp: 15),
        ],
      );
      expect(chosen, isIn(['d1f3', 'd1h5']));
    });
  });
}
