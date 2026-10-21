// Personality-driven move selection among a MultiPV candidate list, for
// personalities that aren't already handled by a dedicated policy (the
// Aggressor's fast-mate/trap hunting lives in `ScholarsMateHunterPolicy`,
// the Pawn Pusher's in `PawnPusherPolicy`). See docs/features/done/bot_play_styles.md
// for the Trickster/Defender design and scoring formulas implemented below.
import 'package:chess/chess.dart' as chess_lib;
import '../usecases/scholars_mate_hunter_policy.dart';
import 'bot_move_strategy.dart';
import 'chess_move_analysis.dart';
import 'engine_move_candidate.dart';

/// Picks a move from a set of engine-ranked candidates according to a
/// personality's playing style. Returning null falls back to the engine's
/// plain best move (e.g. there were no candidates to choose from).
abstract class BotStylePolicy {
  String? pickMove(String fen, List<EngineMoveCandidate> candidates);
}

/// Wraps any [BotStylePolicy] (pure: fen + already-fetched candidates in, a
/// move out) into a full [BotMoveStrategy] by doing the engine fetch and
/// draw-avoidance filtering every scored-candidate personality needs
/// identically — see docs/features/done/refactor_03_bot_strategy_pattern.md.
/// Subclasses only implement [pickMove]; this shared base keeps
/// TricksterStylePolicy and DefenderStylePolicy from each duplicating the
/// same wrapper logic.
abstract class CandidateScoringStrategy
    implements BotStylePolicy, BotMoveStrategy {
  /// How many candidates to request from the engine — override per style
  /// (Trickster/Defender both use the same default today).
  int get multiPv => 6;

  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(ctx.fen);
    if (mateIn1 != null) return mateIn1;

    final candidates = await ctx.engine.getTopMoves(
      ctx.fen,
      movetimeMs: ctx.moveTimeMs,
      multiPv: multiPv,
    );
    if (candidates.isNotEmpty) {
      ctx.recordEval?.call(ctx.fen, candidates.first.scoreCp);
    }
    final nonDrawing = candidates
        .where(
          (c) =>
              !ScholarsMateHunterPolicy.wouldCauseDraw(
                ctx.fen,
                c.uci,
                ctx.positionCounts,
              ) &&
              !ScholarsMateHunterPolicy.wouldRepeatPosition(
                ctx.fen,
                c.uci,
                ctx.positionCounts,
              ),
        )
        .toList();
    final chosen = pickMove(
      ctx.fen,
      nonDrawing.isNotEmpty ? nonDrawing : candidates,
    );
    return (chosen != null && chosen.isNotEmpty) ? chosen : null;
  }
}

/// A comparable "how good is this for the side to move" value that folds
/// mate scores and plain centipawn scores into one scale, so tolerance-band
/// filtering works the same for either.
int _comparableScore(EngineMoveCandidate c) {
  final mateIn = c.mateIn;
  if (mateIn == null) return c.scoreCp;
  return mateIn > 0 ? 100000 - mateIn : -100000 - mateIn;
}

/// Candidates within [toleranceCp] of the best-eval candidate in the list —
/// never pick something objectively worse than that just to "be in
/// character".
List<EngineMoveCandidate> _withinTolerance(
  List<EngineMoveCandidate> candidates,
  int toleranceCp,
) {
  if (candidates.isEmpty) return candidates;
  final best = candidates.map(_comparableScore).reduce((a, b) => a > b ? a : b);
  return candidates
      .where((c) => best - _comparableScore(c) <= toleranceCp)
      .toList();
}

/// Picks the candidate with the highest style [score], breaking ties by
/// original engine rank (first candidate in the input list wins ties).
String? _pickHighestScoring(
  List<EngineMoveCandidate> pool,
  int Function(EngineMoveCandidate) score,
) {
  if (pool.isEmpty) return null;
  var best = pool.first;
  var bestScore = score(best);
  for (final c in pool.skip(1)) {
    final s = score(c);
    if (s > bestScore) {
      best = c;
      bestScore = s;
    }
  }
  return best.uci;
}

/// Net material balance (mover minus opponent) on the board in [fen].
/// Comparing this across candidates — rather than just the mover's own
/// piece count, which a mover's own move can never reduce on its own — is
/// what lets a capture-foregoing "trick" move register as a relative
/// sacrifice next to the engine's top (often capture-grabbing) choice.
int _netMaterial(String fen, chess_lib.Color mover) {
  final opponent = mover == chess_lib.Color.WHITE
      ? chess_lib.Color.BLACK
      : chess_lib.Color.WHITE;
  return materialFor(fen, mover) - materialFor(fen, opponent);
}

/// Maximize "tricks": forks, checks/discovered checks, and sound-but-
/// unobvious sacrifices.
class TricksterStylePolicy extends CandidateScoringStrategy {
  static const toleranceCp = 100;

  @override
  String? pickMove(String fen, List<EngineMoveCandidate> candidates) {
    final pool = _withinTolerance(candidates, toleranceCp);
    if (pool.isEmpty) return null;

    final probe = chess_lib.Chess();
    probe.load(fen);
    final moverColor = probe.turn;
    final topAnalysis = MoveAnalysis.of(fen, candidates.first.uci);
    final topNetMaterial = _netMaterial(topAnalysis.resultingFen, moverColor);

    int score(EngineMoveCandidate c) {
      final analysis = MoveAnalysis.of(fen, c.uci);
      var s = 0;
      if (movesCreatesFork(fen, c.uci)) s += 40;
      if (analysis.isCheck) s += 25;
      final netMaterial = _netMaterial(analysis.resultingFen, moverColor);
      if (netMaterial < topNetMaterial) s += 20;
      return s;
    }

    return _pickHighestScoring(pool, score);
  }
}

/// Fortress/never-drop-a-piece: heavily penalize candidates that leave a
/// bot piece hanging; small bonuses for trading down while even-or-ahead
/// and for castling.
class DefenderStylePolicy extends CandidateScoringStrategy {
  static const toleranceCp = 50;

  @override
  String? pickMove(String fen, List<EngineMoveCandidate> candidates) {
    final pool = _withinTolerance(candidates, toleranceCp);
    if (pool.isEmpty) return null;

    final probe = chess_lib.Chess();
    probe.load(fen);
    final moverColor = probe.turn;
    final opponentColor = moverColor == chess_lib.Color.WHITE
        ? chess_lib.Color.BLACK
        : chess_lib.Color.WHITE;
    final ownMaterialBefore = materialFor(fen, moverColor);
    final opponentMaterialBefore = materialFor(fen, opponentColor);

    int score(EngineMoveCandidate c) {
      final analysis = MoveAnalysis.of(fen, c.uci);
      var s = 0;
      s -= 200 * hangingPieceValueAfter(fen, c.uci);
      if (analysis.capturedValue > 0 &&
          ownMaterialBefore >= opponentMaterialBefore) {
        s += 10;
      }
      if (analysis.isCastle) s += 10;
      return s;
    }

    return _pickHighestScoring(pool, score);
  }
}
