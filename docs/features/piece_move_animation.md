# Feature: Animated Piece Movement

**Status:** Planned — not built. Written to align on approach before implementation.

## Problem

`ChessBoardWidgetState._buildPieces()` (`lib/core/widgets/chess_board/chess_board_widget.dart:323-345`)
places every piece in a plain `Positioned(left, top)` computed directly from
the current `_chess` position — no `AnimatedPositioned`, no
`TweenAnimationBuilder`, no tweening of any kind. Every FEN-driven update
(`didUpdateWidget` → `_initFrom`, line 60-79) fully rebuilds `_chess` and
re-renders every piece at its new square instantly. There is no sense of a
piece sliding from one square to another — it teleports. This is what reads
as "clunky" versus chess.com/lichess-style boards where moved pieces glide.

Two distinct cases exist today:

1. **User's own move via drag** — already has live tracking: `_dragPosition`
   follows the pointer during the drag (`_onPanUpdate`), rendered as a
   floating piece (`build()` line 309-316, `Layer 4`). But the moment the
   drag ends, `_commitMove` → `widget.onMove` → provider → new `fen` prop →
   `didUpdateWidget` → `_initFrom` throws that all away and snaps every
   piece (including the one just dragged) to a freshly computed grid
   position. There's no hand-off from "where the user dropped it" to "the
   square's exact center."
2. **Tap-to-move, bot replies, blunder revert, new game, FEN load, undo** —
   none of these have *any* user gesture to interpolate from; the piece
   simply needs to animate from its old square to its new one
   programmatically.

## Proposed approach

Diff the old and new board state in `didUpdateWidget` to find which
square(s) changed, and animate only the piece(s) that moved — leave every
static piece as a plain `Positioned` (cheap, no wasted animation
machinery).

```dart
void didUpdateWidget(ChessBoardWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.fen != oldWidget.fen || widget.orientation != oldWidget.orientation) {
    final move = _diffMove(oldWidget.fen, widget.fen); // best-effort (from, to), null if undiffable
    setState(() => _initFrom(widget.fen));
    if (move != null) _animateSlide(move.from, move.to); // drives a short AnimationController
  }
}
```

- `_diffMove` compares occupied squares between the two FENs to find the
  simplest explanation (one piece disappeared from square A, the same
  piece type/color appeared on square B). This covers the common case.
  Castling moves two pieces at once (king + rook) and en passant removes a
  pawn that isn't on the destination square — both need explicit
  detection (chess.dart's move history / `_chess.history` could supply the
  actual move type directly instead of inferring from FEN alone, which
  would be more reliable than diffing two board strings).
- Drive the animation with a short `AnimationController` (suggest
  150–200ms, `Curves.easeOut`) owned by `ChessBoardWidgetState`, animating
  a `Positioned` (or `Transform.translate`) for just the moved piece from
  its old pixel offset to its new one, while the rest of `_buildPieces()`
  renders normally underneath.
- For the user's own drag: skip the teleport entirely by special-casing
  the commit path — animate from `_dragPosition` (or the drop square) to
  the exact target-square center instead of re-deriving it generically
  through `_diffMove`, since the "move" is already known precisely
  (`from`, `to`) without needing to diff anything.

## Decisions needed

1. **Scope** — animate every move (own taps included) or primarily the
   bot's replies, which are the ones with zero existing visual continuity
   today?
2. **Duration/curve** — proposing ~150-200ms ease-out to match common
   chess UIs; confirm or adjust.
3. **Captures** — does the captured piece just disappear the instant the
   capturing piece's slide finishes (simplest), or fade/shrink out over
   the same duration?
4. **Castling** — animate king and rook simultaneously (two concurrent
   slides)? Any extra visual treatment, or just two plain slides?
5. **En passant / promotion** — promotion already shows a dialog before
   the move commits; does the pawn need to animate to the back rank before
   swapping to the promoted piece, or is an instant swap on arrival fine?
6. Is relying on `_chess.history` (if `chess.dart` exposes the last move
   type) preferred over FEN diffing for reliability, given FEN diffing
   alone can't distinguish castling/en passant from a normal move?

## Likely touched files

- `lib/core/widgets/chess_board/chess_board_widget.dart` — all of the
  above; no other file should need to change (`fen` stays the single
  source of truth passed in by `GamePage`/`GameNotifier`).

## Non-goals

- No changes to game logic, engine timing, or the provider layer — this
  is purely a rendering-layer animation on top of the existing FEN-driven
  board.
