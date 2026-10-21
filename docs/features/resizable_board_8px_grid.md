# Feature: Board Resizing & 8px Grid Alignment

**Status:** Built (with persistence & min-width clamping extracted from Chess.com's board resizer bundle).

## Overview

Reverse-engineered from Chess.com's board layout resizer bundle (`#board-layout-controls`, `--modifiedBoardWidth`, and `CSS.supports("width: round(down, 257px, 8px)")`). Ensures that every square on the 8×8 board lands on an exact integer pixel boundary (eliminating sub-pixel seams between squares) and allows the user to interactively resize the board by dragging its bottom-right corner handle.

## Key Files in Flutter App

- [`lib/core/widgets/chess_board/chess_board_widget.dart`](../../lib/core/widgets/chess_board/chess_board_widget.dart) — `ChessBoardWidget.snapTo8Px(double rawSize)` and `ResizableBoardFrame`
- [`lib/features/game/presentation/pages/game_page.dart`](../../lib/features/game/presentation/pages/game_page.dart) — integrates `ResizableBoardFrame` around `ChessBoardWidget`

## Reverse-Engineered Mechanics

### 1. 8px Grid Snapping (`b()` and `U(e)`)
In the original JS bundle:
```js
function b() {
  let e = v();
  return (e.name === "Safari" && e.version < 17) || (p() && !m([17, 2, 0]))
    ? false
    : CSS.supports("width: round(down, 257px, 8px)");
}
function U(e) {
  if (e >= X) {
    document.body.style.setProperty(
      "--modifiedBoardWidth",
      b() ? `${e}px` : `${e - (e % 8)}px`
    );
  }
}
```
- Because a chessboard has 8 files and 8 ranks, any board width not divisible by `8` produces fractional square sizes (e.g., `301 / 8 = 37.625px`), causing anti-aliased hairline gaps between squares.
- In Flutter, `ChessBoardWidget.snapTo8Px(double rawSize)` computes:
  ```dart
  static double snapTo8Px(double rawSize) {
    if (rawSize <= 64.0) return 64.0;
    final snapped = (rawSize.floor() ~/ 8) * 8;
    return snapped < 64 ? 64.0 : snapped.toDouble();
  }
  ```

### 2. Corner Drag-to-Resize (`K()`, `ResizableBoardFrame`)
- **RTL-Aware Delta:** In JS, `t = d() ? -1 : 1` flips the horizontal drag delta (`(e.pageX - r) * t`) when `document.documentElement.getAttribute("dir") === "rtl"`.
- **Clamping:** Clamps the board size between minimum width (`X = --boardMinWidth * 10`, or `160px` in our Flutter `ResizableBoardFrame`) and the maximum available container size (`maxSize`).
- **Frame Throttling (`s(e)`):** Wraps `mousemove` updates in `requestAnimationFrame` (`cancelAnimationFrame` on pending frames) before updating `--modifiedBoardWidth` and dispatching a global `new Event("resize")` (`S()`).
- **Double-Tap Reset:** Double-tapping the resize handle in `ResizableBoardFrame` resets the custom size back to the responsive default (`_customSize = null`).

### 3. LocalStorage Cache & Quota Eviction (`M`, `P`, `z(e)`, `A()`)
- Saves `boardLayoutSize` and `new-board-layout-cache: true` under the `json_settings` key in `localStorage`.
- If `localStorage.setItem` throws a `QuotaExceededError`, `A()` scans all keys matching `/^Resource\.([0-9a-f-]{36}|anonymous)\./i` that do not belong to the active `window.context?.user?.uuid` and removes them before retrying.
