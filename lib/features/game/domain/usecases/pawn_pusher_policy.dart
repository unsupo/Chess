import 'package:chess/chess.dart' as chess_lib;
import '../entities/chess_move_analysis.dart';
import '../entities/engine_move_candidate.dart';
import 'scholars_mate_hunter_policy.dart';

/// Pure-Dart domain policy for "The Pawn Pusher" (`pawn_pusher`) personality.
///
/// Prioritizes advancing pawns, building pawn chains, kicking enemy pieces with
/// pawns, creating and pushing passed pawns, and promoting pawns, while still
/// taking forced checkmates, defending hanging pieces, and avoiding draws.
class PawnPusherPolicy {
  /// Maximum centipawn drop below Stockfish's best move that the bot will
  /// accept in order to push a safe pawn instead of making a quiet piece move.
  static const int pawnPushToleranceCp = 220;

  /// Selects a move from [fen] that strongly prioritizes safe, aggressive pawn
  /// pushes while respecting tactical safety and avoiding draws/repetitions.
  static String? selectMove({
    required String fen,
    required List<EngineMoveCandidate> candidates,
    Map<String, int> positionCounts = const {},
  }) {
    // 1. Always take an immediate Mate-in-1 if on the board.
    final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(fen);
    if (mateIn1 != null) return mateIn1;

    // 2. If Stockfish sees a forced checkmate, take the shortest mate.
    for (final c in candidates) {
      if (c.mateIn != null && c.mateIn! > 0) {
        return c.uci;
      }
    }

    final bestCp = candidates.isNotEmpty ? candidates.first.scoreCp : 0;

    // 3. Merge Stockfish's MultiPV candidates with safe legal pawn moves that
    //    Stockfish's MultiPV may have omitted in favor of piece moves.
    final allCandidates = <EngineMoveCandidate>[
      ...candidates,
      ..._discoverSafePawnCandidates(fen, candidates, positionCounts),
    ];

    if (allCandidates.isEmpty) return null;

    // 4. Filter to non-drawing candidates within tolerance of the best move.
    final viable = allCandidates.where((c) {
      if (c.mateIn != null && c.mateIn! < 0) return false;
      if (ScholarsMateHunterPolicy.wouldCauseDraw(fen, c.uci, positionCounts)) {
        return false;
      }
      return (bestCp - c.scoreCp) <= pawnPushToleranceCp;
    }).toList();

    final nonDrawingFallback = viable.isNotEmpty
        ? viable
        : allCandidates.where((c) {
            if (c.mateIn != null && c.mateIn! < 0) return false;
            return !ScholarsMateHunterPolicy.wouldCauseDraw(
              fen,
              c.uci,
              positionCounts,
            );
          }).toList();

    final pool = nonDrawingFallback.isNotEmpty
        ? nonDrawingFallback
        : [allCandidates.first];

    String bestUci = pool.first.uci;
    double bestTotalScore = double.negativeInfinity;

    for (final c in pool) {
      final pawnBonus = scorePawnCandidate(
        fen,
        c.uci,
        positionCounts: positionCounts,
      );
      final totalScore = c.scoreCp.toDouble() + pawnBonus;
      if (totalScore > bestTotalScore) {
        bestTotalScore = totalScore;
        bestUci = c.uci;
      }
    }

    return bestUci;
  }

  /// Scores a candidate move [uci] from [fen] according to Pawn Pusher
  /// priorities (pushing pawns, kicking pieces, advancing passed pawns,
  /// building pawn chains, promoting, and avoiding draws).
  static double scorePawnCandidate(
    String fen,
    String uci, {
    Map<String, int> positionCounts = const {},
  }) {
    final before = chess_lib.Chess()..load(fen);
    final us = before.turn;
    final them = us == chess_lib.Color.WHITE
        ? chess_lib.Color.BLACK
        : chess_lib.Color.WHITE;

    final fromSq = uci.substring(0, 2);
    final toSq = uci.substring(2, 4);
    final movingPiece = before.get(fromSq);
    final capturedPiece = before.get(toSq);
    if (movingPiece == null) return 0;

    final after = chess_lib.Chess()..load(fen);
    final moved = after.move({
      'from': fromSq,
      'to': toSq,
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return -10000;

    double bonus = 0;

    // 0. Anti-Draw & Anti-Repetition Penalties
    if (ScholarsMateHunterPolicy.wouldCauseDraw(fen, uci, positionCounts)) {
      bonus -= 5000;
    } else if (ScholarsMateHunterPolicy.wouldRepeatPosition(
      fen,
      uci,
      positionCounts,
    )) {
      bonus -= 800;
    }

    final isPawnMove = movingPiece.type == chess_lib.PieceType.PAWN;
    final isSafe = _isSafePawnOrPieceMove(fen, uci);

    if (!isSafe) {
      bonus -= 420;
    }

    if (isPawnMove) {
      // 1. Base bonus for moving a pawn (so safe pawn moves beat quiet piece moves)
      bonus += isSafe ? 270 : -150;

      // 2. Promotion bonus
      if (uci.length > 4) {
        bonus += uci[4] == 'q' ? 900 : 400;
      }

      // 3. Advancement rank bonus (how far up the board the pawn reaches)
      final toRank = int.parse(toSq[1]);
      final fromRank = int.parse(fromSq[1]);
      final relativeRank = us == chess_lib.Color.WHITE
          ? toRank
          : (9 - toRank); // 2..8
      bonus += (relativeRank - 2) * 42;
      if (relativeRank >= 6) {
        bonus += 130; // Deep thorn/passed pawn on 6th or 7th rank!
      }

      // 4. Double-step space grab (e.g. e2->e4, d2->d4, g2->g4)
      if ((toRank - fromRank).abs() == 2) {
        bonus += 55;
      }

      // 5. Center files (c, d, e, f) slight preference for strong phalanx
      final toFile = toSq.codeUnitAt(0);
      if (toFile >= 'c'.codeUnitAt(0) && toFile <= 'f'.codeUnitAt(0)) {
        bonus += 25;
      }

      // 6. Passed pawn push bonus
      if (_isPassedPawn(after, toSq, us)) {
        bonus += 150;
      }

      // 7. Kicking / Forking enemy pieces with the pushed pawn!
      final attackedTargets = _countEnemyPiecesAttackedByPawn(
        after,
        toSq,
        us,
        them,
      );
      if (attackedTargets >= 2) {
        bonus += 340; // Pawn fork!
      } else if (attackedTargets == 1 && isSafe) {
        bonus += 165; // Kicking an enemy Knight/Bishop/Rook/Queen!
      }

      // 8. Pawn capture bonus
      if (capturedPiece != null) {
        bonus += 130 + pieceValue(capturedPiece.type) * 28;
      }

      // 9. Pawn chain / supported square bonus
      if (_isSquareSupportedByFriendlyPawn(after, toSq, us)) {
        bonus += 55;
      }
    } else {
      // Non-pawn move: reward capturing high-value pieces or giving check when no safe pawn push applies
      if (capturedPiece != null) {
        bonus += pieceValue(capturedPiece.type) * 18;
      }
      if (after.in_check) {
        bonus += 60;
      }
    }

    return bonus;
  }

  /// Discovers legal, tactically safe pawn moves that were not in Stockfish's
  /// top [existingCandidates] so the policy can still push pawns when
  /// Stockfish only suggested piece moves.
  static List<EngineMoveCandidate> _discoverSafePawnCandidates(
    String fen,
    List<EngineMoveCandidate> existingCandidates,
    Map<String, int> positionCounts,
  ) {
    final existingUcis = {for (final c in existingCandidates) c.uci};
    final bestCp = existingCandidates.isNotEmpty
        ? existingCandidates.first.scoreCp
        : 0;
    final chess = chess_lib.Chess()..load(fen);
    if (chess.in_check) return const [];

    // Do not inject unvetted pawn moves if one of our major/minor pieces is
    // currently hanging undefended and needs to be saved first!
    if (_hasHangingNonPawnPiece(chess)) return const [];

    final discovered = <EngineMoveCandidate>[];
    for (final m in chess.generate_moves()) {
      if (m.piece != chess_lib.PieceType.PAWN) continue;
      final uci = moveToUci(m);
      if (existingUcis.contains(uci)) continue;
      if (ScholarsMateHunterPolicy.wouldCauseDraw(fen, uci, positionCounts) ||
          ScholarsMateHunterPolicy.wouldRepeatPosition(
            fen,
            uci,
            positionCounts,
          )) {
        continue;
      }
      if (!_isSafePawnOrPieceMove(fen, uci)) continue;

      discovered.add(EngineMoveCandidate(uci: uci, scoreCp: bestCp - 95));
    }
    return discovered;
  }

  // ── Internal Board Helpers ──────────────────────────────────────────────

  /// Checks whether any of our Knights, Bishops, Rooks, or Queens are currently
  /// attacked by a lower-value enemy piece or undefended against an enemy capture.
  ///
  /// Deliberately distinct from `chess_move_analysis.dart`'s
  /// `hangingPieceValueAfter` (general hanging-value-after-a-hypothetical-move
  /// check) — this one is scoped to non-pawn pieces on the *current* board,
  /// with no hypothetical move involved. See
  /// docs/features/done/refactor_02_shared_chess_helpers.md for why these stay
  /// separate functions rather than being merged.
  static bool _hasHangingNonPawnPiece(chess_lib.Chess currentChess) {
    final us = currentChess.turn;
    final tokens = currentChess.fen.split(' ');
    if (tokens.length < 6) return false;
    tokens[1] = us == chess_lib.Color.WHITE ? 'b' : 'w';
    tokens[3] = '-';
    final oppChess = chess_lib.Chess();
    if (!oppChess.load(tokens.join(' '))) return false;

    for (final oppMove in oppChess.generate_moves()) {
      final targetSq = chess_lib.Chess.algebraic(oppMove.to);
      final victim = currentChess.get(targetSq);
      if (victim == null ||
          victim.color != us ||
          victim.type == chess_lib.PieceType.PAWN ||
          victim.type == chess_lib.PieceType.KING) {
        continue;
      }
      final attackerSq = chess_lib.Chess.algebraic(oppMove.from);
      final attacker = currentChess.get(attackerSq);
      final victimVal = pieceValue(victim.type);
      final attackerVal = attacker != null ? pieceValue(attacker.type) : 1;

      if (attackerVal < victimVal) return true;

      oppChess.make_move(oppMove);
      var defended = false;
      for (final recap in oppChess.generate_moves()) {
        if (chess_lib.Chess.algebraic(recap.to) == targetSq) {
          defended = true;
          break;
        }
      }
      oppChess.undo_move();
      if (!defended) return true;
    }
    return false;
  }

  /// Verifies that playing [uci] from [fen] does not:
  /// 1. Allow opponent Mate-in-1
  /// 2. Hang the moved piece for free on its destination square
  /// 3. Leave one of our higher-value pieces (Knight/Bishop/Rook/Queen) en prise
  static bool _isSafePawnOrPieceMove(String fen, String uci) {
    final before = chess_lib.Chess()..load(fen);
    final us = before.turn;
    final fromSq = uci.substring(0, 2);
    final toSq = uci.substring(2, 4);
    final movedPiece = before.get(fromSq);
    final capturedPiece = before.get(toSq);
    if (movedPiece == null) return false;

    final movedVal = uci.length > 4 ? 9 : pieceValue(movedPiece.type);
    final capturedVal = capturedPiece != null
        ? pieceValue(capturedPiece.type)
        : 0;

    final after = chess_lib.Chess()..load(fen);
    if (!after.move({
      'from': fromSq,
      'to': toSq,
      if (uci.length > 4) 'promotion': uci[4],
    })) {
      return false;
    }

    for (final oppMove in after.generate_moves()) {
      final oppTo = chess_lib.Chess.algebraic(oppMove.to);
      final oppFrom = chess_lib.Chess.algebraic(oppMove.from);
      final victim = after.get(oppTo);
      final attacker = after.get(oppFrom);

      after.make_move(oppMove);
      if (after.in_checkmate) {
        after.undo_move();
        return false;
      }

      var canRecapture = false;
      for (final recap in after.generate_moves()) {
        if (chess_lib.Chess.algebraic(recap.to) == oppTo) {
          canRecapture = true;
          break;
        }
      }
      after.undo_move();

      if (victim != null && victim.color == us) {
        final victimVal = pieceValue(victim.type);
        final attackerVal = attacker != null ? pieceValue(attacker.type) : 1;

        // Never hang our Queen, Rook, Bishop, or Knight
        if (victimVal >= 3) {
          if (!canRecapture && victimVal > capturedVal) return false;
          if (victimVal - capturedVal - attackerVal >= 2) return false;
        }

        // If the opponent captures the pawn we just pushed to `toSq` and we
        // cannot recapture it (or we lose material on the exchange), don't push it!
        if (oppTo == toSq && movedPiece.type == chess_lib.PieceType.PAWN) {
          if (!canRecapture && movedVal > capturedVal) return false;
        }
      }
    }
    return true;
  }

  /// Checks if the pawn at [sq] in [chess] is a passed pawn (no enemy pawns
  /// ahead of it on the same file or adjacent files).
  static bool _isPassedPawn(
    chess_lib.Chess chess,
    String sq,
    chess_lib.Color us,
  ) {
    final fileCode = sq.codeUnitAt(0);
    final rank = int.parse(sq[1]);
    final them = us == chess_lib.Color.WHITE
        ? chess_lib.Color.BLACK
        : chess_lib.Color.WHITE;

    for (var df = -1; df <= 1; df++) {
      final fCode = fileCode + df;
      if (fCode < 'a'.codeUnitAt(0) || fCode > 'h'.codeUnitAt(0)) continue;
      final fChar = String.fromCharCode(fCode);
      if (us == chess_lib.Color.WHITE) {
        for (var r = rank + 1; r <= 7; r++) {
          final p = chess.get('$fChar$r');
          if (p != null &&
              p.color == them &&
              p.type == chess_lib.PieceType.PAWN) {
            return false;
          }
        }
      } else {
        for (var r = rank - 1; r >= 2; r--) {
          final p = chess.get('$fChar$r');
          if (p != null &&
              p.color == them &&
              p.type == chess_lib.PieceType.PAWN) {
            return false;
          }
        }
      }
    }
    return true;
  }

  /// Counts how many enemy non-pawn pieces (`Knight`, `Bishop`, `Rook`, `Queen`, `King`)
  /// are diagonally attacked by our pawn on [pawnSq].
  static int _countEnemyPiecesAttackedByPawn(
    chess_lib.Chess after,
    String pawnSq,
    chess_lib.Color us,
    chess_lib.Color them,
  ) {
    final fileCode = pawnSq.codeUnitAt(0);
    final rank = int.parse(pawnSq[1]);
    final targetRank = us == chess_lib.Color.WHITE ? rank + 1 : rank - 1;
    if (targetRank < 1 || targetRank > 8) return 0;

    var count = 0;
    for (final df in const [-1, 1]) {
      final fCode = fileCode + df;
      if (fCode < 'a'.codeUnitAt(0) || fCode > 'h'.codeUnitAt(0)) continue;
      final targetSq = '${String.fromCharCode(fCode)}$targetRank';
      final p = after.get(targetSq);
      if (p != null && p.color == them && p.type != chess_lib.PieceType.PAWN) {
        count++;
      }
    }
    return count;
  }

  /// Checks whether [sq] is defended by a friendly pawn on an adjacent file.
  static bool _isSquareSupportedByFriendlyPawn(
    chess_lib.Chess after,
    String sq,
    chess_lib.Color us,
  ) {
    final fileCode = sq.codeUnitAt(0);
    final rank = int.parse(sq[1]);
    final supportRank = us == chess_lib.Color.WHITE ? rank - 1 : rank + 1;
    if (supportRank < 1 || supportRank > 8) return false;

    for (final df in const [-1, 1]) {
      final fCode = fileCode + df;
      if (fCode < 'a'.codeUnitAt(0) || fCode > 'h'.codeUnitAt(0)) continue;
      final supportSq = '${String.fromCharCode(fCode)}$supportRank';
      final p = after.get(supportSq);
      if (p != null && p.color == us && p.type == chess_lib.PieceType.PAWN) {
        return true;
      }
    }
    return false;
  }
}
