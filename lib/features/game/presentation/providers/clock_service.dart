// Timer plumbing extracted out of `GameNotifier` — see
// docs/features/refactor_05_game_notifier_facade.md. Deliberately dumb:
// it only knows how to start/stop a periodic tick and report elapsed
// time back via callback. The *meaning* of a tick (whose clock is
// running, timeout detection, `GameState` updates) depends on
// `GameState`, which this class deliberately doesn't know about, so that
// stays in `GameNotifier.tickClock` — same split as the mate-safety
// decorator wrapping `BotMovePipeline` rather than the pipeline itself
// knowing about mate safety.
import 'dart:async' show Timer;

class ClockService {
  Timer? _timer;

  /// Starts (or restarts) ticking. Calls [onTick] every 100ms with the
  /// elapsed milliseconds since the last tick.
  void start(void Function(int elapsedMs) onTick) {
    stop();
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => onTick(100),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
