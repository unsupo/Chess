# Feature: Chessboard Core API, Premoves, Variations & Capture-the-Star Mode

**Status:** Extracted Reference — reverse-engineered from `@chesscom/chessboard v1.189.0`.

## Overview

Documents the internal architecture of `@chesscom/chessboard`, including its AOP plugin hook system, multi-move premove queue, PGN variation tree management, "Capture the Star" mini-game mode, and CEE (Chess Engine Evaluator) error reporting.

---

## 1. AOP Plugin & Method Interceptor System (`aee`, `one`)

`@chesscom/chessboard` allows features and game modes to wrap any method on `context.api` using an aspect-oriented hook system (`aee`):
- Every hooked API method maintains three ordered interceptor arrays (`before`, `instead`, `after`, sorted by `order`) plus `extensions`.
- **`before` hooks:** Can inspect arguments and optionally mutate them if `changeArgs: true`.
- **`instead` hooks:** Replace the underlying `current` implementation when their `conditions(context, ...args)` predicate returns `true`.
- **`after` hooks:** Transform or react to the return value `(result, ...args)`.
- Calling the disposer function returned by `aee(pluginId, hooks)` cleanly unregisters all interceptors for `pluginId`.

---

## 2. Multi-Move Premove Queue (`tee`, `Sn`, `mee`, `Lee`, `Wte`, `Cne`)

- **Queue Storage:** `game.premove.queue` stores an array of queued premoves so players can pre-chain multiple moves (e.g., recaptures or king walks) while it is the opponent's turn (`cte(e): e.api.getPlayingAs() !== e.api.getTurn()`).
- **Reload Preservation (`Sn`):** When `api.reload()` is called, if `api.premoves.getQueue().length > 0`, it snapshots the queue, reloads the board state, and replays `api.premoves.loadQueue(savedQueue)`.
- **King Premove Fallback (`Lee`):** When validating a premove where the moving piece is a King (`type.toLowerCase() === 'k'`) and normal premove generation doesn't match, it temporarily snapshots `game.premove.queue`, tests `game.premove.move(n)`, cancels, and restores the queue.
- **Auto-Queen Promotion Fallback (`Cne`):** When checking `game.getMove(move)` and it returns `null`, it automatically retries with `Object.assign(move, { promotion: "q" })`.

---

## 3. Variation Tree & PGN Annotation Commands (`Vn`, `Jr`, `di`, `yr`)

### A. Supported Variation & Annotation Actions (`Vn`)
- **Annotations & Comments:** `AddAnnotation`, `AddAdditionalAnnotation`, `RemoveAnnotation`, `HideAllAnnotations`, `ShowAllAnnotations`, `AddComment`, `AddCommentBefore`, `DeleteCommentAfter`, `DeleteCommentBefore`
- **Tree Manipulation:** `DeleteVariation`, `PromoteVariation`, `DeleteMove`, `ClearAnalysis`, `InsertContinuation`, `MoveVariationUp`, `MoveVariationDown`
- **Range / Focus Selection:** `SetBegin`, `RemoveBegin`, `SetEnd`, `RemoveEnd`, `SetFocus`, `RemoveFocus`

### B. 64-Bit Position Hash Comparison (`di(nodeA, nodeB)`)
```js
function di(e, t) {
  if (!e || !t) return false;
  let { ids: n, hash: r } = t;
  return (
    e.ids.line === n.line &&
    e.ids.move === n.move &&
    e.hash[0] === r[0] &&
    e.hash[1] === r[1]
  );
}
```
- Each move node carries `{ ids: { line, move }, hash: [hi32, lo32] }` to detect identical positions across lines.

### C. Move List Auto-Scroller (`yr`)
- Smoothly scrolls `.node[data-node="${line}-${move}"]` (`Ji`) into view inside `moveListEl` using modes `'center'`, `'nearest-edge'`, `'top'`, or `'bottom'`, with `onlyIfOutside: true` to avoid jarring scrolls when the move chip is already visible.

---

## 4. "Capture the Star" Mini-Game Mode (`Xt`, `Qt`, `an`, `Mr`)

Used for interactive beginner lessons and arcade puzzles where stars (or custom items) are placed on board squares (`initialItems`):
- **`Mr(captureLog, moveIndex, initialItems)`:** Filters `captureLog` entries with `moveIndex <= currentMoveIndex` and deletes those squares from `initialItems` so scrubbing backward/forward in the move list restores or removes stars accurately!
- **State Snapshot (`an`):**
  ```js
  {
    completed: puzzleState.get("completed") || false,
    completedMoveCount: puzzleState.get("completedMoveCount"),
    captureLog: puzzleState.get("captureLog") ?? [],
    itemsRemaining: captureTheStar.getNumItemsRemaining(),
    moveCount: captureTheStar.getCurrentMoveCount(),
    initialItems: puzzleState.get("initialItems") || {},
  }
  ```

---

## 5. CEE (Chess Engine Evaluator) Error Hierarchy (`Rt`, `zt`, `Bt`, `Vt`)

When the local WebAssembly/Worker chess engine encounters an error:
- `CeeError` (`Rt`) — base class storing `this.recentLog` (array of recent UCI/engine log lines) and implementing `toAttachments()` to attach `binary-interface-logs.txt` to Sentry crash reports.
- `CeeWorkerError` (`zt`) — Web Worker initialization/communication failure.
- `CeeFeatureError` (`Bt`) — unsupported engine capability/option failure.
- `CeeDecodeError` (`Vt`) — binary protocol decode failure, storing `this.bytesBase64` alongside `recentLog`.
