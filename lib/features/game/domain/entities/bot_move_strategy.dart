// Unified personality move-selection strategy — see
// docs/features/refactor_03_bot_strategy_pattern.md. Replaces dispatching
// on `state.personality.id` inline in `GameNotifier._pickBotMove` with one
// registry lookup; each personality's actual move-picking logic still lives
// where it always has (ScholarsMateHunterPolicy, PawnPusherPolicy,
// bot_style_policy.dart's Trickster/Defender scorers) — this file only
// adapts them to one common shape.
import '../repositories/chess_engine_repository.dart';
import '../usecases/pawn_pusher_policy.dart';
import '../usecases/scholars_mate_hunter_policy.dart';
import 'bot_style_policy.dart';
import 'chess_opening.dart';

/// Everything a personality's move-selection strategy needs. Deliberately
/// carries a `ChessEngineRepository` reference (not just a pre-fetched
/// candidate list) because personalities genuinely need different engine
/// calls — Aggressor wants `multiPv: 10, mateLimit: 8`, Trickster wants
/// `multiPv: 6` — not just different scoring over the same candidates.
///
/// `personalityId`/`ply`/`selectedOpening`/`mateSafetyEnabled`/`mateSafetyN`
/// were added in docs/features/refactor_04_bot_move_pipeline.md — they're
/// not needed by the per-personality strategies above, only by the
/// pipeline steps and decorator in `bot_move_pipeline.dart`, but living on
/// the one context object `GameNotifier` already builds per bot turn is
/// simpler than threading two context types through the pipeline.
class BotMoveContext {
  final String fen;
  final int elo;
  final ChessEngineRepository engine;
  final Map<String, int> positionCounts;
  final String personalityId;
  final int ply;
  final ChessOpening? selectedOpening;
  final bool mateSafetyEnabled;
  final int mateSafetyN;

  /// Called by a strategy that fetches a fresh MultiPV candidate list, so
  /// the caller can reuse the top candidate's score for later game-review
  /// computation without a second engine call — mirrors exactly what
  /// `_pickBotMove` used to write into `GameNotifier`'s `_fenEvalCache`
  /// inline. Optional: strategies that don't fetch candidates (or have
  /// nothing worth recording) simply don't call it. Takes the raw [fen];
  /// the caller applies its own key normalization (`GameReviewAnalyzer.fenKey`),
  /// which is presentation/review-layer concern, not domain logic.
  final void Function(String fen, int scoreCp)? recordEval;

  const BotMoveContext({
    required this.fen,
    required this.elo,
    required this.engine,
    required this.positionCounts,
    this.personalityId = '',
    this.ply = 0,
    this.selectedOpening,
    this.mateSafetyEnabled = false,
    this.mateSafetyN = 3,
    this.recordEval,
  });

  /// Same ELO-to-movetime curve every personality search has always used.
  int get moveTimeMs => (elo / 1.5).floor().clamp(400, 2000);
}

/// One personality's move-selection behavior. Returning null falls back to
/// [DefaultBotMoveStrategy] (e.g. no candidate matched the personality's
/// style, or it has nothing special to do for this move).
abstract class BotMoveStrategy {
  Future<String?> selectMove(BotMoveContext ctx);
}

/// Aggressor: immediate/forced mate detection, then
/// `ScholarsMateHunterPolicy`'s 3-phase fast-mate hunter over a wide
/// (multiPv 10, mate-limited to 8) candidate search.
class AggressorStrategy implements BotMoveStrategy {
  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(ctx.fen);
    if (mateIn1 != null) return mateIn1;

    final mateIn2 = ScholarsMateHunterPolicy.findForcedMateIn2(
      ctx.fen,
      ctx.positionCounts,
    );
    if (mateIn2 != null) return mateIn2;

    final candidates = await ctx.engine.getTopMoves(
      ctx.fen,
      movetimeMs: ctx.moveTimeMs,
      multiPv: 10,
      mateLimit: 8,
    );
    if (candidates.isNotEmpty) {
      ctx.recordEval?.call(ctx.fen, candidates.first.scoreCp);
    }
    final chosen = ScholarsMateHunterPolicy.selectMove(
      fen: ctx.fen,
      candidates: candidates,
      positionCounts: ctx.positionCounts,
    );
    return (chosen != null && chosen.isNotEmpty) ? chosen : null;
  }
}

/// Pawn Pusher: immediate mate detection, then `PawnPusherPolicy`'s
/// pawn-storm scorer over a multiPv 10 candidate search.
class PawnPusherStrategy implements BotMoveStrategy {
  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(ctx.fen);
    if (mateIn1 != null) return mateIn1;

    final candidates = await ctx.engine.getTopMoves(
      ctx.fen,
      movetimeMs: ctx.moveTimeMs,
      multiPv: 10,
    );
    if (candidates.isNotEmpty) {
      ctx.recordEval?.call(ctx.fen, candidates.first.scoreCp);
    }
    final chosen = PawnPusherPolicy.selectMove(
      fen: ctx.fen,
      candidates: candidates,
      positionCounts: ctx.positionCounts,
    );
    return (chosen != null && chosen.isNotEmpty) ? chosen : null;
  }
}

/// What every personality without a dedicated strategy (Martin, Strategist,
/// Crusher) gets, and what any strategy above falls back to when it returns
/// null: the engine's plain best move, retried against a wider candidate
/// list if the top choice would cause a draw/repeat a position.
class DefaultBotMoveStrategy implements BotMoveStrategy {
  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final bestMove = await ctx.engine.getBestMove(
      ctx.fen,
      movetimeMs: ctx.moveTimeMs,
    );
    if (bestMove.isEmpty || bestMove == '(none)') return bestMove;

    final causesDrawOrRepeat =
        ScholarsMateHunterPolicy.wouldCauseDraw(
          ctx.fen,
          bestMove,
          ctx.positionCounts,
        ) ||
        ScholarsMateHunterPolicy.wouldRepeatPosition(
          ctx.fen,
          bestMove,
          ctx.positionCounts,
        );
    if (!causesDrawOrRepeat) return bestMove;

    final candidates = await ctx.engine.getTopMoves(
      ctx.fen,
      movetimeMs: ctx.moveTimeMs,
      multiPv: 5,
    );
    for (final c in candidates) {
      if (c.mateIn != null && c.mateIn! < 0) continue;
      if (!ScholarsMateHunterPolicy.wouldCauseDraw(
            ctx.fen,
            c.uci,
            ctx.positionCounts,
          ) &&
          !ScholarsMateHunterPolicy.wouldRepeatPosition(
            ctx.fen,
            c.uci,
            ctx.positionCounts,
          )) {
        return c.uci;
      }
    }
    for (final c in candidates) {
      if (c.mateIn != null && c.mateIn! < 0) continue;
      if (!ScholarsMateHunterPolicy.wouldCauseDraw(
        ctx.fen,
        c.uci,
        ctx.positionCounts,
      )) {
        return c.uci;
      }
    }
    return bestMove;
  }
}

final DefaultBotMoveStrategy _defaultBotMoveStrategy = DefaultBotMoveStrategy();

/// Every personality with behavior beyond the default best-move + draw
/// avoidance. Martin, Strategist, and Crusher deliberately have no entry
/// here — they fall through to [_defaultBotMoveStrategy] via
/// [strategyForPersonalityId].
final Map<String, BotMoveStrategy> kBotMoveStrategies = {
  'aggressor': AggressorStrategy(),
  'pawn_pusher': PawnPusherStrategy(),
  'trickster': TricksterStylePolicy(),
  'defender': DefenderStylePolicy(),
};

/// Looks up [personalityId]'s strategy, or [DefaultBotMoveStrategy] if it
/// has none registered.
BotMoveStrategy strategyForPersonalityId(String personalityId) =>
    kBotMoveStrategies[personalityId] ?? _defaultBotMoveStrategy;
