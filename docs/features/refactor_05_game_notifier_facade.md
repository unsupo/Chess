# Refactor Phase 5: `GameNotifier` as a Facade

**Status:** Planned — not built. Part of
[refactor_overview.md](refactor_overview.md), phase 5 (last, highest
risk). Depends on phases 1-4 — bot move selection must already be
extracted (phases 3-4) before this phase, since `_playBotReply` is one
of the methods being thinned out here too.

## Problem

After phases 1-4, `GameNotifier` still owns everything that isn't bot
move selection:

- **PGN**: `GameState.pgn` getter (header/move-list formatting,
  `game_provider.dart:365-421`), `_parsePgn` (PGN → `GameState`), the
  private `_findSanMove`/`_findUciMove` (near-duplicate FEN-diff-to-move
  helpers, see phase 2's note deferring their merge to this phase),
  `_applyUciWithSan`.
- **Clock**: `tickClock`, `_syncClockTimer`, the `Timer?` field, timeout
  detection and `timeoutWinner` assignment.
- **Game review**: `_computeGameReview`, the `_fenEvalCache` map and its
  lifecycle (seeded in the constructor, grown throughout the game, read
  by `GameReviewAnalyzer.analyze`).
- **Crowns**: `_awardCrownsIfHumanWon`.
- **Debug tooling**: `_registerDebugMoveExtension` (`dart:developer` VM
  service extension).
- Plus the actual state-coordination work a `StateNotifier` should be
  doing: `onUserMove`, `newGame`, `loadFen`, `flipBoard`, the simple
  `setX` setters, `stepBack`/`stepForward`/`selectPly`.

None of this is *wrong* — each piece works and is tested — but it means
`GameNotifier` is the one class that has to be understood (and risked
breaking) to touch PGN handling, clock behavior, game review, *or* core
move flow. This phase extracts the first three into standalone,
independently-testable collaborators, leaving `GameNotifier` as a
Facade: it still exposes the same public API (`onUserMove`, `newGame`,
`setPersonality`, ...) so `game_page.dart` doesn't change at all, but
each method's body becomes a few lines delegating to a service instead
of containing the logic itself.

## Proposed approach

### `PgnCodec` — static, no internal state

```dart
// lib/features/game/domain/usecases/pgn_codec.dart
class PgnCodec {
  static String toPgn(GameState state) { /* today's GameState.pgn body */ }

  /// Parses a PGN string into (initialFen, finalFen, sanMoves, lastFrom, lastTo).
  static ({String initialFen, String finalFen, List<String> sanMoves,
           String? lastFrom, String? lastTo})? parse(String pgn) { /* today's _parsePgn */ }

  /// Finds the legal move from [fromFen] to [toFen], returning both its
  /// SAN and UCI form in one board traversal (replaces the separate
  /// _findSanMove/_findUciMove, which independently replayed the same
  /// legal-move loop — see refactor_02_shared_chess_helpers.md).
  static ({String san, String uci})? findMove(String fromFen, String toFen) { /* ... */ }

  static String applyUciWithSan(String fen, String uci) { /* today's _applyUciWithSan, if still needed
                                                                once findMove covers its use sites */ }
}
```

`GameState.pgn` becomes a one-line delegating getter: `String get pgn =>
PgnCodec.toPgn(this);` — kept as a getter (not removed) because it's a
pure read of `this`'s own fields with no external dependency, which is
a legitimate thing for `GameState` to expose directly; only the
*algorithm* moves out, not the convenience accessor.

### `ClockService` — owns the `Timer`, reports back via callback

```dart
// lib/features/game/presentation/providers/clock_service.dart
class ClockService {
  Timer? _timer;

  /// Starts (or restarts) ticking. Calls [onTick] every ~100ms with the
  /// elapsed milliseconds since the last tick; GameNotifier decides how
  /// to apply that to whichever side's clock is running and whether it's
  /// now a timeout.
  void start(void Function(int elapsedMs) onTick) { /* today's _syncClockTimer body */ }
  void stop() { _timer?.cancel(); _timer = null; }
  void dispose() => stop();
}
```

`GameNotifier` keeps one `ClockService` instance (constructed in its own
constructor, same lifecycle as today's `Timer?` field), and `tickClock`'s
actual elapsed-time-to-state-update math (which side is active,
decrementing `whiteTimeMs`/`blackTimeMs`, detecting `<= 0` and setting
`timeoutWinner`) **stays in `GameNotifier`** — that part is genuine
state-coordination logic (it reads/writes `state`), not something to
extract. Only the `Timer` plumbing itself moves out.

### `GameReviewService` — stateful, holds the eval cache

```dart
// lib/features/game/presentation/providers/game_review_service.dart
class GameReviewService {
  final ChessEngineRepository _engine;
  final Map<String, int> _fenEvalCache = {
    GameReviewAnalyzer.fenKey(chess_lib.Chess.DEFAULT_POSITION): 20,
  };

  GameReviewService(this._engine);

  void recordEval(String fen, int cp) =>
      _fenEvalCache[GameReviewAnalyzer.fenKey(fen)] = cp;

  Map<String, int> get evalByFenKey => Map<String, int>.from(_fenEvalCache);

  Future<GameReviewSummary> computeReview({
    required String initialFen,
    required List<String> sanMoves,
    required int botElo,
    required bool humanIsWhite,
    required Future<void> Function(String fen) ensureEvaluated, // fills any gaps via _engine.evaluateFen
  }) async { /* today's _computeGameReview body */ }
}
```

This is instance-based (not static like `PgnCodec`) because
`_fenEvalCache` is real mutable state that has to persist for the whole
game and be injected with an engine reference — exactly the shape
`ChessEngineRepository` already uses, so `GameNotifier` holds one
`GameReviewService` the same way it holds `_engine` and `_attemptMove`
today (constructor injection).

### `_awardCrownsIfHumanWon` and `_registerDebugMoveExtension`

Both stay on `GameNotifier` — `_awardCrownsIfHumanWon` is a few lines of
pure state-update logic with no reusable algorithm to extract, and the
debug VM extension is inherently tied to `GameNotifier`'s lifecycle
(registered once per instance, guarded by the existing
`_debugExtensionRegistered` static flag) rather than being a service
anything else would ever use.

### What's explicitly *not* moving

`GameState`'s other computed getters (`currentWhiteCp`,
`formattedEvalScore`, `plyWhiteCpHistory`, `liveMoveClassifications`,
`displayedFen`/`_displayedSnapshot`, `materialFor`, `isGameOver`/
`isDraw`/`isCheckmate`, `gameOverMessage`, `positionCounts`) stay exactly
where they are. The test for "does this belong in a service instead of
a `GameState` getter" is: *does it need a dependency beyond `this`'s own
fields* (an engine call, a parser, a cache)? PGN parsing/serialization
and FEN-diff-to-move needed exactly that (a full re-implementation of
"replay legal moves and compare"), which is why they're the ones
extracted. The rest are pure functions of `state`'s own fields — that's
what a `GameState` getter is *for*, and splitting them out into a
separate "selector" layer would be solving a problem this codebase
doesn't have (there's no framework-level reason Riverpod state can't
carry computed getters, and every one of these is already independently
unit-tested via `game_notifier_test.dart` state assertions).

## Decisions baked in as reasonable calls

1. `PgnCodec` is static-only (no constructor, no injected state) — same
   shape as `ScholarsMateHunterPolicy`/`PawnPusherPolicy`, consistent
   with this codebase's existing convention for stateless domain logic.
2. `ClockService` and `GameReviewService` are instance-based and
   constructor-injected into `GameNotifier`, same DI pattern as
   `ChessEngineRepository`/`AttemptMoveUseCase` already use — no new DI
   mechanism introduced.
3. `ClockService` reports elapsed time via callback rather than owning
   `whiteTimeMs`/`blackTimeMs` itself — the *meaning* of a tick (whose
   clock, timeout detection) depends on `GameState`, which the service
   deliberately doesn't know about, keeping it a dumb interval-ticker
   that's trivially testable with a `FakeAsync`/manual `onTick` call.
4. `_findSanMove`/`_findUciMove`'s merge into one `PgnCodec.findMove`
   (deferred from phase 2 specifically because it's PGN-service work,
   not generic chess-helper work) happens here, not phase 2.
5. Explicit non-goal (see "What's explicitly not moving" above):
   `GameState`'s pure computed getters are not touched. Resist the urge
   to introduce a "selectors" layer here — there's no evidence of a
   problem it would solve.

## Likely touched files

- `lib/features/game/domain/usecases/pgn_codec.dart` — new.
- `lib/features/game/presentation/providers/clock_service.dart` — new.
- `lib/features/game/presentation/providers/game_review_service.dart` —
  new.
- `lib/features/game/presentation/providers/game_provider.dart` —
  `GameNotifier` constructor gains `ClockService`/`GameReviewService`
  fields; `tickClock`/`_syncClockTimer` thin out to delegate to
  `ClockService`; `_computeGameReview` thins out to delegate to
  `GameReviewService.computeReview`; `_fenEvalCache` moves into
  `GameReviewService`, so every direct reference to it elsewhere in
  `GameNotifier` (`onUserMove`, `_playBotReply`, `newGame`, `loadFen`,
  `loadPgn`) goes through `_gameReviewService.recordEval`/
  `.evalByFenKey` instead; `GameState.pgn` delegates to `PgnCodec.toPgn`;
  `_parsePgn`/`_findSanMove`/`_findUciMove`/`_applyUciWithSan` deleted
  from `GameNotifier`, replaced by `PgnCodec` calls.
- `test/unit/game_notifier_test.dart` — should need **no assertion
  changes** (this phase is the strongest test of "did we actually keep
  behavior identical" in the whole refactor, since it touches the most
  surface area) — only possibly new imports if any test constructs a
  `GameNotifier` with additional required constructor parameters for the
  new services (give `ClockService`/`GameReviewService` sensible
  no-config constructors so existing test call sites need minimal
  changes).
- New `test/unit/pgn_codec_test.dart`, `test/unit/clock_service_test.dart`
  — net-new isolated coverage for logic that was previously only
  reachable through `GameNotifier`.

## Verification

Per `refactor_overview.md`'s checklist. This is the phase most likely to
introduce a subtle regression (most call sites touched), so: run the
full suite after *each* extraction (`PgnCodec` first, verify, then
`ClockService`, verify, then `GameReviewService`, verify) rather than
doing all three in one pass — if something breaks, this isolates which
extraction caused it instead of debugging three at once.
