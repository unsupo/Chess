// Isolated coverage for ClockService — see
// docs/features/done/refactor_05_game_notifier_facade.md. Previously the
// `Timer` plumbing lived directly on `GameNotifier` and could only be
// exercised indirectly (via `tickClock`/the public clock-related
// GameState fields), with no way to test the timer mechanics (restart
// behavior, stop/dispose) on their own.
//
// These use real `Timer.periodic` delays rather than `FakeAsync` (not a
// project dependency), with generous margins relative to the 100ms tick
// interval to stay robust under CI scheduling jitter.
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/presentation/providers/clock_service.dart';

void main() {
  group('ClockService', () {
    test('start calls onTick repeatedly, each with ~100ms elapsed', () async {
      final service = ClockService();
      final ticks = <int>[];
      service.start(ticks.add);
      await Future.delayed(const Duration(milliseconds: 450));
      service.stop();
      expect(ticks.length, greaterThanOrEqualTo(2));
      expect(ticks.every((e) => e == 100), isTrue);
    });

    test('stop prevents further ticks', () async {
      final service = ClockService();
      final ticks = <int>[];
      service.start(ticks.add);
      await Future.delayed(const Duration(milliseconds: 350));
      service.stop();
      final countAtStop = ticks.length;
      expect(countAtStop, greaterThan(0));
      await Future.delayed(const Duration(milliseconds: 350));
      expect(ticks.length, countAtStop);
    });

    test('calling start again restarts cleanly instead of running two '
        'timers at once', () async {
      final service = ClockService();
      final ticks = <int>[];
      service.start(ticks.add);
      await Future.delayed(const Duration(milliseconds: 250));
      service.start(ticks.add);
      final countAtRestart = ticks.length;
      await Future.delayed(const Duration(milliseconds: 250));
      // A single timer ticking every 100ms over 250ms fires ~2-3 times; a
      // stacked second timer running alongside it would roughly double
      // that. The gap between the two is wide enough to absorb real
      // scheduling jitter without masking an actual double-timer bug.
      expect(ticks.length - countAtRestart, lessThanOrEqualTo(4));
    });

    test('dispose stops ticking', () async {
      final service = ClockService();
      final ticks = <int>[];
      service.start(ticks.add);
      await Future.delayed(const Duration(milliseconds: 250));
      service.dispose();
      final countAtDispose = ticks.length;
      expect(countAtDispose, greaterThan(0));
      await Future.delayed(const Duration(milliseconds: 350));
      expect(ticks.length, countAtDispose);
    });
  });
}
