// Bot move selection, structured as a Chain of Responsibility (opening
// book, then weak-play degradation, then the personality strategy) wrapped
// in a Decorator (mate safety) — see
// docs/features/done/refactor_04_bot_move_pipeline.md. `GameNotifier._pickBotMove`
// and `_applyMateSafety` used to express this ordering only implicitly, by
// which branch ran first in one long method; this file makes the ordering
// itself a visible, reorderable list.
import 'dart:math' show Random;
import 'package:chess/chess.dart' as chess_lib;
import '../usecases/scholars_mate_hunter_policy.dart';
import 'bot_move_strategy.dart';
import 'chess_move_analysis.dart' show applyUciToFen;

/// One link in the bot-move chain. Returns a chosen move, or null to pass
/// to the next step.
abstract class BotMoveStep {
  Future<String?> tryHandle(BotMoveContext ctx);
}

/// While an opening is selected and the stored line hasn't run out yet,
/// play the scripted book reply — bypasses weak play and the personality
/// strategy entirely, same as `_pickBotMove`'s old top-of-method check.
class OpeningBookStep implements BotMoveStep {
  @override
  Future<String?> tryHandle(BotMoveContext ctx) async {
    final opening = ctx.selectedOpening;
    if (opening == null || ctx.ply >= opening.uciMoves.length) return null;
    return opening.uciMoves[ctx.ply];
  }
}

// Stockfish's `Skill Level` bottoms out at ~1300 real playing strength even
// at its own minimum (see docs/GOTCHAS.md). Below 1000 ELO, blend in two
// increasingly common substitutes for the engine's real choice: a uniformly
// random legal move ("blunder"), and, further down, the worst move out of a
// small sample ("trying to lose as fast as possible"). The two bands meet
// at 250 (50%/0%) so the transition is continuous, not a jump.
const _worstMoveThreshold = 250;

double _blunderChance(int elo) {
  if (elo >= 1000) return 0;
  return ((1000 - elo) / (1000 - _worstMoveThreshold)).clamp(0.0, 1.0) * 0.5;
}

double _worstMoveChance(int elo) {
  if (elo >= _worstMoveThreshold) return 0;
  return (1 - elo / _worstMoveThreshold).clamp(0.0, 1.0);
}

/// Below 1000 ELO, a random roll may substitute a uniformly-random legal
/// move or deliberately the worst-evaluated move from a small sample,
/// regardless of which personality is active — moved verbatim from
/// `GameNotifier`'s old inline logic.
class WeakPlayStep implements BotMoveStep {
  final Random _random;
  WeakPlayStep([Random? random]) : _random = random ?? Random();

  @override
  Future<String?> tryHandle(BotMoveContext ctx) async {
    final roll = _random.nextDouble();
    if (roll < _worstMoveChance(ctx.elo)) {
      return _pickWorstMove(ctx);
    }
    if (roll < _worstMoveChance(ctx.elo) + _blunderChance(ctx.elo)) {
      return _pickRandomLegalMove(ctx);
    }
    return null;
  }

  /// Evaluates a small random sample of legal moves and returns whichever
  /// leaves the bot worst off. Sampling (not every legal move) keeps this
  /// from taking seconds in the opening, where there are 20+ legal moves;
  /// "worst of ~5" is still a clearly self-destructive choice almost all
  /// the time without the latency of exhaustively checking every option.
  Future<String> _pickWorstMove(BotMoveContext ctx) async {
    final chess = chess_lib.Chess()..load(ctx.fen);
    final moves = chess.generate_moves()..shuffle(_random);
    if (moves.isEmpty) return '(none)';

    String worstUci = '';
    int? worstEvalForOpponent;
    for (final m in moves.take(5)) {
      final from = chess_lib.Chess.algebraic(m.from);
      final to = chess_lib.Chess.algebraic(m.to);
      final promo = m.promotion != null ? m.promotion!.name : '';
      final uci = '$from$to$promo';
      final afterFen = applyUciToFen(ctx.fen, uci);
      // evaluateFen is from the perspective of the side to move in
      // afterFen — i.e. the opponent. The higher that is, the worse this
      // move was for the bot.
      final evalForOpponent = await ctx.engine.evaluateFen(afterFen);
      if (worstEvalForOpponent == null ||
          evalForOpponent > worstEvalForOpponent) {
        worstEvalForOpponent = evalForOpponent;
        worstUci = uci;
      }
    }
    return worstUci;
  }

  String? _pickRandomLegalMove(BotMoveContext ctx) {
    final chess = chess_lib.Chess()..load(ctx.fen);
    final moves = chess.generate_moves();
    if (moves.isEmpty) return null;

    final nonDrawing = moves.where((m) {
      final uci =
          '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';
      return !ScholarsMateHunterPolicy.wouldCauseDraw(
            ctx.fen,
            uci,
            ctx.positionCounts,
          ) &&
          !ScholarsMateHunterPolicy.wouldRepeatPosition(
            ctx.fen,
            uci,
            ctx.positionCounts,
          );
    }).toList();
    var pool = nonDrawing.isNotEmpty ? nonDrawing : moves;
    // If Pawn Pusher blunders at low ELO, still prefer pushing a random pawn!
    if (ctx.personalityId == 'pawn_pusher') {
      final pawnPool = pool
          .where((m) => m.piece == chess_lib.PieceType.PAWN)
          .toList();
      if (pawnPool.isNotEmpty) {
        pool = pawnPool;
      }
    }
    final m = pool[_random.nextInt(pool.length)];
    final from = chess_lib.Chess.algebraic(m.from);
    final to = chess_lib.Chess.algebraic(m.to);
    final promo = m.promotion != null ? m.promotion!.name : '';
    return '$from$to$promo';
  }
}

/// Defers to the registered `BotMoveStrategy` for `ctx.personalityId`,
/// which itself falls back to `DefaultBotMoveStrategy` when it has nothing
/// special to do — see docs/features/done/refactor_03_bot_strategy_pattern.md.
class PersonalityStrategyStep implements BotMoveStep {
  @override
  Future<String?> tryHandle(BotMoveContext ctx) async {
    final chosen = await strategyForPersonalityId(
      ctx.personalityId,
    ).selectMove(ctx);
    if (chosen != null && chosen.isNotEmpty) return chosen;
    return await DefaultBotMoveStrategy().selectMove(ctx);
  }
}

/// Runs each step in order; the first one to return a non-null move wins.
/// The order of `steps` **is** the design — today's "opening book beats
/// weak play beats personality" ordering is this list, not something only
/// discoverable by reading a long method top to bottom.
class BotMovePipeline {
  final List<BotMoveStep> steps;
  const BotMovePipeline(this.steps);

  Future<String> selectMove(BotMoveContext ctx) async {
    for (final step in steps) {
      final move = await step.tryHandle(ctx);
      if (move != null) return move;
    }
    // Unreachable in practice: PersonalityStrategyStep always resolves to
    // at least DefaultBotMoveStrategy, which returns '(none)' rather than
    // null when the engine has nothing to play. Kept as a safe default.
    return '(none)';
  }
}

final kDefaultBotMovePipeline = BotMovePipeline([
  OpeningBookStep(),
  WeakPlayStep(),
  PersonalityStrategyStep(),
]);

/// Wraps a pipeline's chosen move: if mate safety is on and that move hands
/// the human a forced mate within `ctx.mateSafetyN` plies, substitutes the
/// engine's own straightforward best move instead. Doesn't fit the chain —
/// it needs to see what was *chosen* first, which a `BotMoveStep` can't see
/// (a step only ever gets the context, never a previous step's result) —
/// moved verbatim from `GameNotifier._applyMateSafety`.
///
/// Best-effort single retry, not a guarantee: in a position where literally
/// every legal move allows a short mate, the fallback can still be unsafe,
/// and this doesn't re-check it. The mate search always runs at full engine
/// strength regardless of bot difficulty (same reasoning as the
/// anti-blunder shield — see GOTCHAS #14), since the whole point is "no
/// matter how weak" the bot is.
class MateSafetyDecorator {
  final BotMovePipeline inner;
  const MateSafetyDecorator(this.inner);

  Future<String> selectMove(BotMoveContext ctx) async {
    final chosen = await inner.selectMove(ctx);
    if (!ctx.mateSafetyEnabled || chosen == '(none)' || chosen.isEmpty) {
      return chosen;
    }
    final n = ctx.mateSafetyN;
    final afterCandidate = applyUciToFen(ctx.fen, chosen);
    final humanMateIn = await ctx.engine.getMateDistance(
      afterCandidate,
      movetimeMs: (n * 200).clamp(300, 3000),
    );
    final isUnsafe = humanMateIn != null && humanMateIn > 0 && humanMateIn <= n;
    if (!isUnsafe) return chosen;
    return ctx.engine.getBestMove(ctx.fen, movetimeMs: ctx.moveTimeMs);
  }
}
