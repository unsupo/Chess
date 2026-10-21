# Feature: Anti-Blunder Shield

## Overview

When the user makes a move, the position is evaluated **before and after** using Stockfish. If the evaluation drops by more than 300 centipawns, the move is rejected and the board reverts to the pre-move position. The user must find a better move.

## Flow

```
User drags piece → board applies move locally (optimistic)
  → onMove callback fires → GameNotifier.onUserMove(newFen)
    → isEvaluating = true
    → AttemptMoveUseCase.execute(preMoveFen, newFen)
        → evaluateFen(preMoveFen)    ← ~300 ms
        → evaluateFen(newFen)        ← ~300 ms
        → delta = -newEval - currentEval
        → blunder if delta < -300
    → if blunder:
        state.fen = preMoveFen       ← board reverts via didUpdateWidget
        isEvaluating = false
        errorMessage = 'Blunder! Find a better move.'
    → if accepted:
        state.fen = newFen
        getBestMove(newFen)          ← bot reply
        state.fen = afterBotMove
        isEvaluating = false
```

## Evaluation perspective

UCI engines always return scores from the **current side's** perspective. The delta calculation accounts for the perspective flip:

```
currentEval = evaluateFen(preFen)   // white's turn → white's perspective
newEval = evaluateFen(newFen)       // black's turn → black's perspective
delta = -newEval - currentEval      // convert to white's perspective
```

A delta of `-301` or less means white lost more than 3 pawns of value → blunder.

## Blunder revert

The board widget does **not** use `undoLastMove()` for blunder revert. Instead the provider sets `state.fen = preMoveFen`. `ChessBoardWidget.didUpdateWidget` detects the FEN change and calls `_initFrom(preMoveFen)`, which fully reinitialises the board. This avoids a visual double-revert glitch.

## Threshold

300 centipawns (3 pawns). Defined in `AttemptMoveUseCase.blunderThresholdCp`. Chosen to catch piece-dropping blunders while allowing positional inaccuracies.

## Board lock during evaluation

`ChessBoardWidget(interactive: !state.isEvaluating)` — all pan/tap handlers return early while evaluation is in progress, preventing double-moves.

## Toggle

`GameState.antiBlunderEnabled` (default `true`) — a switch in the sidebar
(and an icon in its collapsed rail) controlled by
`GameNotifier.setAntiBlunderEnabled`. When off, `onUserMove` skips the
blunder check entirely: any legal move is accepted immediately, no
evaluation happens, and the bot replies as normal.

## Evaluation always runs at full engine strength

`evaluateFen` must never run on a weakened engine, regardless of the
bot's configured difficulty — see GOTCHAS #14.
`ChessEngineRepositoryImpl` only applies `Skill Level` around
`getBestMove`'s own search, restoring it to 20 (full strength)
immediately after, so the blunder check's `evaluateFen` calls always see
accurate evaluations even when playing a low-ELO personality.
