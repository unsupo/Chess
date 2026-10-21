# Refactor Phase 3: Unify Personality Move Selection (Strategy Pattern)

**Status:** Planned — not built. Part of
[refactor_overview.md](refactor_overview.md), phase 3. Depends on phase 2
(shared helpers) being done first, since the adapters below call into
`chess_move_analysis.dart`'s now-consolidated functions.

## Problem

`GameNotifier._pickBotMove(fen, elo)` (`game_provider.dart:677-861`, 184
lines) picks the bot's move by checking `state.personality.id` against
string literals in sequence:

```dart
if (state.personality.id == 'aggressor') {
  // ~30 lines: mate-in-1, mate-in-2, getTopMoves(multiPv: 10, mateLimit: 8),
  // ScholarsMateHunterPolicy.selectMove(...)
}
if (state.personality.id == 'pawn_pusher') {
  // ~20 lines: mate-in-1, getTopMoves(multiPv: 10),
  // PawnPusherPolicy.selectMove(...)
}
final stylePolicy = styleForPersonalityId(state.personality.id); // trickster/defender
if (stylePolicy != null) {
  // ~25 lines: mate-in-1, getTopMoves(multiPv: 6), non-drawing filter,
  // stylePolicy.pickMove(...)
}
// fallback: getBestMove + draw-avoidance retry loop
```

Three personalities (`martin`, `strategist`, `crusher`) fall through to
the plain `getBestMove` fallback with no policy at all — that's already
correct Strategy-pattern behavior by omission (no-op case), it just
isn't expressed as one.

Adding a personality today means adding another `if` block to this
method, in a specific position relative to the others, duplicating the
"get candidates, filter non-drawing, pick" shape each time. The
`BotStylePolicy` interface (`bot_style_policy.dart`) already solves this
for Trickster/Defender — this phase extends it to cover all five
personality behaviors uniformly, including the "no special policy, just
call `getBestMove`" case.

## Proposed approach

### 1. One interface, context object instead of loose `(fen, candidates)`

`BotStylePolicy.pickMove(fen, candidates)` is too narrow — Aggressor and
Pawn Pusher need more than a candidate list (they need direct engine
access for `getTopMoves` with personality-specific `multiPv`/`mateLimit`,
and the position-repeat counts). Replace it with:

```dart
// lib/features/game/domain/entities/bot_move_strategy.dart
class BotMoveContext {
  final String fen;
  final int elo;
  final ChessEngineRepository engine;
  final Map<String, int> positionCounts;
  const BotMoveContext({
    required this.fen,
    required this.elo,
    required this.engine,
    required this.positionCounts,
  });
}

/// One personality's move-selection behavior. Returning null falls back
/// to `DefaultBotMoveStrategy` (plain getBestMove + draw-avoidance).
abstract class BotMoveStrategy {
  Future<String?> selectMove(BotMoveContext ctx);
}
```

This does pull `ChessEngineRepository` into the domain layer as a
dependency of a domain interface, which is new — today `domain/` only
holds pure-Dart logic. That's an intentional, narrow exception: the
*strategy* of "which engine calls to make and in what order" is exactly
what varies per personality (Aggressor wants `multiPv: 10, mateLimit:
8`; Trickster wants `multiPv: 6`), so the engine calls have to live
inside the strategy, not be hoisted out of it. `ChessEngineRepository`
is already an abstract interface with no Flutter dependency, so this
doesn't violate "domain has no Flutter imports" — it's domain depending
on another domain interface, which is fine.

### 2. Adapters for the existing policies

```dart
class AggressorStrategy implements BotMoveStrategy {
  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(ctx.fen);
    if (mateIn1 != null) return mateIn1;
    final mateIn2 = ScholarsMateHunterPolicy.findForcedMateIn2(ctx.fen, ctx.positionCounts);
    if (mateIn2 != null) return mateIn2;
    final candidates = await ctx.engine.getTopMoves(
      ctx.fen, movetimeMs: _moveTimeMs(ctx.elo), multiPv: 10, mateLimit: 8,
    );
    return ScholarsMateHunterPolicy.selectMove(
      fen: ctx.fen, candidates: candidates, positionCounts: ctx.positionCounts,
    );
  }
}

class PawnPusherStrategy implements BotMoveStrategy {
  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(ctx.fen);
    if (mateIn1 != null) return mateIn1;
    final candidates = await ctx.engine.getTopMoves(
      ctx.fen, movetimeMs: _moveTimeMs(ctx.elo), multiPv: 10,
    );
    return PawnPusherPolicy.selectMove(
      fen: ctx.fen, candidates: candidates, positionCounts: ctx.positionCounts,
    );
  }
}
```

`TricksterStylePolicy`/`DefenderStylePolicy` (today's `BotStylePolicy`
implementers) get the same treatment — wrap the existing `pickMove(fen,
candidates)` logic inside a `selectMove(ctx)` that fetches candidates
first, and fold today's `styleForPersonalityId`'s mate-in-1 + non-drawing
filter (currently duplicated inline in `_pickBotMove`, see phase 4) in
here too, so each strategy is fully self-contained. `_moveTimeMs` moves
from `GameNotifier` into this file as a shared top-level helper (or into
`BotMoveContext` as a computed getter) since every strategy needs it.

### 3. `DefaultBotMoveStrategy` — the "no personality quirks" case, made explicit

```dart
class DefaultBotMoveStrategy implements BotMoveStrategy {
  @override
  Future<String?> selectMove(BotMoveContext ctx) async {
    final bestMove = await ctx.engine.getBestMove(ctx.fen, movetimeMs: _moveTimeMs(ctx.elo));
    if (bestMove.isEmpty || bestMove == '(none)') return bestMove;
    if (!ScholarsMateHunterPolicy.wouldCauseDraw(ctx.fen, bestMove, ctx.positionCounts) &&
        !ScholarsMateHunterPolicy.wouldRepeatPosition(ctx.fen, bestMove, ctx.positionCounts)) {
      return bestMove;
    }
    // existing draw-avoidance retry loop moves here unchanged
  }
}
```

Martin, Strategist, and Crusher all map to this one strategy instance —
today they're implicitly handled by falling through every `if` in
`_pickBotMove`; after this phase they're an explicit registry entry like
everyone else.

### 4. Registry replaces the string-matching chain

```dart
final Map<String, BotMoveStrategy> kBotMoveStrategies = {
  'aggressor': AggressorStrategy(),
  'pawn_pusher': PawnPusherStrategy(),
  'trickster': TricksterStylePolicy(),
  'defender': DefenderStylePolicy(),
};
final _defaultStrategy = DefaultBotMoveStrategy();

BotMoveStrategy strategyForPersonalityId(String id) =>
    kBotMoveStrategies[id] ?? _defaultStrategy;
```

`styleForPersonalityId` (today's smaller registry, `bot_style_policy.dart`)
is superseded by this and removed.

## Decisions baked in as reasonable calls

1. `BotMoveContext` carries a `ChessEngineRepository` reference rather
   than strategies being handed pre-fetched candidates — see the
   rationale above (personalities genuinely need different `multiPv`/
   `mateLimit`, not just different scoring over the same candidate set).
2. A strategy returning `null` means "defer to `DefaultBotMoveStrategy`"
   (mirrors today's `BotStylePolicy.pickMove` null-fallback contract) —
   kept for the case where e.g. Trickster's candidate pool comes back
   empty.
3. `kBotMoveStrategies` is a plain top-level `Map`, not a class with a
   registration method — there's no use case yet for a plugin system
   where strategies register themselves at runtime; a literal map is
   the simplest thing that works and is trivially greppable to see every
   personality's strategy in one place.
4. This phase does **not** yet address the weak-play
   (`_blunderChance`/`_pickWorstMove`) or mate-safety
   (`_applyMateSafety`) logic that currently wraps around
   `_pickBotMove`'s personality branches — those become Decorators in
   phase 4, applied uniformly to whatever `BotMoveStrategy` the registry
   returns, rather than being part of the strategies themselves.

## Likely touched files

- `lib/features/game/domain/entities/bot_move_strategy.dart` — new
  (`BotMoveContext`, `BotMoveStrategy`, `DefaultBotMoveStrategy`,
  `AggressorStrategy`, `PawnPusherStrategy`, `kBotMoveStrategies`,
  `strategyForPersonalityId`).
- `lib/features/game/domain/entities/bot_style_policy.dart` — Trickster/
  Defender gain `selectMove(ctx)`; `styleForPersonalityId` removed (moved
  into the new registry above).
- `lib/features/game/presentation/providers/game_provider.dart` —
  `_pickBotMove` shrinks to building a `BotMoveContext` and calling
  `strategyForPersonalityId(state.personality.id).selectMove(ctx)`; the
  draw-avoidance retry loop, mate-in-1/mate-in-2 calls, and `_moveTimeMs`
  move out to the files above.
- `test/unit/bot_style_policy_test.dart` — update
  `styleForPersonalityId` references to `strategyForPersonalityId`/
  `kBotMoveStrategies`; assertions about which concrete type comes back
  for each id should be unchanged otherwise.
- New `test/unit/bot_move_strategy_test.dart` for
  `AggressorStrategy`/`PawnPusherStrategy`/`DefaultBotMoveStrategy`,
  using a fake `ChessEngineRepository` (same fakes already used in
  `game_notifier_test.dart`) — these three had no isolated unit tests
  before (only exercised indirectly through `GameNotifier`), so this is
  net-new coverage, not just moved coverage.

## Verification

Per `refactor_overview.md`'s checklist, plus: since `_pickBotMove`'s
*behavior* must be identical (same move chosen for the same input), the
existing `game_notifier_test.dart` tests that exercise bot replies for
each personality (if any exist by this point — add them before this
phase if not) are the real regression guard here, not just "tests still
pass in general."
