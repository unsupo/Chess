# Feature: Chess Clocks, Time Controls, & Rotating Ticker

**Status:** Built (with additional daily/custom time control parsing and 10-second audio trigger documented from Chess.com's `play-computer` bundle).

## Overview

Reverse-engineered from Chess.com's `MoveTime` (`WR`), `TickerIcon` (`RR`), time control parser (`BO`), speed category calculator (`WO`), and decisecond formatter (`MO`, `Mh`). Provides configurable time controls, category classification, active player countdown clocks with a 90°-per-tick rotating clock SVG icon, tenth-of-a-second precision under 20 seconds, and flag/timeout detection.

## Key Files in Flutter App

- [`lib/features/game/domain/entities/time_control.dart`](../../lib/features/game/domain/entities/time_control.dart) — `TimeControl`, `TimeCategory`, `BO`/`WO`/`MO` equivalents
- [`lib/features/game/presentation/widgets/chess_feature_widgets.dart`](../../lib/features/game/presentation/widgets/chess_feature_widgets.dart) — `MoveTimeWidget`, `TickerIconWidget`, `TimeControlSelectorButton`
- [`lib/features/game/presentation/providers/game_provider.dart`](../../lib/features/game/presentation/providers/game_provider.dart) — 100ms decisecond timer (`_clockTimer`) and timeout game-over handling

## Reverse-Engineered Mechanics

### 1. Time Control Parsing (`BO(e)`) & Preset List (`oP`)
- **Preset Keys (`oP`):**
  ```js
  ["60", "60|1", "120|1", "180|2", "300", "300|5", "600", "900|10", "1800", "600|5", "1200", "3600"]
  ```
- **Parser (`BO(e)`):**
  - Accepts strings like `"600"`, `"180|2"`, `"180+2"`, `"3d"` (daily), or `"1/259200"` (moves per seconds), as well as objects `{ baseTime, timeIncrement, timeType }` or raw numbers.
  - Clamps `timeIncrement` to `0..60` seconds and `baseTime` to `<= 7200` seconds (2 hours).
  - Normalizes key format to `${baseTime}|${timeIncrement}` (or `${baseTime}` when increment is `0`).

### 2. Estimated Duration & Category Formula (`WO(e)`)
```js
function WO(e) {
  return (Number(e.baseTime) || 0) + 40 * (Number(e.timeIncrement) || 0);
}
```
- Assumes an average game length of **40 moves** when weighting the increment:
  - `estimatedSeconds == 0` → `TimeCategory.unlimited`
  - `< 180` (3 min) → `TimeCategory.bullet`
  - `< 600` (10 min) → `TimeCategory.blitz`
  - `>= 600` (10+ min) → `TimeCategory.rapid`

### 3. Decisecond Clock Formatting (`MO(e)` & `Mh(e, t)`)
```js
function MO(e) {
  let t = e;
  if (t <= 0) return "0:00";
  let n = 0, r = 0, i = 0, a = t <= 200; // <= 20.0 seconds (200 deciseconds)
  ...
  return n
    ? `${n}:${r}:${i}`
    : a
      ? `${r}:${i}.${Math.floor(t)}`
      : `${r}:${i}`;
}
```
- Input `e` is in **deciseconds** (tenths of a second).
- When `t <= 200` (`<= 20.0` seconds) and hours (`n`) is `0`, appends `.d` tenths of a second (`0:19.4`).
- Otherwise formats as `M:SS` or `H:MM:SS`.

### 4. Rotating Clock Ticker Icon (`RR` / `TickerIcon`)
```js
setup(e, { expose: t }) {
  let n = K(0),
      r = I(() => ({ transform: `rotate(${n.value}deg)` }));
  function i() {
    n.value += 90;
  }
  return t({ tick: i }), ...
}
```
- Every time the active player's `timeLeft` reactive prop changes, `MoveTime` calls `tickerIcon.value?.tick()`, rotating the SVG clock hand by **+90°** (`turns: _quarterTurns * 0.25` in Flutter's `TickerIconWidget`).

### 5. Low-Time Sound Trigger (`TI.TenSeconds` / `pR`)
- The sound controller (`pR`) listens for `wn.TenSeconds` (`"tenseconds"`) and triggers a warning sound effect when a player's clock crosses below 10 seconds, alongside `GameStart` (`"game-start"`) and `GameEnd` (`"game-end"`).
