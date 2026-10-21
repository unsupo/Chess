# Feature: Chess Engine Integration

## Overview

Local Stockfish UCI engine via a locally vendored fork of the `stockfish`
1.8.1 FFI package (`third_party/stockfish/`, path dependency — see below).
All engine I/O is wrapped in `ChessEngineRepositoryImpl`
(`native_engine_repository.dart`). On web, a random-move stub is used
instead.

## Conditional import

```dart
// chess_engine_repository_impl.dart
export 'native_engine_repository.dart'
    if (dart.library.js_interop) 'web_engine_repository.dart';
```

## Platform support / the macOS fork

The published `stockfish` 1.8.1 package only ships Android and iOS native
implementations. To run on macOS desktop, the package is vendored at
`third_party/stockfish/` with an added `macos/` CocoaPods pod (duplicating
the iOS pod's C++ engine source, since CocoaPods can't reference files
outside a pod's own directory) plus two isolate-related fixes needed to get
the engine actually responding on macOS. See GOTCHAS #12 for the full
story, and GOTCHAS #11 for a separate, platform-independent bug
(`LineSplitter` double-processing) that was blocking bot replies on every
platform until fixed.

## Operation serialization

All three public methods — `setBotElo`, `evaluateFen`, `getBestMove` — are wrapped in `_serialized<T>()`, a simple promise-chain mutex:

```dart
Future<T> _serialized<T>(Future<T> Function() fn) {
  final Future<T> next = _queue.then<T>((_) => fn());
  _queue = next.then<void>((_) {}, onError: (_) {});
  return next;
}
```

This is required because `setBotElo` is called unawaited from `GameNotifier`'s constructor. Without serialization, `evaluateFen` can race with `setBotElo` and corrupt the shared `_syncCompleter` field. See GOTCHAS #2 and #3.

## Initialization sequence

1. `Stockfish()` factory creates the engine (spawns the stdout/main FFI
   isolates directly from the root isolate — see GOTCHAS #12 for why this
   is no longer done via `compute()`).
2. When `StockfishState.ready` fires, `_initEngine` sends `uci`.
3. `setBotElo` (queued first) calls `_waitReady()`, then sends `setoption name UCI_LimitStrength value false` + `setoption name Skill Level value N`, each followed by `_sync()` (isready/readyok).

## Search flow (`evaluateFen` / `getBestMove`)

```
_waitReady()
_prepareSearch(fen):
  stop          ← drain any stale bestmove BEFORE setting completers
  ucinewgame    ← wipe transposition tables
  position fen  
  isready → readyok

_evalCompleter = Completer<int>()   ← set AFTER prepareSearch
go movetime 300
← bestmove arrives → _evalCompleter.complete(score)
```

Setting the completer **after** `_prepareSearch` is critical. The defensive `stop` at the start of `_prepareSearch` can trigger a stale `bestmove` from a prior timed-out search. Since the engine processes commands in FIFO order, that stale `bestmove` arrives **before** `readyok` — and the completer doesn't exist yet, so it's silently dropped.

## Timing budget

| Phase | Time |
|---|---|
| `setBotElo` (first call, cold engine) | ~300–800 ms |
| `evaluateFen` × 2 (blunder check) | ~700 ms |
| `getBestMove` at 900 ELO (movetime 600 ms) | ~700 ms |
| **Total per move (typical)** | **~1.4–2.1 s** |

## Difficulty scaling

`Skill Level = ((elo - 800) / 100).clamp(0, 20)` maps human Elo to Stockfish's internal skill (0–20). `UCI_LimitStrength` is explicitly disabled because it's buggy in some FFI builds.

`Skill Level` is set **only** around `getBestMove`'s own search, never
left standing — see GOTCHAS #14. Leaving it set persistently would also
weaken the anti-blunder shield's own evaluation, since `evaluateFen` and
`getBestMove` share one engine instance.

`Skill Level`'s own floor (0, i.e. ELO ≤ 800 in the formula above) still
plays at roughly ~1300 real strength — it was never designed to emulate a
genuinely weak human. The difficulty slider's range (`250`–`2800`,
`game_page.dart`) extends well below where `Skill Level` can have any
further effect; below 1000 ELO, `GameNotifier._pickBotMove` sometimes
substitutes a uniformly random legal move for the engine's choice instead
(probability scaling from 0% at 1000 ELO to 50% at the slider's floor),
the same technique `web_engine_repository.dart`'s web mock already uses
for every move — matching how chess.com's own low-rated bots work
(deliberately weak move selection, not a strong engine turned down).

## Timeouts

| Operation | Dart-side timeout |
|---|---|
| `_waitReady()` | 15 s |
| `_sync()` (isready/readyok) | 8 s |
| `evaluateFen` search | 5 s |
| `getBestMove` search | movetime + 4 000 ms |

All timeouts send `stop` and return a safe fallback value so `isEvaluating` always clears.
