# Gotchas

Non-obvious pitfalls with symptoms, causes, and fixes. Read before touching an area it covers.

---

## 1. Stockfish `stdin` setter throws if engine is not in `ready` state

**Symptom:** `StateError: Stockfish is not ready (starting)` crash, or spinner hangs indefinitely.

**Cause:** The `Stockfish.stdin` setter in `stockfish` 1.8.1 explicitly throws if `_state.value != StockfishState.ready`. The engine initialises asynchronously (via `compute` / isolates). Sending any UCI command before the engine reaches `ready` crashes.

**Fix:** Always call `_waitReady()` before touching `_engine.stdin`. The repository's `_serialized` queue ensures this automatically for all public methods.

---

## 2. Shared `_readyOkCompleter` race between concurrent engine operations

**Symptom:** Bot spinner never clears; app appears frozen after a move.

**Cause:** The old implementation used a single shared `_readyOkCompleter` field. When `setBotElo` (called unawaited from the `GameNotifier` constructor) ran concurrently with `evaluateFen` (called from a user move), both wrote to the same field. One operation consumed the other's `readyok` response, leaving the other completer permanently incomplete — no timeout, no spinner clear.

**Fix:** `_serialized<T>()` — a `Future<void> _queue` chain that ensures `setBotElo`, `evaluateFen`, and `getBestMove` never overlap. Each operation fully completes before the next starts.

```dart
Future<T> _serialized<T>(Future<T> Function() fn) {
  final Future<T> next = _queue.then<T>((_) => fn());
  _queue = next.then<void>((_) {}, onError: (_) {});
  return next;
}
```

---

## 3. Stale `bestmove` completing the wrong Completer

**Symptom:** Bot makes a random or clearly wrong move; evaluation scores incorrect.

**Cause:** If `evaluateFen` timed out and sent `stop`, the engine's `bestmove` response could arrive *after* the next operation had already set a new `_evalCompleter`. The stale `bestmove` would complete the new completer with the wrong score.

**Fix:** Set `_evalCompleter` / `_moveCompleter` only **after** `_prepareSearch` returns (i.e., after `readyok`). `_prepareSearch` sends `stop` first; because the engine processes commands in FIFO order, the stale `bestmove` arrives **before** `readyok` — and since the completer doesn't exist yet, it is silently dropped.

```dart
Future<int> evaluateFen(String fen, ...) => _serialized(() async {
  await _waitReady();
  await _prepareSearch(fen);   // stop → ucinewgame → position → isready → readyok
  _evalCompleter = Completer<int>();  // set HERE, after all stale output has passed
  _engine.stdin = 'go movetime 300';
  ...
});
```

---

## 4. `go depth N` has no time bound — use `movetime` instead

**Symptom:** Spinner never clears; engine thinks for 30+ seconds.

**Cause:** `go depth 10` asks Stockfish to search to depth 10 with no time limit. At low ELO on a fast machine, this can take 10–30 s. There is no built-in ceiling.

**Fix:** Use `go movetime N` (milliseconds). For blunder detection: `movetime 300` (300 ms). For bot reply: `movetime = (elo / 1.5).floor().clamp(400, 2000)`. Always add a Dart-side `.timeout()` as a second safety net.

---

## 5. `chess.dart` Color enum: `.name` returns `'WHITE'`/`'BLACK'`, not `'w'`/`'b'`

**Symptom:** Piece code lookup always falls through to `SizedBox.shrink()`; board renders empty.

**Cause:** `chess.Color` is a plain Dart `enum { WHITE, BLACK }`. `.name` (Dart 2.15+ introspection) returns the identifier string `'WHITE'` / `'BLACK'`. The piece widget lookup uses `'w'` / `'b'` prefixes.

**Fix:**
```dart
final colorCode = piece.color == ch.Color.WHITE ? 'w' : 'b';
final code = '$colorCode${piece.type.name.toUpperCase()}'; // e.g. 'wP', 'bK'
```

---

## 6. `flutter_chess_board` 1.0.1 ships no piece images

**Symptom:** Board renders (green squares visible) but all pieces are missing.

**Cause:** `flutter_chess_board` 1.0.1 only bundles board texture PNGs. Piece PNGs were removed in a prior version. The package's `ChessBoardWidget` is not used at all in this project.

**Fix:** Use `chess_vectors_flutter` for vector piece widgets (`WhitePawn`, `BlackKing`, etc.). The custom `ChessBoardWidget` calls `_pieceWidget(code, size)` which returns the appropriate widget via a switch.

---

## 7. `Stockfish` factory throws if an instance already exists (hot-reload)

**Symptom:** `StateError: Multiple instances are not supported, yet.` on hot reload or restart.

**Cause:** `Stockfish()` factory stores a static `_instance`. If the Flutter engine is hot-reloaded without calling `dispose()`, the old instance is still alive when a new one is requested.

**Fix:** The `engineRepositoryProvider` calls `repo.dispose()` in `ref.onDispose`. For development, prefer hot-**restart** (`R`) over hot-reload (`r`) when changing engine-related code. Full hot-reload of widget-only code is fine.

---

## 8. `kDefaultPersonality` must be a `const` — list indexing is not compile-time constant

**Symptom:** `non_constant_default_value` lint error on `GameState` constructor default parameter.

**Cause:** `kPersonalities[0]` is not a compile-time constant (list indexing isn't). Default parameter values in Dart must be compile-time constants.

**Fix:** Declare `const kDefaultPersonality = BotPersonality(...)` as a top-level constant and reference it directly in the default parameter.

---

## 9. `separatorBuilder` wildcard syntax requires Dart 3

**Symptom:** `unnecessary_underscores` lint warning on `separatorBuilder: (_, __) => ...`

**Cause:** Using `__` (double underscore) for the second unused parameter triggers the lint. Dart 3 introduced wildcard parameters using `_` for all unused positions.

**Fix:** `separatorBuilder: (_, _) => const SizedBox(width: 8)` — both parameters use `_`.

---

## 11. `_engine.stdout.transform(const LineSplitter())` buffers forever — the engine never "responds"

**Symptom:** Bot spinner runs for a long time then gives up with no move;
`_sync()`/`evaluateFen`/`getBestMove` always hit their timeouts. Happens on
every platform, not just macOS — this bug predates the macOS port.

**Cause:** The `stockfish` package's `_isolateStdout` already reassembles
raw native reads into complete, newline-stripped lines before sending them
(`previous + chunk`, split on `\n`, buffer the trailing partial line). Each
event on `Stockfish.stdout` is therefore a single line with **no** `\n`
character in it. Piping that through `.transform(const LineSplitter())`
again makes `LineSplitter` wait for a newline character it will never see —
it buffers every event forever and never emits, so
`ChessEngineRepositoryImpl._handleUciOutput` never fires.

**Fix:** Don't re-split. `_engine.stdout.listen(_handleUciOutput)` directly
— no `.transform()`. Confirmed by attaching a second, untransformed
listener to the same stream during debugging: it received every UCI line
(including `readyok`) immediately, while the `LineSplitter`-wrapped listener
received nothing, ever.

---

## 12. `package:stockfish` 1.8.1 ships no macOS implementation

**Symptom:** On macOS, the engine's `state` never reaches
`StockfishState.ready` within any reasonable time (or at all) — every
`_waitReady()` call burns its full 15s timeout.

**Cause:** The package's `pubspec.yaml` only declares `android` and `ios`
plugin platforms. There's no native stockfish implementation wired into a
macOS build at all.

**Fix:** The package is vendored locally at `third_party/stockfish/` (path
dependency in `pubspec.yaml`) with an added `macos/` CocoaPods pod. CocoaPods
`source_files` can't reference paths outside the podspec's own directory, so
the iOS pod's Stockfish C++ source and FFI bridge (`ios/Stockfish`,
`ios/FlutterStockfish`) are **duplicated** into `macos/Stockfish` /
`macos/FlutterStockfish` rather than shared — see
`third_party/stockfish/macos/stockfish.podspec`.

Two more things were needed before the engine actually worked on macOS,
independent of the above:

- The package's `compute()`-based init (which spawns an isolate via
  `Isolate.exit()`-style completion) never signaled back to the root
  isolate on this build. Fixed by spawning the stdout/main isolates
  directly with `Isolate.spawn` from the root isolate instead (see
  `third_party/stockfish/lib/src/stockfish.dart`, `Stockfish._spawnDirect`).
- `macos/Runner/Info.plist` now sets `FLTEnableMergedPlatformUIThread` to
  `false` — this Flutter version defaults that experimental mode on for
  macOS (logged at launch as *"Running with merged UI and platform
  thread. Experimental."*), disabled as a stability precaution while
  debugging isolate-messaging issues.

**Trap:** `stockfish_main()`'s native `dup2(CHILD_WRITE_FD, STDOUT_FILENO)`
redirects the **whole process's** stdout fd into the engine's own pipe once
the engine starts. Any `print()` call anywhere in the app after that point
is silently swallowed — or worse, gets written back into the engine's own
input pipe and read back as bogus "UCI output," corrupting the stream. Never
enable `Logger.root.onRecord.listen((r) => print(...))` (or any other
print-based logging) in this app; use a file-based diagnostic instead if you
need to debug the engine.

---

## 13. `ChessBoardOrientation` enum is defined in the project, not in a package

**Symptom:** Import confusion; `flutter_chess_board`'s orientation enum is not used.

**Cause:** The custom `ChessBoardWidget` defines its own `ChessBoardOrientation { white, black }` enum in `chess_board_widget.dart` (exported via `board_theme.dart`). `flutter_chess_board`'s widget is not instantiated anywhere.

**Fix:** Import from `package:chess_teacher/core/widgets/chess_board/chess_board_widget.dart`.

---

## 14. `setBotElo`'s `Skill Level` leaked into the anti-blunder shield's own evaluation

**Symptom:** The anti-blunder shield lets obvious blunders through, especially
at low bot difficulty (e.g. the default Martin personality, 900 ELO).

**Cause:** `Skill Level` is a *persistent* UCI engine option — once set, it
stays in effect for every subsequent `go` command until changed again.
`setBotElo` used to send `setoption name Skill Level value N` immediately
and leave it there. `evaluateFen` (the blunder check,
`AttemptMoveUseCase`) and `getBestMove` (the bot's own move) share one
engine instance, so the blunder check was running on the *same weakened
engine* as the bot's move selection — e.g. Skill Level 1 at the default
900 ELO. A deliberately dumbed-down Stockfish can genuinely fail to see
that a move hangs a piece.

**Fix:** `setBotElo` now only *stores* the computed skill value
(`_skillLevel`); it no longer sends `Skill Level` to the engine. Only
`getBestMove` sets it (right before its own search) and restores it to
20 (Stockfish's own default / full strength) immediately after. This
means `evaluateFen` always runs at full strength — see
`docs/features/engine.md` and `docs/features/anti_blunder.md`. Confirmed
by scripting an obvious queen-hanging blunder (`Qh5??` where `g6` pawn
takes for free) at the default personality via the
`ext.chess_teacher.makeUciMove` debug extension: rejected correctly after
the fix, where it would previously have depended on a Skill-Level-1
engine noticing an 800+cp swing.
