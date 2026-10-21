# Feature: Board Visual Effects (VFX), Arrow Geometry, & SVG Badges

**Status:** Extracted Reference — reverse-engineered from `@chesscom/chessboard v1.189.0`.

## Overview

Documents the visual feedback animations, arrow math, edge-tucking rules, and embedded SVG badge artwork in Chess.com's board renderer.

---

## 1. Interactive Board VFX Overlays

### A. Illegal Move Tap Overlay (`vte`)
When a user taps or drops a piece onto an illegal destination square:
- Creates `<div class="illegal-move-tap-overlay">` and `<div class="illegal-move-tap-circle">` inside the target square.
- Plays the CSS keyframe animation `illegal-move-tap-overlay-fade` (`ui`) and automatically removes the DOM elements on `animationend` / `animationcancel`.

### B. Growing Circle Ripple on Tap/Drop (`Dne`, `Vi`)
When selecting or dragging over a square, spawns `<div class="growing-circle">` with animation `growing-circle-expand`:
- **Light square preset (`Vi.light`):** `color: "#000000"`, `initialOpacity: 0.07`
- **Dark square preset (`Vi.dark`):** `color: "#ffffff"`, `initialOpacity: 0.25`

### C. "Hand-Throw" Sticker / Piece Animation (`ite`)
Used for animated bot/arcade reactions thrown onto the board (`.hand-throw-image.hand-throw-animate`):
- `appearDurationMs`: `150ms` (`--hand-throw-appear-duration`)
- `throwDurationMs`: `200ms` (`--hand-throw-throw-duration`)
- `fadeDurationMs`: `800ms` (`--hand-throw-fade-duration`)
- `appearRotationDeg`: `90deg` (`--hand-throw-appear-rotation`)
- `throwScaleX` / `throwScaleY`: `1.5`
- `throwDyPercent`: `-8%`
- Auto-cleans up after `appearDurationMs + throwDurationMs + fadeDurationMs` (`1150ms`).

### D. Step Opacity Decay & Easing Curves (`bn`, `Yn`, `Xn`, `Zn`, `Vne`, `Hne`)
- **Step Opacity (`bn`):** `opacity = Math.min(1, 2.86 - 2.86 * ((stepIndex + 1) / numSteps))` (holds opacity at `1.0` for the first ~65% of the animation, then linearly fades to `0.0`).
- **Easing Functions:**
  - `Yn(t) = t * t` (Ease-In Quad)
  - `Xn(t) = t * (2 - t)` (Ease-Out Quad)
  - `Zn(t)` (Ease-In-Out Quad)
  - `Vne(t) = --t * t * t + 1` (Ease-Out Cubic)
  - `Hne(t)` (Ease-In-Out Cubic)

---

## 2. Arrow Geometry & Knight L-Shape Rotation (`Ln`, `_r`, `ure`)

When drawing right-click or engine suggestion arrows between squares `from` and `to`:
1. **Euclidean Distance (`ure`):**
   ```js
   Math.sqrt((from.x - to.x) ** 2 + (from.y - to.y) ** 2);
   ```
2. **Slope Calculation (`Ln`):**
   ```js
   const slope = Number(((from.y - to.y) / (from.x - to.x)).toFixed(1));
   ```
3. **Knight Move L-Shape Arrow Orientation (`_r`):**
   Knight jumps have a slope of `±2.0` or `±0.5`. `_r` maps the slope and direction to a cardinal rotation angle (`0°`, `90°`, `180°`, `270°`) for the L-shaped arrow SVG:
   ```js
   switch (slope) {
     case 2:    return from.x > to.x ? 180 : 0;
     case -2:   return from.x > to.x ? 0 : 180;
     case 0.5:  return from.x > to.x ? 90 : 270;
     case -0.5: return from.x > to.x ? 90 : 270;
     default:   return 0;
   }
   ```

---

## 3. Edge Badge Tucking (`yi`, `bi`) & Check/King Target (`fr`)

Move classification and game-over badges (`bestMove`, `blunder`, `mate`, `timeout`, `resign`) are normally positioned protruding slightly from the top-right corner of the destination square.
- **Top/Right Edge Detection (`bi(square, isFlipped)`):**
  ```js
  function bi(square, isFlipped) {
    const edges = {
      top: isFlipped ? "1" : "8",
      right: isFlipped ? "a" : "h",
    };
    return {
      top: square.includes(edges.top),
      right: square.includes(edges.right),
    };
  }
  ```
- If `top` is true, adds `.tuck-top`; if `right` is true, adds `.tuck-right` so the badge stays inside the board boundary.
- **King Castling Target (`fr(move)`):** Uses `move.kingTo ?? move.to` so badges attach to the King's final square on castling moves.

---

## 4. Embedded SVG Icons in Bundle

The chunk embeds raw SVG `<g>` definitions for board overlay badges:
- **`On` & `Ni` (`#mate`):** White-filled and Black-filled tilted King (`#`) checkmate icons.
- **`gr` (`#incorrect`):** Red circle (`#FF7769`) with white `X` cross for wrong puzzle moves.
- **`Tr` (`#bestMove`):** 5-pointed white star icon for best moves.
- **`qr` (`#timeout`):** Clock face icon shown on the King's square when a player flags on time.
- **`ua` (`#resign`):** White flag icon shown on the King's square upon resignation.
- **`pre`:** 64×64 multi-toned gold star SVG (`#F7C631`, `#FAD541`, `#E3AA24`, `#FFF599`) used for collectible stars on the board.
