# Refactor Phase 4: Bot Move Pipeline as Chain of Responsibility + Decorator

**Status:** Built, matching this plan closely. Two implementation notes
beyond the sketch below:

1. `MateSafetyDecorator.selectMove` guards on the chosen move being
   `'(none)'`/empty *before* calling `getMateDistance` — the sketch's
   `if (!ctx.mateSafetyEnabled) return chosen;` early-out doesn't cover
   that case, and `applyUciToFen(ctx.fen, '(none)')` would throw.
   `_playBotReply`'s old call order (`_applyMateSafety` was only ever
   invoked after checking `rawUci != '(none)'`) made this implicit before;
   it's now an explicit guard in the decorator itself.
2. `MateSafetyDecorator`'s `getMateDistance` call passes
   `movetimeMs: (n * 200).clamp(300, 3000)` (verbatim from the old
   `_applyMateSafety`) rather than the sketch's bare call with no
   `movetimeMs` argument — dropping that would have silently shortened
   the mate search for small `mateSafetyN` values.

`GameNotifier` gained a small `_botMoveContext(fen, elo)` builder (not in
the original sketch) so `_playBotReply` doesn't repeat the same six-field
`BotMoveContext(...)` construction inline.

## Problem

After phase 3, `_pickBotMove` still isn't just "look up a strategy and
call it" — three more concerns are layered around the personality
dispatch, today as inlined logic at specific points in the method:

1. **Opening-book override** (`game_provider.dart`, top of
   `_pickBotMove`): if `state.selectedOpening != null` and the current
   ply is still inside the stored line, play the scripted move —
   bypasses weak-play *and* the personality strategy entirely.
2. **Weak-play degradation** (`_blunderChance`/`_worstMoveChance`/
   `_pickWorstMove`, currently rolled *before* the personality check):
   below 1000 ELO, a random roll may substitute a uniformly-random legal
   move or deliberately the worst-evaluated move from a small sample,
   regardless of which personality is active.
3. **Mate safety** (`_applyMateSafety`, applied in `_playBotReply` *after*
   `_pickBotMove` returns): if the chosen move allows the opponent a
   forced mate within `mateSafetyN` plies, substitute the engine's own
   best move instead.

These three are structurally different from "personality strategy" —
they're not properties of a personality, they're modifiers that apply
*regardless of* which personality is active. Today that's true in
practice (the weak-play roll is explicitly commented "apply to all
personalities") but it's not visible as a design — a reader has to trace
through `_pickBotMove` and `_playBotReply` to discover that mate safety
wraps the whole thing while weak play is a short-circuit near the top.

## Proposed approach

### Chain of Responsibility for the "does something override the personality's move?" question

```dart
// lib/features/game/domain/entities/bot_move_pipeline.dart
abstract class BotMoveStep {
  /// Returns a chosen move, or null to pass to the next step.
  Future<String?> tryHandle(BotMoveContext ctx);
}

class OpeningBookStep implements BotMoveStep {
  @override
  Future<String?> tryHandle(BotMoveContext ctx) async {
    final opening = ctx.selectedOpening;
    if (opening == null || ctx.ply >= opening.uciMoves.length) return null;
    return opening.uciMoves[ctx.ply];
  }
}

class WeakPlayStep implements BotMoveStep {
  final Random _random;
  WeakPlayStep([Random? random]) : _random = random ?? Random();

  @override
  Future<String?> tryHandle(BotMoveContext ctx) async {
    final roll = _random.nextDouble();
    if (roll < _worstMoveChance(ctx.elo)) return _pickWorstMove(ctx);
    if (roll < _worstMoveChance(ctx.elo) + _blunderChance(ctx.elo)) {
      return _pickRandomLegalMove(ctx); // today's inline blunder-roll branch
    }
    return null; // not weakened this turn — fall through to the personality
  }
  // _blunderChance/_worstMoveChance/_pickWorstMove/_pickRandomLegalMove
  // move here verbatim from GameNotifier.
}

class PersonalityStrategyStep implements BotMoveStep {
  @override
  Future<String?> tryHandle(BotMoveContext ctx) =>
      strategyForPersonalityId(ctx.personalityId).selectMove(ctx);
}
```

```dart
class BotMovePipeline {
  final List<BotMoveStep> steps;
  const BotMovePipeline(this.steps);

  Future<String> selectMove(BotMoveContext ctx) async {
    for (final step in steps) {
      final move = await step.tryHandle(ctx);
      if (move != null) return move;
    }
    return '(none)'; // steps always include PersonalityStrategyStep, which
                      // itself falls back to DefaultBotMoveStrategy — this
                      // return is unreachable in practice, kept as a safe default.
  }
}

final kDefaultBotMovePipeline = BotMovePipeline([
  OpeningBookStep(),
  WeakPlayStep(),
  PersonalityStrategyStep(),
]);
```

The order of this list **is** the design — today's implicit "opening
book beats weak play beats personality" ordering becomes a visible,
reorderable list instead of something only discoverable by reading
`_pickBotMove` top to bottom.

### Decorator for mate safety

Mate safety doesn't fit the "does this override the move" shape — it
needs to see what the pipeline *chose* first, then conditionally
replace it. That's a Decorator around the whole pipeline, not another
step in the chain:

```dart
class MateSafetyDecorator {
  final BotMovePipeline inner;
  const MateSafetyDecorator(this.inner);

  Future<String> selectMove(BotMoveContext ctx) async {
    final chosen = await inner.selectMove(ctx);
    if (!ctx.mateSafetyEnabled) return chosen;
    final resultingFen = applyUciToFen(ctx.fen, chosen);
    final mateIn = await ctx.engine.getMateDistance(resultingFen);
    if (mateIn == null || mateIn > ctx.mateSafetyN) return chosen;
    // today's _applyMateSafety fallback: substitute the engine's own best move
    return ctx.engine.getBestMove(ctx.fen, movetimeMs: _moveTimeMs(ctx.elo));
  }
}
```

`GameNotifier._playBotReply` ends up calling one thing:

```dart
final botUci = await MateSafetyDecorator(kDefaultBotMovePipeline).selectMove(ctx);
```

(Constructing a new `MateSafetyDecorator` per call is fine — it's a
stateless wrapper around the shared, stateless `kDefaultBotMovePipeline`
singleton; no need to cache the decorator instance.)

### `BotMoveContext` grows

Phase 3's `BotMoveContext` (`fen`, `elo`, `engine`, `positionCounts`)
gains the fields these steps/decorator need:

```dart
class BotMoveContext {
  final String fen;
  final int elo;
  final ChessEngineRepository engine;
  final Map<String, int> positionCounts;
  final String personalityId;
  final int ply;                  // state.sanMoves.length at selection time
  final ChessOpening? selectedOpening;
  final bool mateSafetyEnabled;
  final int mateSafetyN;
  const BotMoveContext({ /* ... */ });
}
```

`GameNotifier` builds one `BotMoveContext` per bot turn (in
`_playBotReply`, where `state` is already fully in scope) instead of
passing `fen`/`elo` as loose parameters through `_pickBotMove`.

## Decisions baked in as reasonable calls

1. Opening-book and weak-play are modeled as **Chain of Responsibility**
   (each step either fully decides the move or declines), while mate
   safety is a **Decorator** (it needs the chain's output as input,
   which a chain step can't express — a step only ever sees the
   context, never a previous step's result). This isn't a stylistic
   choice, it's the only shape that matches how `_applyMateSafety`
   already behaves today (post-processing after a move is chosen).
2. `kBotMovePipeline`/`kDefaultBotMovePipeline` as a module-level
   `const`/`final` singleton, same pattern as phase 3's
   `kBotMoveStrategies` — no per-instance configuration needed yet, and
   introducing one before anything needs it would be speculative.
3. `WeakPlayStep` takes an optional `Random` in its constructor
   specifically so tests can inject a seeded/fake `Random` and assert
   deterministic branch selection — today's `_blunderChance`/
   `_worstMoveChance` tests (if any exist) likely work around
   `GameNotifier`'s private, unseeded `Random()` field; this is a
   genuine testability improvement, not just a move.
4. Reordering the chain (e.g. "should weak play affect opening-book
   moves too?") is explicitly out of scope — this phase preserves
   today's exact ordering and behavior; reordering is a product
   decision for a separate conversation, not something to sneak into a
   structural refactor.

## Likely touched files

- `lib/features/game/domain/entities/bot_move_pipeline.dart` — new
  (`BotMoveStep`, `OpeningBookStep`, `WeakPlayStep`,
  `PersonalityStrategyStep`, `BotMovePipeline`,
  `kDefaultBotMovePipeline`, `MateSafetyDecorator`).
- `lib/features/game/domain/entities/bot_move_strategy.dart` — extend
  `BotMoveContext` with `personalityId`, `ply`, `selectedOpening`,
  `mateSafetyEnabled`, `mateSafetyN`.
- `lib/features/game/presentation/providers/game_provider.dart` —
  `_pickBotMove`/`_applyMateSafety`/`_blunderChance`/`_worstMoveChance`/
  `_pickWorstMove` are deleted; `_playBotReply` builds a `BotMoveContext`
  and calls `MateSafetyDecorator(kDefaultBotMovePipeline).selectMove(ctx)`.
- `test/unit/game_notifier_test.dart` — weak-play/mate-safety assertions
  that currently exercise `GameNotifier` directly can mostly stay as
  black-box behavior tests (unchanged); any test reaching into
  `GameNotifier`'s private weak-play fields needs to move to a new
  `test/unit/bot_move_pipeline_test.dart` instead, testing
  `WeakPlayStep`/`MateSafetyDecorator` directly with a seeded `Random`
  and fake engine.

## Verification

Per `refactor_overview.md`'s checklist. This phase is the first one
with real behavioral surface area (weak-play randomness, mate-safety
substitution) — before merging, manually re-run the same live
verification done when these features were first built (script a known
queen-hang/mate-in-N position through the debug VM extension, confirm
the pipeline still rejects/substitutes exactly as it did before the
refactor).
