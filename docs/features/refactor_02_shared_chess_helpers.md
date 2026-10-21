# Refactor Phase 2: Consolidate Duplicated Chess Helpers

**Status:** Built. Part of
[refactor_overview.md](refactor_overview.md), phase 2. Independent of
phase 1 — can be done before, after, or in parallel with it.

## Problem

The same handful of "pure chess logic" questions are answered by 2-3
independent implementations, living in different files, that are not
guaranteed to agree:

### Piece values — 3 copies

- `lib/features/game/domain/entities/chess_move_analysis.dart`:
  top-level `int pieceValue(chess_lib.PieceType type)`.
- `lib/features/game/domain/usecases/scholars_mate_hunter_policy.dart`:
  `ScholarsMateHunterPolicy._pieceValue()` (private, same switch, same
  values).
- `lib/features/game/domain/usecases/pawn_pusher_policy.dart`:
  `PawnPusherPolicy._pieceValue()` (private, same switch, same values).

All three currently agree (pawn=1, knight/bishop=3, rook=5, queen=9,
king=0), so no bug exists *yet* — but nothing stops them from drifting,
and anyone editing one reasonably assumes they're editing "the" piece
value table.

### Move → UCI string — 2 copies

- `scholars_mate_hunter_policy.dart`: `_moveToUci(chess_lib.Move m)`.
- `pawn_pusher_policy.dart`: `_moveToUci(chess_lib.Move m)`.

Identical implementation (`'$from$to$promo'` built from
`Chess.algebraic(m.from/m.to)` + `m.promotion?.name`).

### "Is this piece safe / hanging?" — 3 different answers

- `chess_move_analysis.dart`: `hangingPieceValueAfter(fen, uci)` — plays
  the move, enumerates opponent captures, checks for a legal recapture
  on the same square.
- `scholars_mate_hunter_policy.dart`: `_hangsQueenOrAllowsMate(fen,
  uci)` — narrower (queen-only + mate-in-1 check), different approach
  (enumerates opponent moves and checks target-square piece identity).
- `pawn_pusher_policy.dart`: `_hasHangingNonPawnPiece(chess_lib.Chess
  currentChess)` — yet another independent implementation, scoped to
  non-pawn pieces on the current board rather than after a hypothetical
  move.

These three are legitimately checking different things (general hanging
value vs. "would this specific move hang the queen or allow mate" vs.
"is any non-pawn piece hanging right now") — this phase does **not**
try to force them into one function with the same signature. The fix is
narrower: make the ones that *are* the same question (piece values,
move→UCI) share one implementation, and leave the three different
hanging-piece questions as three clearly-named functions in one shared
file instead of three private near-duplicates scattered across
unrelated policy files.

## Proposed approach

`chess_move_analysis.dart` is already the natural home — it's Flutter-free,
already shared by `bot_style_policy.dart`, and already has
`pieceValue()`/`applyUciToFen()`/`materialFor()`/`MoveAnalysis`/
`movesCreatesFork()`/`hangingPieceValueAfter()`. Add to it:

```dart
/// Move in UCI notation (e.g. 'd1h5', 'f1c4', 'h5f7', 'e7e8q').
String moveToUci(chess_lib.Move m) {
  final from = chess_lib.Chess.algebraic(m.from);
  final to = chess_lib.Chess.algebraic(m.to);
  final promo = m.promotion != null ? m.promotion!.name : '';
  return '$from$to$promo';
}
```

Then:
1. Delete `ScholarsMateHunterPolicy._pieceValue()` and
   `PawnPusherPolicy._pieceValue()`; both files import `pieceValue` from
   `chess_move_analysis.dart` instead.
2. Delete `ScholarsMateHunterPolicy._moveToUci()` and
   `PawnPusherPolicy._moveToUci()`; both import `moveToUci` instead.
3. Rename `ScholarsMateHunterPolicy._hangsQueenOrAllowsMate` and
   `PawnPusherPolicy._hasHangingNonPawnPiece` **in place** — no logic
   change, just confirming (via a comment pointing at this doc) that
   they're deliberately distinct from `hangingPieceValueAfter` and why,
   so a future reader doesn't "simplify" them into one function and
   silently change behavior.
4. `game_provider.dart`'s own `_applyUci` (private, lines ~1521) and
   `chess_move_analysis.dart`'s `applyUciToFen` are the same operation
   under different names in different files — `GameNotifier` switches to
   calling `applyUciToFen` directly and its private copy is deleted.

## Decisions baked in as reasonable calls

1. Only unify the two helpers that are *actually* identical today
   (piece values, move→UCI). The three "hanging piece" functions stay
   separate because they answer genuinely different questions — forcing
   a shared signature would either lose precision (the queen/mate-in-1
   check) or add unused parameters (the "right now, no hypothetical
   move" check), which is worse than three well-named functions.
2. No behavior change anywhere — this phase is verified by the existing
   test suite already covering `chess_move_analysis_test.dart`,
   `scholars_mate_hunter_policy_test.dart`, and
   `pawn_pusher_policy_test.dart` continuing to pass unmodified (those
   tests call the public `selectMove`/`pickMove` entry points, not the
   private helpers being consolidated, so no test changes are expected
   at all — if a test needs to change, something's wrong).
3. `game_provider.dart`'s `_applyUciWithSan` (used for PGN move
   application) is **not** touched here — it does double duty (returns
   both the resulting FEN and the SAN in one board traversal) and
   doesn't have a duplicate elsewhere; it's in scope for phase 5
   (`GameNotifier` Facade split into `PgnCodec`), not this phase.

## Likely touched files

- `lib/features/game/domain/entities/chess_move_analysis.dart` — add
  `moveToUci()`.
- `lib/features/game/domain/usecases/scholars_mate_hunter_policy.dart` —
  remove `_pieceValue`/`_moveToUci`, import from `chess_move_analysis.dart`.
- `lib/features/game/domain/usecases/pawn_pusher_policy.dart` — same.
- `lib/features/game/presentation/providers/game_provider.dart` — remove
  private `_applyUci`, call `applyUciToFen` directly.
- No test files should need changes (see decision #2) — if any do,
  that's a signal to stop and re-check before proceeding.

## Verification

Per `refactor_overview.md`'s checklist. Extra check specific to this
phase: run `scholars_mate_hunter_policy_test.dart`,
`pawn_pusher_policy_test.dart`, `bot_style_policy_test.dart`, and
`chess_move_analysis_test.dart` individually before/after and diff the
output — should be byte-identical pass counts and test names.
