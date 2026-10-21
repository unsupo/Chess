// Pure domain-logic tests for the move-analysis helpers that back the bot
// style-scoring policies (fork/check/capture/queen-trade detection for
// Aggressor & Trickster, hanging-piece detection for Defender). No Flutter,
// no engine — just the `chess` package. See
// docs/features/done/bot_play_styles.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:chess_teacher/features/game/domain/entities/chess_move_analysis.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _afterE4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

void main() {
  group('pieceValue', () {
    test('matches standard chess material values', () {
      expect(pieceValue(chess_lib.PieceType.PAWN), 1);
      expect(pieceValue(chess_lib.PieceType.KNIGHT), 3);
      expect(pieceValue(chess_lib.PieceType.BISHOP), 3);
      expect(pieceValue(chess_lib.PieceType.ROOK), 5);
      expect(pieceValue(chess_lib.PieceType.QUEEN), 9);
      expect(pieceValue(chess_lib.PieceType.KING), 0);
    });
  });

  group('applyUciToFen', () {
    test('plays a simple pawn move', () {
      expect(applyUciToFen(_startFen, 'e2e4'), _afterE4Fen);
    });

    test('handles promotion', () {
      const fen = '8/P6k/8/8/8/8/7K/8 w - - 0 1';
      final result = applyUciToFen(fen, 'a7a8q');
      final chess = chess_lib.Chess()..load(result);
      expect(chess.get('a8')?.type, chess_lib.PieceType.QUEEN);
    });
  });

  group('materialFor', () {
    test('both sides start with 39 points of non-king material', () {
      expect(materialFor(_startFen, chess_lib.Color.WHITE), 39);
      expect(materialFor(_startFen, chess_lib.Color.BLACK), 39);
    });

    test('counts only the pieces actually on the board', () {
      // Black's d-pawn is simply missing from this position.
      const fen = 'rnbqkbnr/ppp1pppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 2';
      expect(materialFor(fen, chess_lib.Color.BLACK), 38);
    });
  });

  group('MoveAnalysis.of', () {
    test('plain non-capturing move has no captured value and is not check', () {
      final analysis = MoveAnalysis.of(_startFen, 'e2e4');
      expect(analysis.capturedValue, 0);
      expect(analysis.isQueenCapture, false);
      expect(analysis.isCheck, false);
      expect(analysis.isCastle, false);
      expect(analysis.resultingFen, _afterE4Fen);
    });

    test('detects a capture and its value', () {
      const fen =
          '4k3/8/8/n7/8/8/8/R3K3 w - - 0 1'; // white rook a1, black knight a5
      final analysis = MoveAnalysis.of(fen, 'a1a5');
      expect(analysis.capturedValue, 3); // knight
      expect(analysis.isQueenCapture, false);
    });

    test('detects a queen trade (mover queen captures opponent queen)', () {
      const fen = '3qk3/8/8/8/8/8/8/3QK3 w - - 0 1';
      final analysis = MoveAnalysis.of(fen, 'd1d8');
      expect(analysis.capturedValue, 9);
      expect(analysis.isQueenCapture, true);
      expect(analysis.isCheck, true); // queen now adjacent to the black king
    });

    test('a rook capturing a queen is not flagged as a queen trade', () {
      const fen =
          '3qk3/8/8/8/8/8/8/3RK3 w - - 0 1'; // white rook d1 vs black queen d8
      final analysis = MoveAnalysis.of(fen, 'd1d8');
      expect(analysis.capturedValue, 9);
      expect(analysis.isQueenCapture, false); // mover's piece was a rook
    });

    test('detects check without a capture', () {
      const fen =
          '4k3/8/8/8/8/8/8/Q3K3 w - - 0 1'; // white queen a1, black king e8
      final analysis = MoveAnalysis.of(fen, 'a1a8');
      expect(analysis.capturedValue, 0);
      expect(analysis.isCheck, true);
    });

    test('detects kingside castling', () {
      const fen = '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1';
      final analysis = MoveAnalysis.of(fen, 'e1g1');
      expect(analysis.isCastle, true);
      expect(analysis.capturedValue, 0);
    });

    test('a normal king move is not flagged as castling', () {
      const fen = '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1';
      final analysis = MoveAnalysis.of(fen, 'e1d2');
      expect(analysis.isCastle, false);
    });
  });

  group('movesCreatesFork', () {
    test('knight move attacking a rook and a queen is a fork', () {
      // White knight a3 -> c4 attacks both b6 (rook) and d6 (queen).
      const fen = '4k3/8/1r1q4/8/8/N7/8/4K3 w - - 0 1';
      expect(movesCreatesFork(fen, 'a3c4'), true);
    });

    test('attacking two pawns (both below knight value) is not a fork', () {
      // Same geometry, but b6/d6 now hold pawns instead of rook/queen.
      const fen = '4k3/8/1p1p4/8/8/N7/8/4K3 w - - 0 1';
      expect(movesCreatesFork(fen, 'a3c4'), false);
    });

    test('attacking only one enemy piece is not a fork', () {
      const fen = '4k3/8/1r6/8/8/N7/8/4K3 w - - 0 1';
      expect(movesCreatesFork(fen, 'a3c4'), false);
    });

    test('a quiet king move creates no fork', () {
      const fen = '4k3/8/1r1q4/8/8/N7/8/4K3 w - - 0 1';
      expect(movesCreatesFork(fen, 'e1d1'), false);
    });
  });

  group('hangingPieceValueAfter', () {
    test('moving a queen to an attacked, undefended square hangs it', () {
      // White queen h1 -> h5, attacked by the black queen on e5 along rank
      // 5, with no white piece able to recapture on h5. King on b1 (not e1)
      // so it isn't sitting on the e5 queen's diagonal/file.
      const fen = '4k3/8/8/4q3/8/8/8/1K5Q w - - 0 1';
      expect(hangingPieceValueAfter(fen, 'h1h5'), 9);
    });

    test('a defended square is not counted as hanging', () {
      // Same idea, but a white rook on h1 can recapture on h5 once the
      // queen (now moved there from d1) is taken.
      const fen = '4k3/8/8/4q3/8/8/8/1K1Q3R w - - 0 1';
      expect(hangingPieceValueAfter(fen, 'd1h5'), 0);
    });

    test('a quiet move with nothing attacked afterward hangs nothing', () {
      expect(hangingPieceValueAfter(_startFen, 'e2e4'), 0);
    });

    test('a bishop moved onto an undefended diagonal hangs', () {
      // White bishop h1 -> f3, straight onto the black bishop's h5-f3
      // diagonal, with no white piece able to recapture on f3.
      const fen = '4k3/8/8/7b/8/8/8/4K2B w - - 0 1';
      expect(hangingPieceValueAfter(fen, 'h1f3'), 3);
    });
  });
}
