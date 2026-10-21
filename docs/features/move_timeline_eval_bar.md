# Feature: Move Timeline, Eval Bar, and Eval Graph

**Status:** Built. The move timeline (clickable SAN chips, step back/forward,
`selectPly`/`currentPly`/`viewPly`) and per-move classification badges were
already built independently (see `chess_feature_widgets.dart`'s
`MoveHistoryAndFeedbackBar` and `GameReviewAnalyzer`). The togglable eval
bar (`EvalBar`, `GameState.showEvalBar`) and the eval graph with key-move
markers (`EvalGraph`, `GameState.plyWhiteCpHistory`) were added on top of
that — see `lib/features/game/presentation/widgets/chess_feature_widgets.dart`
and `GameNotifier.setShowEvalBar`.

## Problem

Three related requests:
1. A **timeline** of the game you can scrub back through — jump to any
   earlier position instead of only ever seeing the current one.
2. A **togglable eval bar** showing who's winning and by how much right
   now (chess.com-style).
3. The timeline should show a **graph** of the eval over the course of
   the game, with key moves marked.

All three need the same missing piece of state: `GameState` today only
holds the *current* `fen` — there's no record of the game's history at
all. That has to exist first; the eval bar, timeline, and graph are three
views onto it.

## Proposed approach

### 1. Move history becomes real state

Add to `GameState`:

```dart
final List<GameHistoryEntry> history; // one entry per ply actually played
final int? viewingIndex; // null = viewing the live/latest position
```

```dart
class GameHistoryEntry {
  final String fen;       // position AFTER this ply
  final String uci;       // the move that produced it
  final int evalCp;        // engine eval of the resulting position, White's perspective
  const GameHistoryEntry({required this.fen, required this.uci, required this.evalCp});
}
```

Every accepted human move and every bot move appends one entry (both in
`onUserMove`/`_playBotReply`, which already exist — see
`docs/features/anti_blunder.md` for the current flow). `newGame()` /
`loadFen()` reset `history` to empty (loading a FEN starts a fresh
timeline from that position, same as starting a fresh game from the
standard position — there's nothing before it to show).

### 2. Getting the eval without extra engine round trips

The eval bar and graph both need a centipawn score for *every* ply,
including the bot's own moves — today nothing evaluates the position
after a bot move at all. The naive approach (an extra `evaluateFen` call
after every move) adds a real round trip per ply. Cheaper: `getBestMove`'s
own search already reports a score via `info ... score cp N ...` lines
while it searches — `_handleUciOutput` in `native_engine_repository.dart`
already captures this into `_latestScore` today, it's just discarded
instead of returned. Change `getBestMove` to return `(String uci, int
evalCp)` (or add a sibling field) instead of just the move string — no
extra search needed, the number was already being computed.

The human's move already has an eval too — `AttemptMoveUseCase.execute`
already computes `evaluateFen(newFen)` as part of the blunder check (see
`anti_blunder.md`'s flow diagram); when anti-blunder is *disabled*
(`docs/features/anti_blunder.md`'s toggle) there's currently no
evaluation at all, so a human move's history entry would need its own
`evaluateFen` call in that case specifically — the one real added cost,
and only when the user has turned blunder-checking off.

### 3. Eval bar

A togglable widget (new sidebar switch, same pattern as the anti-blunder
toggle) showing the *current* position's eval — reads
`history.last?.evalCp` (or 0 for the starting position with no history
yet). Visual: a vertical bar alongside the board, filled proportionally
white/black (clamp the cp range, e.g. ±800cp maps to the full bar, mate
scores pin it to one end) — standard chess.com-style treatment. Pure
presentation, no new state beyond what §1/§2 already add.

### 4. Timeline / scrubbing back

A horizontal strip (ply markers, e.g. below the board or in the sidebar)
tied to `viewingIndex`. Tapping a ply sets `viewingIndex` to that index;
`ChessBoardWidget`'s `fen` prop becomes `history[viewingIndex].fen`
instead of the live `state.fen` while reviewing. "Jump to latest" (or
simply tapping the current/last entry again) sets `viewingIndex` back to
`null`.

**Open decision:** is this read-only review (the default I'd propose —
scrub through history, can't play from a past position, matches "go back
in time" as *looking* back rather than *rewriting*), or does playing a
move while `viewingIndex` is set truncate `history` at that point and
continue from there (a real undo-and-branch)? Read-only is substantially
simpler and is what's built unless told otherwise:
`ChessBoardWidget(interactive: !state.isEvaluating && state.viewingIndex == null)`.

### 5. Eval graph with key moves

A simple line/area chart: X axis = ply index, Y axis = `evalCp` (clamped
to a sane range, e.g. ±1000, so one mate score doesn't flatten the rest
of the graph). This codebase hand-rolls its own `CustomPainter` rather
than pulling in widget packages for things it already owns (the board
itself, `_BoardPainter` in `chess_board_widget.dart`, is a hand-rolled
painter rather than a package widget) — proposing the same approach here
(a small `_EvalGraphPainter`) rather than adding a charting dependency
like `fl_chart`, for consistency and to avoid a new dependency for
something this simple. Flagging as a decision in case a charting package
is preferred for speed of implementation instead.

"Key moves" marked on the graph: plies where the eval swing from the
previous ply exceeds a threshold smaller than the hard blunder-reject
threshold (300cp, `AttemptMoveUseCase.blunderThresholdCp`) — proposing
100cp as a "notable swing" marker (a distinct dot color on the graph at
that ply). This only surfaces swings that happened (blunders are already
rejected before they can enter history at all when anti-blunder is on;
with it off, or for the bot's own imperfect moves, a notable swing can
end up in history and is worth flagging retrospectively).

Tapping a marked point on the graph jumps the timeline to that ply (ties
§4 and §5 together, matching "the timeline shows a graph... and key
moves").

## Decisions baked in as reasonable calls

1. Timeline review is read-only (no undo-and-branch) for v1.
2. Hand-rolled `CustomPainter` graph, not a new charting dependency.
3. "Key move" threshold: 100cp swing (separate from the 300cp blunder
   threshold).
4. Eval clamp range for both the bar and the graph: ±800–1000cp, with
   forced-mate scores pinned to the extreme.
5. `getBestMove`'s return type changes to carry its own eval score
   alongside the move, reusing the search that already happens rather
   than adding a second one.

## Sequencing note

This touches `GameState`/`GameNotifier` extensively (history tracking,
the `getBestMove` return-type change) — the same file the in-flight
bot-play-styles work (`docs/features/bot_play_styles.md`) is also
editing in its own worktree. Building this should wait until that work
is merged into main, to avoid three-way conflicts in
`game_provider.dart`.

## Likely touched files

- `lib/features/game/presentation/providers/game_provider.dart` — `GameState.history`/`viewingIndex`, append-on-move logic
- `lib/features/game/domain/repositories/chess_engine_repository.dart` + `native_engine_repository.dart` + `web_engine_repository.dart` — `getBestMove` return shape
- `lib/features/game/domain/usecases/attempt_move_usecase.dart` — expose the eval it already computes instead of discarding it
- `lib/features/game/presentation/pages/game_page.dart` — eval bar widget, timeline strip, graph widget, sidebar toggle
- New: a `GameHistoryEntry` entity, an eval-bar widget, a timeline-strip widget, an `_EvalGraphPainter`
