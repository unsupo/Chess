import 'dart:math' as math;
import 'package:chess/chess.dart' as chess_lib;
import '../entities/chess_move_analysis.dart';
import '../entities/engine_move_candidate.dart';

/// Pure-Dart domain policy that implements the 3-Phase Fast-Mate Hunter:
///   - Phase 0: Immediate Mate-in-1 execution (`Qxf7#`, `Qxf2#`, etc.)
///   - Phase 1: Position-aware Scholar's Mate / Wayward Queen trap sequence
///              (for both White targeting f7 and Black targeting f2, with
///              automatic `Qf3`/`Qf6` battery continuation if poked by `g6`/`g3`,
///              and safety validation so it never hangs the Queen).
///   - Phase 2: Shortest Forced-Mate selection (`mateIn > 0`).
///   - Phase 3: "Keep Pressing" King-Hunt candidate scorer (mate-in-1 threats,
///              direct checks, enemy king-zone attacks/captures, piece
///              advancement toward the enemy king, and queen-trade avoidance).
class ScholarsMateHunterPolicy {
  /// Opening trap tolerance in centipawns (2. Qh5 is ~70cp below 2. Nf3, so
  /// 240cp allows Wayward Queen, Fried Liver, and gambit cheese setups while
  /// rejecting moves that lose a piece for nothing).
  static const int openingTrapToleranceCp = 240;

  /// Standard middlegame tolerance band in centipawns.
  static const int baseToleranceCp = 200;

  /// Tolerance band when a candidate creates a direct cheese Mate-in-1 threat.
  static const int cheeseThreatToleranceCp = 300;

  /// Widened tolerance band when the bot is already winning (>= +300cp),
  /// allowing aggressive sacrifices and direct mating attacks over slow play.
  static const int winningToleranceCp = 350;

  /// Phase 0: Returns a UCI move if any legal move delivers checkmate immediately.
  static String? findImmediateMateIn1(String fen) {
    final chess = chess_lib.Chess()..load(fen);
    final moves = chess.generate_moves();
    for (final move in moves) {
      chess.make_move(move);
      final isMate = chess.in_checkmate;
      chess.undo_move();
      if (isMate) {
        return moveToUci(move);
      }
    }
    return null;
  }

  /// Phase 0.5: Pure-Dart 2-ply Forced Mate-in-2 scanner.
  /// Returns a UCI move if any legal move guarantees checkmate on the very next
  /// turn against ALL legal opponent replies.
  static String? findForcedMateIn2(
    String fen, [
    Map<String, int> positionCounts = const {},
  ]) {
    final chess = chess_lib.Chess()..load(fen);
    for (final move in chess.generate_moves()) {
      final uci = moveToUci(move);
      if (wouldCauseDraw(fen, uci, positionCounts)) continue;
      chess.make_move(move);
      if (chess.in_checkmate) {
        chess.undo_move();
        return uci;
      }
      final oppMoves = chess.generate_moves();
      if (oppMoves.isEmpty) {
        chess.undo_move();
        continue;
      }
      var allRepliesGetMatedIn1 = true;
      for (final oppMove in oppMoves) {
        chess.make_move(oppMove);
        final mateReply = findImmediateMateIn1(chess.fen);
        chess.undo_move();
        if (mateReply == null) {
          allRepliesGetMatedIn1 = false;
          break;
        }
      }
      chess.undo_move();
      if (allRepliesGetMatedIn1) {
        return uci;
      }
    }
    return null;
  }

  /// Runs Phases 0 -> 0.5 -> 2 -> 1 -> 3 to select the most aggressive
  /// mate-seeking or cheese-mate trap move.
  static String? selectMove({
    required String fen,
    required List<EngineMoveCandidate> candidates,
    Map<String, int> positionCounts = const {},
  }) {
    // Phase 0: Immediate Mate-in-1
    final mateIn1 = findImmediateMateIn1(fen);
    if (mateIn1 != null) return mateIn1;

    // Phase 0.5: Immediate Forced Mate-in-2 (100% pure-Dart verification)
    final mateIn2 = findForcedMateIn2(fen, positionCounts);
    if (mateIn2 != null) return mateIn2;

    // Phase 2: Shortest Forced Mate from Stockfish MultiPV
    final forcedMateMove = _findShortestForcedMate(candidates);
    if (forcedMateMove != null) return forcedMateMove;

    // Phase 1: Position-Aware Scholar's Mate & Cheese Trap Book (first 10 moves)
    final openingMove = _pickScholarsMateOpeningMove(
      fen,
      candidates,
      positionCounts,
    );
    if (openingMove != null) return openingMove;

    // Phase 3: "Keep Pressing" King-Hunt & Cheese-Mate Scorer
    if (candidates.isNotEmpty) {
      return _pickAggressiveMove(fen, candidates, positionCounts);
    }

    return null;
  }

  /// Returns true if neither side has sufficient material to force checkmate:
  /// - `K vs K`, `K+B vs K`, `K+N vs K`
  /// - `K+B vs K+B` (same-colored OR opposite-colored bishops)
  /// - `K+B vs K+N`, `K+N vs K+N`
  /// - `K+2N vs K` (two knights vs lone king cannot force checkmate)
  static bool isInsufficientMatingMaterial(String fen) {
    final boardPart = fen.split(RegExp(r'\s+')).first;
    var wB = 0, wN = 0, bB = 0, bN = 0;
    for (var i = 0; i < boardPart.length; i++) {
      switch (boardPart[i]) {
        case 'P':
        case 'p':
        case 'R':
        case 'r':
        case 'Q':
        case 'q':
          return false;
        case 'B':
          wB++;
        case 'N':
          wN++;
        case 'b':
          bB++;
        case 'n':
          bN++;
      }
    }
    final wMinors = wB + wN;
    final bMinors = bB + bN;
    // Any endgame with at most 1 minor piece per side (K vs K, KB vs K, KN vs K,
    // KB vs KB of any square color, KB vs KN, KN vs KN) cannot force checkmate.
    if (wMinors <= 1 && bMinors <= 1) return true;
    // K+2N vs K cannot force checkmate.
    if (wB == 0 && wN == 2 && bMinors == 0) return true;
    if (bB == 0 && bN == 2 && wMinors == 0) return true;
    return false;
  }

  /// Returns true if playing [uci] from [fen] immediately causes a draw
  /// (stalemate, insufficient material, 50-move rule, or threefold repetition).
  static bool wouldCauseDraw(
    String fen,
    String uci, [
    Map<String, int> positionCounts = const {},
  ]) {
    final after = chess_lib.Chess()..load(fen);
    final moved = after.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return false;
    if (after.in_checkmate) return false;
    if (after.in_stalemate ||
        after.insufficient_material ||
        isInsufficientMatingMaterial(after.fen) ||
        after.half_moves >= 100) {
      return true;
    }
    final key = _positionKey(after.fen);
    return (positionCounts[key] ?? 0) >= 2;
  }

  /// Returns true if playing [uci] from [fen] repeats any previously seen
  /// board position (even a 2-fold repetition).
  static bool wouldRepeatPosition(
    String fen,
    String uci,
    Map<String, int> positionCounts,
  ) {
    if (positionCounts.isEmpty) return false;
    final after = chess_lib.Chess()..load(fen);
    final moved = after.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return false;
    final key = _positionKey(after.fen);
    return (positionCounts[key] ?? 0) >= 1;
  }

  static String _positionKey(String fen) =>
      fen.split(RegExp(r'\s+')).take(4).join(' ');

  /// Phase 2: Picks the candidate with the smallest positive `mateIn`.
  static String? _findShortestForcedMate(List<EngineMoveCandidate> candidates) {
    EngineMoveCandidate? bestMate;
    for (final c in candidates) {
      if (c.mateIn != null && c.mateIn! > 0) {
        if (bestMate == null || c.mateIn! < bestMate.mateIn!) {
          bestMate = c;
        }
      }
    }
    return bestMate?.uci;
  }

  /// Phase 1: Multi-wave Scholar's Mate, Wayward Queen, Fried Liver, and
  /// Defender-Elimination cheese traps for White (targeting f7/g7/h7) and
  /// Black (targeting f2/g2/h2) during the first 10 moves.
  static String? _pickScholarsMateOpeningMove(
    String fen,
    List<EngineMoveCandidate> candidates, [
    Map<String, int> positionCounts = const {},
  ]) {
    final chess = chess_lib.Chess()..load(fen);
    if (chess.in_check) return null; // Defend check tactically via Phase 3

    final fenTokens = fen.split(RegExp(r'\s+'));
    final fullMoveNumber =
        (fenTokens.length > 5 ? int.tryParse(fenTokens[5]) : null) ?? 1;
    if (fullMoveNumber > 6) return null;

    final isWhite = chess.turn == chess_lib.Color.WHITE;
    final them = isWhite ? chess_lib.Color.BLACK : chess_lib.Color.WHITE;
    final enemyKingSq = _findKingSquare(chess, them);
    final targetWeakSq = isWhite ? 'f7' : 'f2';
    // Only run the f7/f2 Scholar's Mate opening book while f7/f2 is adjacent
    // to the enemy King.
    if (enemyKingSq == null || _chebyshevDist(enemyKingSq, targetWeakSq) > 1) {
      return null;
    }
    final legalUcis = {for (final m in chess.generate_moves()) moveToUci(m)};

    final desiredTrapMoves = <String>[];

    if (isWhite) {
      final e2Piece = chess.get('e2');
      final d1Piece = chess.get('d1');
      final f1Piece = chess.get('f1');
      final h5Piece = chess.get('h5');
      final c4Piece = chess.get('c4');
      final f3Piece = chess.get('f3');
      final b3Piece = chess.get('b3');
      final c3Piece = chess.get('c3');

      // 1. Open e2-e4
      if (fullMoveNumber == 1 &&
          e2Piece?.type == chess_lib.PieceType.PAWN &&
          e2Piece?.color == chess_lib.Color.WHITE) {
        desiredTrapMoves.add('e2e4');
      }

      // 2. If Queen is on h5 and under attack (e.g. after ...g6 or ...Nf6),
      //    capture e5 if unprotected (`h5e5`) or pivot Queen to f3 (`h5f3`)
      //    to maintain the Mate-in-1 battery on f7!
      if (h5Piece?.type == chess_lib.PieceType.QUEEN &&
          h5Piece?.color == chess_lib.Color.WHITE &&
          _isSquareAttackedByOpponent(chess, 'h5')) {
        desiredTrapMoves.addAll(['h5e5', 'h5f3', 'h5h6', 'h5h4']);
      }

      // If Queen on f3 is attacked, pivot to b3 (maintaining f7/b7 double threat) or g3
      if (f3Piece?.type == chess_lib.PieceType.QUEEN &&
          f3Piece?.color == chess_lib.Color.WHITE &&
          _isSquareAttackedByOpponent(chess, 'f3')) {
        desiredTrapMoves.addAll(['f3b3', 'f3g3', 'f3e3']);
      }

      // 3. Bring out Qh5 and Bc4 to form the Scholar's Mate battery on f7
      final queenOnBattery =
          (h5Piece?.type == chess_lib.PieceType.QUEEN &&
              h5Piece?.color == chess_lib.Color.WHITE) ||
          (f3Piece?.type == chess_lib.PieceType.QUEEN &&
              f3Piece?.color == chess_lib.Color.WHITE) ||
          (b3Piece?.type == chess_lib.PieceType.QUEEN &&
              b3Piece?.color == chess_lib.Color.WHITE);
      final bishopOnBattery =
          c4Piece?.type == chess_lib.PieceType.BISHOP &&
          c4Piece?.color == chess_lib.Color.WHITE;

      if (d1Piece?.type == chess_lib.PieceType.QUEEN &&
          d1Piece?.color == chess_lib.Color.WHITE) {
        desiredTrapMoves.add('d1h5');
      }
      if (f1Piece?.type == chess_lib.PieceType.BISHOP &&
          f1Piece?.color == chess_lib.Color.WHITE) {
        desiredTrapMoves.add('f1c4');
      }
      if (d1Piece?.type == chess_lib.PieceType.QUEEN &&
          d1Piece?.color == chess_lib.Color.WHITE &&
          bishopOnBattery) {
        desiredTrapMoves.addAll(['d1f3', 'd1h5', 'd1b3']);
      }

      // 4. Wave 2 & 3 Cheese Traps when Scholar's Mate #1 is defended:
      //    - Nd5! (`c3d5`): attacks pinned/blocking f6 Knight + c7 fork
      //    - Ng5! (`f3g5` / `h3g5`): Fried Liver / 3rd attacker on f7 & h7
      //    - Bg5 / Bh6 (`c1g5` / `c1h6`): removes Black's f6 defender of f7/h7
      //    - Qb3 (`f3b3`): double-targets f7 and b7
      if (queenOnBattery || bishopOnBattery) {
        if (c3Piece?.type == chess_lib.PieceType.KNIGHT &&
            c3Piece?.color == chess_lib.Color.WHITE) {
          desiredTrapMoves.add('c3d5');
        }
        desiredTrapMoves.addAll([
          'f3g5',
          'h3g5',
          'c1g5',
          'c1h6',
          'b1c3',
          'g1f3',
          'g1h3',
          'f3b3',
          'd2d4',
          'd2d3',
        ]);
      }
    } else {
      // Black Mirror Scholar's Mate & Blackburne Shilling / Rousseau cheese targeting f2
      final e7Piece = chess.get('e7');
      final d8Piece = chess.get('d8');
      final f8Piece = chess.get('f8');
      final h4Piece = chess.get('h4');
      final c5Piece = chess.get('c5');
      final f6Piece = chess.get('f6');
      final b6Piece = chess.get('b6');
      final c6Piece = chess.get('c6');

      if (fullMoveNumber == 1 &&
          e7Piece?.type == chess_lib.PieceType.PAWN &&
          e7Piece?.color == chess_lib.Color.BLACK) {
        desiredTrapMoves.add('e7e5');
      }

      if (h4Piece?.type == chess_lib.PieceType.QUEEN &&
          h4Piece?.color == chess_lib.Color.BLACK &&
          _isSquareAttackedByOpponent(chess, 'h4')) {
        desiredTrapMoves.addAll(['h4e4', 'h4f6', 'h4h3', 'h4h5']);
      }

      if (f6Piece?.type == chess_lib.PieceType.QUEEN &&
          f6Piece?.color == chess_lib.Color.BLACK &&
          _isSquareAttackedByOpponent(chess, 'f6')) {
        desiredTrapMoves.addAll(['f6b6', 'f6g6', 'f6e6']);
      }

      final queenOnBattery =
          (h4Piece?.type == chess_lib.PieceType.QUEEN &&
              h4Piece?.color == chess_lib.Color.BLACK) ||
          (f6Piece?.type == chess_lib.PieceType.QUEEN &&
              f6Piece?.color == chess_lib.Color.BLACK) ||
          (b6Piece?.type == chess_lib.PieceType.QUEEN &&
              b6Piece?.color == chess_lib.Color.BLACK);
      final bishopOnBattery =
          c5Piece?.type == chess_lib.PieceType.BISHOP &&
          c5Piece?.color == chess_lib.Color.BLACK;

      if (d8Piece?.type == chess_lib.PieceType.QUEEN &&
          d8Piece?.color == chess_lib.Color.BLACK) {
        desiredTrapMoves.add('d8h4');
      }
      if (f8Piece?.type == chess_lib.PieceType.BISHOP &&
          f8Piece?.color == chess_lib.Color.BLACK) {
        desiredTrapMoves.add('f8c5');
      }
      if (d8Piece?.type == chess_lib.PieceType.QUEEN &&
          d8Piece?.color == chess_lib.Color.BLACK &&
          bishopOnBattery) {
        desiredTrapMoves.addAll(['d8f6', 'd8h4', 'd8b6']);
      }

      if (queenOnBattery || bishopOnBattery) {
        if (c6Piece?.type == chess_lib.PieceType.KNIGHT &&
            c6Piece?.color == chess_lib.Color.BLACK) {
          desiredTrapMoves.add('c6d4');
        }
        desiredTrapMoves.addAll([
          'f6g4',
          'h6g4',
          'c8g4',
          'c8h3',
          'b8c6',
          'g8f6',
          'g8h6',
          'f6b6',
          'd7d5',
          'd7d6',
        ]);
      }
    }

    final bestEngineScore = candidates.isNotEmpty
        ? candidates.first.scoreCp
        : 0;

    for (final trapUci in desiredTrapMoves) {
      if (!legalUcis.contains(trapUci)) continue;

      // Safety Check 1: Does this move hang our Queen, lose a piece for free,
      // allow mate, or cause a draw/repetition?
      if (!_isSafeCheeseTrap(fen, trapUci)) continue;
      if (wouldCauseDraw(fen, trapUci, positionCounts) ||
          wouldRepeatPosition(fen, trapUci, positionCounts)) {
        continue;
      }

      // Safety Check 2: If engine candidates include this move, verify it's within
      // openingTrapToleranceCp of the best move.
      final matchingCandidate = candidates
          .where((c) => c.uci == trapUci)
          .firstOrNull;
      if (matchingCandidate != null) {
        if (matchingCandidate.mateIn != null && matchingCandidate.mateIn! < 0) {
          continue;
        }
        if (bestEngineScore - matchingCandidate.scoreCp >
            openingTrapToleranceCp) {
          continue;
        }
      }

      return trapUci;
    }

    return null;
  }

  /// Scans all legal moves in [fen] to discover safe "Cheese Mate" traps
  /// (moves that threaten immediate Mate-in-1 against most opponent replies)
  /// that Stockfish's top MultiPV lines may have filtered out.
  static List<EngineMoveCandidate> _discoverCheeseMateCandidates(
    String fen,
    List<EngineMoveCandidate> existingCandidates,
    Map<String, int> positionCounts,
  ) {
    final existingUcis = {for (final c in existingCandidates) c.uci};
    final bestCp = existingCandidates.isNotEmpty
        ? existingCandidates.first.scoreCp
        : 0;
    final chess = chess_lib.Chess()..load(fen);
    final us = chess.turn;
    final discovered = <EngineMoveCandidate>[];

    for (final m in chess.generate_moves()) {
      final uci = moveToUci(m);
      if (existingUcis.contains(uci)) continue;
      if (wouldCauseDraw(fen, uci, positionCounts) ||
          wouldRepeatPosition(fen, uci, positionCounts)) {
        continue;
      }

      chess.make_move(m);
      final afterFen = chess.fen;
      final givesCheck = chess.in_check;
      chess.undo_move();

      final threatCount = _countMateIn1Threats(afterFen, us);
      if (threatCount == 0 && !givesCheck) continue;

      if (!_isSafeCheeseTrap(fen, uci)) continue;

      final stats = _analyzeOpponentMateSurvival(afterFen);
      if (stats.matedReplies == 0) continue;

      // If at least 40% of the opponent's replies walk into Mate-in-1, or the
      // opponent has <= 3 non-mated replies in the entire position, inject it!
      if (stats.matedRatio >= 0.40 ||
          stats.safeReplies <= 3 ||
          threatCount >= 2) {
        discovered.add(
          EngineMoveCandidate(
            uci: uci,
            // Assign baseline cp slightly below bestCp so Phase 3's cheese
            // bonuses can elevate it if it's the deadliest trap on the board.
            scoreCp: bestCp - 90,
          ),
        );
      }
    }
    return discovered;
  }

  /// Phase 3: Scores candidate moves to relentlessly press against the enemy King
  /// and hunt for cheese mates while strictly avoiding draws and repetitions.
  static String _pickAggressiveMove(
    String fen,
    List<EngineMoveCandidate> candidates, [
    Map<String, int> positionCounts = const {},
  ]) {
    final bestCp = candidates.first.scoreCp;
    final baseTolerance = bestCp >= 300
        ? winningToleranceCp
        : (bestCp < -150 ? 110 : baseToleranceCp);

    final chess = chess_lib.Chess()..load(fen);
    final us = chess.turn;

    // Merge Stockfish's MultiPV candidates with any pure-Dart discovered
    // Cheese-Mate trap moves that Stockfish's MultiPV omitted.
    final allCandidates = <EngineMoveCandidate>[
      ...candidates,
      ..._discoverCheeseMateCandidates(fen, candidates, positionCounts),
    ];

    // Prefer candidates that do NOT cause a draw or get us mated.
    // Candidates that create a direct Mate-in-1 threat get a wider tolerance
    // (`cheeseThreatToleranceCp`) so the bot will gambit a pawn/exchange to
    // set a lethal mate trap!
    final nonDrawingViable = allCandidates.where((c) {
      if (c.mateIn != null && c.mateIn! < 0) return false;
      if (wouldCauseDraw(fen, c.uci, positionCounts)) return false;
      final afterFen = _applyUciFen(fen, c.uci);
      final createsMateThreat =
          afterFen != null &&
          _countMateIn1Threats(afterFen, us) > 0 &&
          _isSafeCheeseTrap(fen, c.uci);
      final effectiveTolerance = createsMateThreat
          ? math.max(baseTolerance, cheeseThreatToleranceCp)
          : baseTolerance;
      return (bestCp - c.scoreCp) <= effectiveTolerance;
    }).toList();

    final anyNonDrawing = nonDrawingViable.isNotEmpty
        ? nonDrawingViable
        : allCandidates.where((c) {
            if (c.mateIn != null && c.mateIn! < 0) return false;
            return !wouldCauseDraw(fen, c.uci, positionCounts);
          }).toList();

    final pool = anyNonDrawing.isNotEmpty ? anyNonDrawing : [candidates.first];

    String bestUci = pool.first.uci;
    double bestTotalScore = double.negativeInfinity;

    for (final c in pool) {
      final styleBonus = scoreAggressiveCandidate(
        fen,
        c.uci,
        positionCounts: positionCounts,
      );
      final totalScore = c.scoreCp.toDouble() + styleBonus;
      if (totalScore > bestTotalScore) {
        bestTotalScore = totalScore;
        bestUci = c.uci;
      }
    }

    // Final safety fallback: if even bestUci would cause a draw, scan all
    // legal moves to find a safe non-drawing attacking move if one exists.
    if (wouldCauseDraw(fen, bestUci, positionCounts)) {
      for (final m in chess.generate_moves()) {
        final uci = moveToUci(m);
        if (!wouldCauseDraw(fen, uci, positionCounts) &&
            !wouldRepeatPosition(fen, uci, positionCounts) &&
            !_hangsQueenOrAllowsMate(fen, uci)) {
          return uci;
        }
      }
    }

    return bestUci;
  }

  /// Computes the tactical, cheese-mate, & king-hunt bonus (in cp-equivalent
  /// units) for playing [uci] from [fen].
  static double scoreAggressiveCandidate(
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

    final enemyKingSq = _findKingSquare(before, them);

    final after = chess_lib.Chess()..load(fen);
    final moved = after.move({
      'from': fromSq,
      'to': toSq,
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return -10000;

    double bonus = 0;

    // 0. Fierce Anti-Draw & Anti-Repetition Penalties
    if (wouldCauseDraw(fen, uci, positionCounts)) {
      bonus -= 5000;
    } else if (wouldRepeatPosition(fen, uci, positionCounts)) {
      bonus -= 900; // Refuse to shuffle back to a visited position!
    }

    // 1. Cheese Mate-in-1 Threat Analysis
    final threatCount = _countMateIn1Threats(after.fen, us);
    final isSafeTrap = _isSafeCheeseTrap(fen, uci);
    if (threatCount > 0 && isSafeTrap) {
      // Massive bonus for setting up a genuine Mate-in-1 trap!
      bonus += 550 + (threatCount - 1) * 180;
      final survival = _analyzeOpponentMateSurvival(after.fen);
      // Reward moves where a huge fraction of the human's legal replies walk
      // straight into Mate-in-1 ("hope-chess" lethality):
      bonus += (survival.matedRatio * 300);
      if (survival.safeReplies <= 2) {
        bonus += 220; // Opponent has only 1 or 2 non-mated moves!
      }
    } else if (threatCount > 0 && !isSafeTrap) {
      // Fake mate threat that hangs our piece for free and stops the mate
      bonus -= 350;
    }

    // 2. Direct Check (+140) & Opponent King Mobility Squeeze
    if (after.in_check) {
      bonus += 140;
      final survival = _analyzeOpponentMateSurvival(after.fen);
      bonus += math.max(0, 6 - survival.totalReplies) * 28;
      // Checking move where some King evasions walk into Mate-in-1!
      if (survival.matedReplies > 0 && isSafeTrap) {
        bonus += 260 + survival.matedReplies * 45;
      }
    }

    // 3. Captures (weighted higher if near the enemy King or removing a King defender!)
    if (capturedPiece != null) {
      final victimVal = pieceValue(capturedPiece.type);
      bonus += victimVal * 24;
      if (enemyKingSq != null && _chebyshevDist(toSq, enemyKingSq) <= 2) {
        bonus += 145; // Ripping open the enemy King's shield!
      }
    }

    // 4. 50-move clock pressure: when half_moves builds up, strongly reward
    //    pawn pushes and captures to break the position open and avoid 50-move draws
    if (before.half_moves >= 8 &&
        (movingPiece.type == chess_lib.PieceType.PAWN ||
            capturedPiece != null)) {
      bonus += 90 + math.min(120, before.half_moves * 4);
    }

    // 5. Battery & King-Zone Concentration (f7/g7/h7 or f2/g2/h2)
    if (enemyKingSq != null) {
      final distBefore = _chebyshevDist(fromSq, enemyKingSq);
      final distAfter = _chebyshevDist(toSq, enemyKingSq);
      if (distAfter < distBefore) {
        bonus += (distBefore - distAfter) * 22;
      }
      if (distAfter <= 2) {
        bonus += movingPiece.type == chess_lib.PieceType.QUEEN ? 115 : 75;
      }
      // Bonus for concentrating multiple attackers on squares adjacent to enemy King
      final kingZonePressure = _countKingZoneAttackers(after, us, enemyKingSq);
      bonus += kingZonePressure * 28;
    }

    // 6. Heavy Penalty for Trading Queens (-550)
    final isQueenTrade =
        movingPiece.type == chess_lib.PieceType.QUEEN &&
        capturedPiece?.type == chess_lib.PieceType.QUEEN;
    if (isQueenTrade) {
      bonus -= 550;
    } else if (_allowsOpponentQueenTrade(after, us)) {
      bonus -= 350;
    }

    return bonus;
  }

  // ── Internal Board Helpers ──────────────────────────────────────────────

  static String? _findKingSquare(chess_lib.Chess chess, chess_lib.Color color) {
    const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    for (final f in files) {
      for (var r = 1; r <= 8; r++) {
        final sq = '$f$r';
        final p = chess.get(sq);
        if (p != null &&
            p.color == color &&
            p.type == chess_lib.PieceType.KING) {
          return sq;
        }
      }
    }
    return null;
  }

  static int _chebyshevDist(String sq1, String sq2) {
    final f1 = sq1.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final r1 = sq1.codeUnitAt(1) - '1'.codeUnitAt(0);
    final f2 = sq2.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final r2 = sq2.codeUnitAt(1) - '1'.codeUnitAt(0);
    return math.max((f1 - f2).abs(), (r1 - r2).abs());
  }

  /// Checks if `square` can be captured by the opponent on the next ply if
  /// we pass the turn.
  static bool _isSquareAttackedByOpponent(
    chess_lib.Chess currentChess,
    String square,
  ) {
    final tokens = currentChess.fen.split(' ');
    if (tokens.length < 6) return false;
    tokens[1] = tokens[1] == 'w' ? 'b' : 'w';
    tokens[3] = '-'; // clear ep square to avoid invalid FEN when flipping turn
    final flippedChess = chess_lib.Chess();
    if (!flippedChess.load(tokens.join(' '))) return false;
    for (final m in flippedChess.generate_moves()) {
      if (chess_lib.Chess.algebraic(m.to) == square) return true;
    }
    return false;
  }

  /// Checks if playing `uci` from `fen` allows the opponent to capture our Queen
  /// or deliver mate-in-1 on the very next ply.
  ///
  /// Deliberately distinct from `chess_move_analysis.dart`'s
  /// `hangingPieceValueAfter` (general hanging-value-after-a-move check) —
  /// this is narrower (queen-only) and also covers mate-in-1, which that
  /// function doesn't. See docs/features/done/refactor_02_shared_chess_helpers.md
  /// for why these stay separate functions rather than being merged.
  static bool _hangsQueenOrAllowsMate(String fen, String uci) {
    final chess = chess_lib.Chess()..load(fen);
    final us = chess.turn;
    final moved = chess.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return true;

    for (final oppMove in chess.generate_moves()) {
      final targetSq = chess_lib.Chess.algebraic(oppMove.to);
      final targetPiece = chess.get(targetSq);
      if (targetPiece != null &&
          targetPiece.color == us &&
          targetPiece.type == chess_lib.PieceType.QUEEN) {
        return true; // Opponent can capture our Queen!
      }
      chess.make_move(oppMove);
      final isMate = chess.in_checkmate;
      chess.undo_move();
      if (isMate) return true; // Opponent has mate in 1!
    }
    return false;
  }

  /// Returns the number of distinct Mate-in-1 moves we would have if it were
  /// our turn again in [afterFen] (0 if none).
  static int _countMateIn1Threats(String afterFen, chess_lib.Color us) {
    final tokens = afterFen.split(' ');
    if (tokens.length < 6) return 0;
    tokens[1] = us == chess_lib.Color.WHITE ? 'w' : 'b';
    tokens[3] = '-';
    final nullMoveChess = chess_lib.Chess();
    if (!nullMoveChess.load(tokens.join(' '))) return 0;
    if (nullMoveChess.in_check) return 0;

    var count = 0;
    for (final m in nullMoveChess.generate_moves()) {
      nullMoveChess.make_move(m);
      final isMate = nullMoveChess.in_checkmate;
      nullMoveChess.undo_move();
      if (isMate) count++;
    }
    return count;
  }

  static String? _applyUciFen(String fen, String uci) {
    final chess = chess_lib.Chess()..load(fen);
    final moved = chess.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci[4],
    });
    return moved ? chess.fen : null;
  }

  /// Checks whether playing [uci] from [fen] is a safe cheese trap:
  /// - Must not hang our Queen or allow opponent Mate-in-1
  /// - Must not allow the opponent to capture the moved piece (or a high-value
  ///   piece) for free or with a lower-value piece in a way that ALSO refutes
  ///   our Mate-in-1 threat! (If capturing our sacrificed piece still walks
  ///   into Mate-in-1, it IS a valid cheese sacrifice!)
  static bool _isSafeCheeseTrap(String fen, String uci) {
    if (_hangsQueenOrAllowsMate(fen, uci)) return false;

    final before = chess_lib.Chess()..load(fen);
    final fromSq = uci.substring(0, 2);
    final toSq = uci.substring(2, 4);
    final movedPiece = before.get(fromSq);
    final capturedPiece = before.get(toSq);
    if (movedPiece == null) return false;
    final movedVal = pieceValue(movedPiece.type);
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

    // Check if the opponent can simply capture the piece we just moved to `toSq`
    // and simultaneously stop any immediate Mate-in-1.
    for (final oppMove in after.generate_moves()) {
      final oppTo = chess_lib.Chess.algebraic(oppMove.to);
      if (oppTo != toSq) continue;
      final oppFrom = chess_lib.Chess.algebraic(oppMove.from);
      final attacker = after.get(oppFrom);
      final attackerVal = attacker != null ? pieceValue(attacker.type) : 1;

      after.make_move(oppMove);
      // If capturing our piece walks straight into Mate-in-1, it's a true
      // sacrifice trap (e.g. Greek Gift / Legal's Mate)!
      final mateStillWorks = findImmediateMateIn1(after.fen) != null;
      // Check if we can recapture on `toSq`
      var canRecapture = false;
      for (final recap in after.generate_moves()) {
        if (chess_lib.Chess.algebraic(recap.to) == toSq) {
          canRecapture = true;
          break;
        }
      }
      after.undo_move();

      if (mateStillWorks) continue;

      // If opponent captures our moved piece and stops the mate:
      // - Bad if we can't recapture and we didn't just make an equal/winning capture
      if (!canRecapture && movedVal > capturedVal && movedVal >= 3) {
        return false;
      }
      // - Bad if a lower-value piece captures our piece (e.g. pawn takes Knight/Bishop/Rook)
      if (movedVal - capturedVal - attackerVal >= 2) {
        return false;
      }
    }
    return true;
  }

  /// Evaluates all legal opponent responses in [afterFen] and counts how many
  /// of them walk straight into a Mate-in-1 on our next turn.
  static ({
    int totalReplies,
    int matedReplies,
    int safeReplies,
    double matedRatio,
  })
  _analyzeOpponentMateSurvival(String afterFen) {
    final after = chess_lib.Chess()..load(afterFen);
    final oppMoves = after.generate_moves();
    if (oppMoves.isEmpty) {
      return (
        totalReplies: 0,
        matedReplies: 0,
        safeReplies: 0,
        matedRatio: 0.0,
      );
    }
    var mated = 0;
    for (final r in oppMoves) {
      after.make_move(r);
      final hasMate = findImmediateMateIn1(after.fen) != null;
      after.undo_move();
      if (hasMate) mated++;
    }
    final total = oppMoves.length;
    final safe = total - mated;
    return (
      totalReplies: total,
      matedReplies: mated,
      safeReplies: safe,
      matedRatio: mated / total,
    );
  }

  /// Counts how many of our legal moves in [after] attack squares within
  /// Chebyshev distance <= 1 of [enemyKingSq] (measuring battery concentration
  /// on f7/g7/h7 or f2/g2/h2).
  static int _countKingZoneAttackers(
    chess_lib.Chess after,
    chess_lib.Color us,
    String enemyKingSq,
  ) {
    final tokens = after.fen.split(' ');
    if (tokens.length < 6) return 0;
    tokens[1] = us == chess_lib.Color.WHITE ? 'w' : 'b';
    tokens[3] = '-';
    final ourTurnChess = chess_lib.Chess();
    if (!ourTurnChess.load(tokens.join(' '))) return 0;
    var count = 0;
    for (final m in ourTurnChess.generate_moves()) {
      final targetSq = chess_lib.Chess.algebraic(m.to);
      if (_chebyshevDist(targetSq, enemyKingSq) <= 1) {
        count++;
      }
    }
    return count;
  }

  static bool _allowsOpponentQueenTrade(
    chess_lib.Chess after,
    chess_lib.Color us,
  ) {
    for (final m in after.generate_moves()) {
      final fromSq = chess_lib.Chess.algebraic(m.from);
      final toSq = chess_lib.Chess.algebraic(m.to);
      final attacker = after.get(fromSq);
      final victim = after.get(toSq);
      if (attacker?.type == chess_lib.PieceType.QUEEN &&
          victim?.type == chess_lib.PieceType.QUEEN &&
          victim?.color == us) {
        return true;
      }
    }
    return false;
  }
}
