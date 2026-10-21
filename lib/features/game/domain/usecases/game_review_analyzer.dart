import 'dart:math' as math;
import 'package:chess/chess.dart' as chess_lib;
import 'scholars_mate_hunter_policy.dart';

/// Chess.com-style move classification tiers.
enum MoveClassification {
  brilliant(symbol: '!!', label: 'Brilliant'),
  great(symbol: '!', label: 'Great'),
  best(symbol: '★', label: 'Best'),
  book(symbol: '📖', label: 'Book'),
  good(symbol: '✓', label: 'Good'),
  inaccuracy(symbol: '?!', label: 'Inaccuracy'),
  mistake(symbol: '?', label: 'Mistake'),
  blunder(symbol: '??', label: 'Blunder');

  final String symbol;
  final String label;
  const MoveClassification({required this.symbol, required this.label});
}

class PlayerGameReview {
  /// Estimated single-game performance rating (Chess.com Game Review style).
  final int estimatedElo;

  /// Move accuracy percentage (`0.0` to `100.0`).
  final double accuracyPercent;

  /// Average centipawn loss across this player's moves.
  final double acpl;

  /// Number of moves analyzed for this player.
  final int moveCount;

  /// Count of each [MoveClassification] for this player.
  final Map<MoveClassification, int> classificationCounts;

  const PlayerGameReview({
    required this.estimatedElo,
    required this.accuracyPercent,
    required this.acpl,
    required this.moveCount,
    this.classificationCounts = const {},
  });

  int countOf(MoveClassification c) => classificationCounts[c] ?? 0;
}

class GameReviewSummary {
  final PlayerGameReview white;
  final PlayerGameReview black;

  /// Move classification for each ply index `0..sanMoves.length - 1`.
  final List<MoveClassification> plyClassifications;

  const GameReviewSummary({
    required this.white,
    required this.black,
    this.plyClassifications = const [],
  });

  PlayerGameReview playerReview({required bool humanIsWhite}) =>
      humanIsWhite ? white : black;

  PlayerGameReview botReview({required bool humanIsWhite}) =>
      humanIsWhite ? black : white;
}

/// Detects the ECO / human-readable opening name from the game's SAN move list.
class OpeningBookClassifier {
  static const List<(List<String>, String)> _openings = [
    (['e4', 'e5', 'Qh5', 'Nc6', 'Bc4', 'Nf6', 'Qxf7#'], "Scholar's Mate"),
    (['e4', 'e5', 'Qh5', 'Nc6', 'Bc4'], "Wayward Queen: Scholar's Mate Trap"),
    (['e4', 'e5', 'Qh5'], 'Wayward Queen Attack (Danvers Opening)'),
    (['e4', 'e5', 'Bc4', 'Nc6', 'Qh5'], "Bishop's Opening: Scholar's Mate Line"),
    (['e4', 'e5', 'Bc4', 'Nc6', 'Qf3'], "Bishop's Opening: Boi Variation"),
    (['e4', 'e5', 'Bc4'], "Bishop's Opening"),
    (['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Ng5'], 'Italian Game: Knight Attack (Fried Liver)'),
    (['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6'], 'Italian Game: Two Knights Defense'),
    (['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5'], 'Italian Game: Giuoco Piano'),
    (['e4', 'e5', 'Nf3', 'Nc6', 'Bc4'], 'Italian Game'),
    (['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'Ruy Lopez (Spanish Game)'),
    (['e4', 'e5', 'Nf3', 'Nc6', 'd4'], 'Scotch Game'),
    (['e4', 'e5', 'Nf3', 'Nf6'], "Petrov's Defense"),
    (['e4', 'e5', 'Nf3', 'd6'], 'Philidor Defense'),
    (['e4', 'e5', 'f4'], "King's Gambit"),
    (['e4', 'e5', 'Nc3'], 'Vienna Game'),
    (['e4', 'e5'], "King's Pawn Game"),
    (['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'], 'Sicilian Defense: Najdorf'),
    (['e4', 'c5', 'Nf3', 'Nc6'], 'Sicilian Defense: Old Sicilian'),
    (['e4', 'c5'], 'Sicilian Defense'),
    (['e4', 'e6'], 'French Defense'),
    (['e4', 'c6'], 'Caro-Kann Defense'),
    (['e4', 'd5'], 'Scandinavian Defense'),
    (['e4', 'd6'], 'Pirc Defense'),
    (['e4', 'g6'], 'Modern Defense'),
    (['e4'], "King's Pawn Opening"),
    (['d4', 'd5', 'c4', 'e6'], "Queen's Gambit Declined"),
    (['d4', 'd5', 'c4', 'dxc4'], "Queen's Gambit Accepted"),
    (['d4', 'd5', 'c4', 'c6'], 'Slav Defense'),
    (['d4', 'd5', 'c4'], "Queen's Gambit"),
    (['d4', 'd5', 'Bf4'], 'London System'),
    (['d4', 'Nf6', 'c4', 'g6'], "King's Indian Defense"),
    (['d4', 'Nf6', 'c4', 'e6'], 'Indian Game: East Indian'),
    (['d4', 'Nf6', 'Bf4'], 'London System'),
    (['d4', 'd5'], "Queen's Pawn Game"),
    (['d4', 'Nf6'], 'Indian Defense'),
    (['d4'], "Queen's Pawn Opening"),
    (['c4'], 'English Opening'),
    (['Nf3'], 'Zukertort Opening (Réti)'),
    (['f4'], "Bird's Opening"),
    (['g3'], "King's Fianchetto Opening"),
    (['b3'], 'Nimzowitsch-Larsen Attack'),
  ];

  /// Returns the longest matching opening name for [sanMoves], or `null` if
  /// no moves have been played or the line is not recognized.
  static String? detectOpeningName(List<String> sanMoves) {
    if (sanMoves.isEmpty) return null;
    for (final (prefix, name) in _openings) {
      if (sanMoves.length < prefix.length) continue;
      var matches = true;
      for (var i = 0; i < prefix.length; i++) {
        final cleanPlayed = sanMoves[i].replaceAll(RegExp(r'[+#?!]+$'), '');
        final cleanBook = prefix[i].replaceAll(RegExp(r'[+#?!]+$'), '');
        if (cleanPlayed != cleanBook) {
          matches = false;
          break;
        }
      }
      if (matches) return name;
    }
    return null;
  }

  /// Returns true if ply [plyIndex] (0-based) is still inside a known book prefix.
  static bool isBookPly(List<String> sanMoves, int plyIndex) {
    if (plyIndex < 0 || plyIndex >= sanMoves.length || plyIndex >= 6) {
      return false;
    }
    final sub = sanMoves.sublist(0, plyIndex + 1);
    for (final (prefix, _) in _openings) {
      if (prefix.length < sub.length) continue;
      var matches = true;
      for (var i = 0; i < sub.length; i++) {
        final cleanPlayed = sub[i].replaceAll(RegExp(r'[+#?!]+$'), '');
        final cleanBook = prefix[i].replaceAll(RegExp(r'[+#?!]+$'), '');
        if (cleanPlayed != cleanBook) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }
}

/// Computes post-game Accuracy %, Average Centipawn Loss (ACPL), Move
/// Classifications, and Chess.com-style Estimated Game Performance ELO.
class GameReviewAnalyzer {
  static String fenKey(String fen) =>
      fen.split(RegExp(r'\s+')).take(4).join(' ');

  /// Computes a [GameReviewSummary] from the game's [initialFen], [sanMoves],
  /// and a map of position evaluations [evalByFenKey] (where each value is the
  /// Stockfish centipawn score from the perspective of the side to move in
  /// that position).
  static GameReviewSummary analyze({
    required String initialFen,
    required List<String> sanMoves,
    required Map<String, int> evalByFenKey,
    required int botElo,
    required bool humanIsWhite,
  }) {
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(initialFen)['valid'] != true ||
        !chess.load(initialFen)) {
      final fallback = PlayerGameReview(
        estimatedElo: botElo.clamp(200, 2800),
        accuracyPercent: 0,
        acpl: 0,
        moveCount: 0,
      );
      return GameReviewSummary(white: fallback, black: fallback);
    }

    final whiteCpls = <double>[];
    final whiteAccs = <double>[];
    final whiteCounts = <MoveClassification, int>{};
    final blackCpls = <double>[];
    final blackAccs = <double>[];
    final blackCounts = <MoveClassification, int>{};
    final plyClassifications = <MoveClassification>[];

    for (var i = 0; i < sanMoves.length; i++) {
      final san = sanMoves[i];
      final moverIsWhite = chess.turn == chess_lib.Color.WHITE;
      final beforeKey = fenKey(chess.fen);
      final rawEvalBefore = evalByFenKey[beforeKey] ?? 0;
      final evalBeforeMover = rawEvalBefore.clamp(-1000, 1000).toDouble();

      if (!chess.move(san)) break;

      final double evalAfterMover;
      if (chess.in_checkmate) {
        evalAfterMover = 1000.0;
      } else if (chess.in_draw ||
          ScholarsMateHunterPolicy.isInsufficientMatingMaterial(chess.fen)) {
        evalAfterMover = 0.0;
      } else {
        final afterKey = fenKey(chess.fen);
        final rawEvalAfterOpp = evalByFenKey[afterKey] ?? (-rawEvalBefore);
        // Flip sign because rawEvalAfterOpp is from the opponent's perspective
        evalAfterMover = (-rawEvalAfterOpp).clamp(-1000, 1000).toDouble();
      }

      final cpl = math.max(0.0, evalBeforeMover - evalAfterMover);
      final cpGain = evalAfterMover - evalBeforeMover;
      final winBefore = _winPercentFromCp(evalBeforeMover);
      final winAfter = _winPercentFromCp(evalAfterMover);
      final winLoss = math.max(0.0, winBefore - winAfter);
      final moveAcc = _moveAccuracyFromWinLoss(winLoss);

      final classification = classifyMove(
        sanMoves: sanMoves,
        plyIndex: i,
        cpl: cpl,
        cpGain: cpGain,
        winLoss: winLoss,
        deliveredMate: chess.in_checkmate,
        gaveCheck: chess.in_check,
      );
      plyClassifications.add(classification);

      if (moverIsWhite) {
        whiteCpls.add(cpl);
        whiteAccs.add(moveAcc);
        whiteCounts[classification] = (whiteCounts[classification] ?? 0) + 1;
      } else {
        blackCpls.add(cpl);
        blackAccs.add(moveAcc);
        blackCounts[classification] = (blackCounts[classification] ?? 0) + 1;
      }
    }

    int whiteOutcome = 0;
    if (chess.in_checkmate) {
      whiteOutcome = chess.turn == chess_lib.Color.BLACK ? 1 : -1;
    }

    final whiteBaseElo = humanIsWhite
        ? botElo.clamp(500, 2400)
        : botElo.clamp(100, 2800);
    final blackBaseElo = humanIsWhite
        ? botElo.clamp(100, 2800)
        : botElo.clamp(500, 2400);

    final whiteReview = _buildPlayerReview(
      cpls: whiteCpls,
      accs: whiteAccs,
      counts: whiteCounts,
      baselineElo: whiteBaseElo,
      outcome: whiteOutcome,
    );
    final blackReview = _buildPlayerReview(
      cpls: blackCpls,
      accs: blackAccs,
      counts: blackCounts,
      baselineElo: blackBaseElo,
      outcome: -whiteOutcome,
    );

    return GameReviewSummary(
      white: whiteReview,
      black: blackReview,
      plyClassifications: plyClassifications,
    );
  }

  /// Classifies a single move into Chess.com-style categories (`Brilliant !!`,
  /// `Great !`, `Best ★`, `Book 📖`, `Good ✓`, `Inaccuracy ?!`, `Mistake ?`,
  /// `Blunder ??`).
  static MoveClassification classifyMove({
    required List<String> sanMoves,
    required int plyIndex,
    required double cpl,
    required double cpGain,
    required double winLoss,
    required bool deliveredMate,
    required bool gaveCheck,
  }) {
    if (deliveredMate) {
      return cpGain >= 200 ? MoveClassification.great : MoveClassification.best;
    }
    if (winLoss >= 20.0 || cpl >= 280.0) {
      return MoveClassification.blunder;
    }
    if (winLoss >= 10.0 || cpl >= 130.0) {
      return MoveClassification.mistake;
    }
    if (winLoss >= 5.0 || cpl >= 60.0) {
      return MoveClassification.inaccuracy;
    }
    if (OpeningBookClassifier.isBookPly(sanMoves, plyIndex) && cpl <= 35.0) {
      return MoveClassification.book;
    }
    if (cpl <= 10.0 && cpGain >= 180.0 && gaveCheck) {
      return MoveClassification.brilliant;
    }
    if (cpl <= 15.0 && cpGain >= 90.0) {
      return MoveClassification.great;
    }
    if (cpl <= 18.0 || winLoss <= 1.2) {
      return MoveClassification.best;
    }
    return MoveClassification.good;
  }

  static PlayerGameReview _buildPlayerReview({
    required List<double> cpls,
    required List<double> accs,
    required Map<MoveClassification, int> counts,
    required int baselineElo,
    required int outcome,
  }) {
    if (accs.isEmpty) {
      return PlayerGameReview(
        estimatedElo: baselineElo,
        accuracyPercent: 0,
        acpl: 0,
        moveCount: 0,
        classificationCounts: counts,
      );
    }

    final avgAcc =
        (accs.reduce((a, b) => a + b) / accs.length).clamp(0.0, 100.0);
    final avgCpl = cpls.reduce((a, b) => a + b) / cpls.length;

    final pureAccRating =
        250.0 + 2250.0 * math.pow(avgAcc / 100.0, 2.2) - avgCpl * 1.2;

    final expectedAcc = (46.0 + baselineElo / 55.0).clamp(50.0, 94.0);
    final outcomeShift = outcome * 85.0;
    final baselineAdjusted =
        baselineElo + outcomeShift + (avgAcc - expectedAcc) * 19.0;

    final rawElo = 0.30 * pureAccRating + 0.70 * baselineAdjusted;
    final roundedElo = ((rawElo / 10.0).round() * 10).clamp(100, 2900);

    return PlayerGameReview(
      estimatedElo: roundedElo,
      accuracyPercent: avgAcc,
      acpl: avgCpl,
      moveCount: accs.length,
      classificationCounts: counts,
    );
  }

  /// Standard centipawn -> win probability % curve (0..100) for the side with
  /// advantage `cp`.
  static double winPercentFromWhiteCp(int whiteCp) {
    return _winPercentFromCp(whiteCp.clamp(-1200, 1200).toDouble());
  }

  static double _winPercentFromCp(double cp) {
    return 50.0 + 50.0 * (2.0 / (1.0 + math.exp(-0.00368208 * cp)) - 1.0);
  }

  static double _moveAccuracyFromWinLoss(double winLoss) {
    final raw = 103.1668 * math.exp(-0.04354 * winLoss) - 3.1669;
    return raw.clamp(0.0, 100.0);
  }
}
