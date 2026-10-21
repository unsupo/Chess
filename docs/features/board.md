# Feature: Chess Board Widget

## Overview

Fully custom `ChessBoardWidget` (StatefulWidget + CustomPainter). Does **not** use `flutter_chess_board`'s widget — only its board texture images (not currently used; board colors come from `BoardTheme`).

## Key files

- `lib/core/widgets/chess_board/chess_board_widget.dart` — widget + painter + piece renderer
- `lib/core/widgets/chess_board/board_theme.dart` — `BoardTheme` color constants

## Piece rendering

Pieces are rendered via `chess_vectors_flutter` 1.1.0 (vector SVG widgets). The `_pieceWidget(code, size)` top-level function maps a two-character code to the correct widget:

```dart
// code = colorPrefix + pieceType.name.toUpperCase()
// e.g. 'wP', 'bK', 'wQ'
final colorCode = piece.color == ch.Color.WHITE ? 'w' : 'b'; // NOT .name
final code = '$colorCode${piece.type.name.toUpperCase()}';
```

`piece.color.name` returns `'WHITE'`/`'BLACK'` (Dart enum introspection) — use `== ch.Color.WHITE` comparison instead. See GOTCHAS #5.

## Drag-and-drop

Pan gesture detection with a 6 px threshold distinguishes taps from drags:

- `onPanStart` — records `_panStart`
- `onPanUpdate` — if distance > 6 px AND own piece: start drag (record `_draggingFrom`, `_draggingCode`); else update `_dragPosition`
- `onPanEnd` — if not dragging: treat as tap; if dragging: commit move to target if legal, else deselect
- `onPanCancel` — clear all drag state

The dragged piece is hidden from its source square (`if (square == _draggingFrom) continue`) and rendered as a floating `Positioned` widget outside the board bounds (`Stack(clipBehavior: Clip.none)`).

## Tap-to-move

`_onSquareTapped` handles the click flow:
- Nothing selected → click own piece → select + show legal move dots
- Piece selected → click legal target → commit move
- Piece selected → click own piece → re-select
- Piece selected → click elsewhere → deselect

## Board reversal

`orientation: ChessBoardOrientation.white` (white at bottom) or `ChessBoardOrientation.black` (black at bottom). The `_grid` (8×8 list of square names) is rebuilt via `_buildGrid()` whenever orientation changes.

## FEN sync

`didUpdateWidget` calls `_initFrom(widget.fen)` whenever `fen` or `orientation` changes. This is used for blunder revert (provider sets `state.fen = preMoveFen`), bot move application, and new game. It fully resets internal `_chess`, selection, and drag state.

## Highlights

All rendered by `_BoardPainter` (CustomPainter):
- **Selected square** — solid accent color
- **Legal move dots** — small filled circles on empty targets; hollow rings on captures
- **Last move** — alpha-blended highlight on `lastMoveFrom` / `lastMoveTo`
- **Check** — alpha-blended red on the king square

## Promotion dialog

Shown as an `AlertDialog` with four piece choices (Q, R, B, N). The move is committed after the user picks. If the dialog is dismissed without selection, the move is cancelled.
