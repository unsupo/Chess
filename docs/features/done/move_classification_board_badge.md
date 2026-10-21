# Feature: On-Board Move-Quality Badge

**Status:** Built. Inspired by
`docs/features/chesscom_reference/board_vfx_animations_svg_badges.md`'s
description of Chess.com's board badges (best-move star, blunder X, mate
icon, edge-tucking), adapted to this app's own iconography — a small
colored circle showing the move's `MoveClassification.symbol`, not
Chess.com's SVG art (which isn't available/licensed here).

## What it does

After a move, a small colored badge (the move's classification symbol —
`!!`, `!`, `?!`, `?`, `??`, etc.) appears anchored at the destination
square's top-right corner, floating half on/half off the square — the
same convention `MoveHistoryAndFeedbackBar`'s per-move strip badges
already used, just now also shown directly on the board. `good`/`book`
moves are deliberately unremarkable and don't get a badge, matching that
same widget's existing suppression rule — the two UIs never disagree
about which moves are "notable."

## Edge tucking

If the destination square sits on the board's own top row or right
column, the badge nudges inward (down / left respectively) by its own
size so it never renders outside the board's bounds — mirroring Chess.com's
`bi()` top/right edge detection from the VFX reference doc above, adapted
to this board's own coordinate system (`_squareCenter`'s col/row, which
already accounts for board orientation).

## Key files

- `lib/core/widgets/chess_board/chess_board_widget.dart` — `badgeSquare`/
  `badgeSymbol`/`badgeColor` widget params (deliberately primitive
  strings/a `Color`, not the `MoveClassification` enum — `core/widgets/`
  has zero dependency on `features/`, and this keeps it that way) and
  `_buildClassificationBadge`.
- `lib/features/game/presentation/pages/game_page.dart` — `_notableClassification(GameState)`
  resolves `state.currentPlyClassification` into what the board should
  show, reusing `move_history_feedback_bar.dart`'s `classificationColor`.
- `test/chess_board_classification_badge_test.dart` — net-new coverage:
  badge renders at the right square, no badge when `badgeSquare` is
  null, and the two edge-tucking cases (top row, right column), each
  asserting the actual rendered `Rect` stays within the board's bounds.

## Verification

`flutter analyze` clean, `flutter test` green (139 tests, 4 new), and a
real `flutter build macos --debug` compiles. **Not verified by a live
screenshot** — the widget tests assert exact pixel rects for both the
default and both tucked positions, which is what a screenshot would
otherwise be checking; a live run would only add visual color/shape
confirmation on top of that. Flagging this per this repo's UI-change
verification convention rather than silently skipping it.
