// Pure `chess` package analysis of individual moves — no Flutter, no
// engine I/O — shared by GameNotifier (applying the bot's chosen UCI move)
// and the bot-style scoring policies (domain/entities/bot_style_policy.dart).
//
// Everything here works by actually playing a move on a throwaway board and
// inspecting the result, rather than trying to reason about chess rules
// from the UCI string alone, so it's exercised directly by the `chess`
// package's own legality/attack logic.
import 'package:chess/chess.dart' as chess_lib;

/// Centipawn-ish piece values used by the style-scoring policies
/// (pawn=1 .. queen=9; king has no material value).
int pieceValue(chess_lib.PieceType type) {
  switch (type) {
    case chess_lib.PieceType.PAWN:
      return 1;
    case chess_lib.PieceType.KNIGHT:
    case chess_lib.PieceType.BISHOP:
      return 3;
    case chess_lib.PieceType.ROOK:
      return 5;
    case chess_lib.PieceType.QUEEN:
      return 9;
    default:
      return 0; // king
  }
}

/// Move in UCI notation (e.g. 'd1h5', 'f1c4', 'h5f7', 'e7e8q').
String moveToUci(chess_lib.Move m) {
  final from = chess_lib.Chess.algebraic(m.from);
  final to = chess_lib.Chess.algebraic(m.to);
  final promo = m.promotion != null ? m.promotion!.name : '';
  return '$from$to$promo';
}

/// Applies a UCI move string (e.g. "e2e4", "e7e8q") to [fen] and returns the
/// resulting FEN.
String applyUciToFen(String fen, String uci) {
  final chess = chess_lib.Chess();
  chess.load(fen);
  chess.move({
    'from': uci.substring(0, 2),
    'to': uci.substring(2, 4),
    if (uci.length > 4) 'promotion': uci[4],
  });
  return chess.fen;
}

/// Sum of piece values for [color]'s pieces on the board described by
/// [fen].
int materialFor(String fen, chess_lib.Color color) {
  final chess = chess_lib.Chess();
  chess.load(fen);
  var total = 0;
  for (final file in 'abcdefgh'.split('')) {
    for (final rank in ['1', '2', '3', '4', '5', '6', '7', '8']) {
      final piece = chess.get('$file$rank');
      if (piece != null && piece.color == color) {
        total += pieceValue(piece.type);
      }
    }
  }
  return total;
}

/// What a single UCI move does, computed by actually playing it.
class MoveAnalysis {
  final String resultingFen;
  final chess_lib.Color moverColor;
  final chess_lib.PieceType movedPiece;

  /// Value of the piece captured by this move, or 0 if it wasn't a capture.
  /// Note: en passant captures land on an empty square, so this
  /// undercounts that one rare case — a known, documented approximation.
  final int capturedValue;

  /// The mover's queen captured the opponent's queen.
  final bool isQueenCapture;

  /// The move gives check.
  final bool isCheck;

  /// The move is castling (either side).
  final bool isCastle;

  const MoveAnalysis({
    required this.resultingFen,
    required this.moverColor,
    required this.movedPiece,
    required this.capturedValue,
    required this.isQueenCapture,
    required this.isCheck,
    required this.isCastle,
  });

  factory MoveAnalysis.of(String fen, String uci) {
    final chess = chess_lib.Chess();
    chess.load(fen);
    final mover = chess.turn;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final movingPiece = chess.get(from)?.type ?? chess_lib.PieceType.PAWN;
    final targetPiece = chess.get(to);

    // Detect castling before the move mutates the board: the king moving
    // two files along its own rank.
    final isCastle =
        movingPiece == chess_lib.PieceType.KING &&
        from[1] == to[1] &&
        (from.codeUnitAt(0) - to.codeUnitAt(0)).abs() == 2;

    final moved = chess.move({
      'from': from,
      'to': to,
      if (uci.length > 4) 'promotion': uci[4],
    });

    if (!moved) {
      // Illegal/garbled move — shouldn't happen for engine-sourced UCI, but
      // fail safe rather than throw out of a scoring policy.
      return MoveAnalysis(
        resultingFen: fen,
        moverColor: mover,
        movedPiece: movingPiece,
        capturedValue: 0,
        isQueenCapture: false,
        isCheck: false,
        isCastle: false,
      );
    }

    final capturedValue = targetPiece != null
        ? pieceValue(targetPiece.type)
        : 0;
    final isQueenCapture =
        movingPiece == chess_lib.PieceType.QUEEN &&
        targetPiece?.type == chess_lib.PieceType.QUEEN;

    return MoveAnalysis(
      resultingFen: chess.fen,
      moverColor: mover,
      movedPiece: movingPiece,
      capturedValue: capturedValue,
      isQueenCapture: isQueenCapture,
      isCheck: chess.in_check, // turn has flipped to the opponent
      isCastle: isCastle,
    );
  }
}

String _withTurn(String fen, chess_lib.Color color) {
  final parts = fen.split(' ');
  parts[1] = color == chess_lib.Color.WHITE ? 'w' : 'b';
  return parts.join(' ');
}

/// Whether playing [uci] from [fen] creates a fork: the piece that just
/// moved ends up attacking 2+ enemy pieces, at least one worth >= a knight
/// (value 3).
bool movesCreatesFork(String fen, String uci) {
  final chess = chess_lib.Chess();
  chess.load(fen);
  final mover = chess.turn;
  final to = uci.substring(2, 4);
  final moved = chess.move({
    'from': uci.substring(0, 2),
    'to': to,
    if (uci.length > 4) 'promotion': uci[4],
  });
  if (!moved) return false;

  // `chess.turn` is now the opponent's. To see what the piece that just
  // landed on `to` attacks, probe pseudo-moves for it as if it were still
  // the mover's turn — the board is unchanged, only the side-to-move flag
  // is flipped for this throwaway probe.
  final probe = chess_lib.Chess();
  probe.load(_withTurn(chess.fen, mover));
  final attacks = probe.generate_moves({'square': to, 'legal': false});

  final attackedValues = <int>[];
  for (final m in attacks) {
    if (m.captured != null) attackedValues.add(pieceValue(m.captured!));
  }
  return attackedValues.length >= 2 && attackedValues.any((v) => v >= 3);
}

/// Total value of the mover's own pieces left hanging after [uci] is played
/// from [fen]: attacked by a legal opponent capture with no legal recapture
/// available on that square afterwards.
///
/// "Defended" here means "some legal recapture exists on that square" —
/// deliberately not weighing whether the recapture is itself a good trade.
/// That's a simplification flagged in docs/features/bot_play_styles.md.
int hangingPieceValueAfter(String fen, String uci) {
  final chess = chess_lib.Chess();
  chess.load(fen);
  final moved = chess.move({
    'from': uci.substring(0, 2),
    'to': uci.substring(2, 4),
    if (uci.length > 4) 'promotion': uci[4],
  });
  if (!moved) return 0;

  // `chess` is now on the opponent's turn; generate_moves() defaults to
  // legal moves for the side to move.
  final opponentCaptures = chess.generate_moves().where(
    (m) => m.captured != null,
  );

  var total = 0;
  final countedSquares = <int>{};
  for (final capture in opponentCaptures) {
    if (countedSquares.contains(capture.to)) continue;
    final victim = capture.captured!;

    final after = chess_lib.Chess();
    after.load(chess.fen);
    after.move({
      'from': chess_lib.Chess.algebraic(capture.from),
      'to': chess_lib.Chess.algebraic(capture.to),
    });
    final hasRecapture = after.generate_moves().any(
      (m) => m.to == capture.to && m.captured != null,
    );

    if (!hasRecapture) {
      total += pieceValue(victim);
      countedSquares.add(capture.to);
    }
  }
  return total;
}
