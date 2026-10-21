/// Play-side selection options matching Chess.com's `play-side-selector`.
enum PlaySide {
  white(label: 'White'),
  random(label: 'Random'),
  black(label: 'Black');

  final String label;
  const PlaySide({required this.label});
}

/// Standard chess time control categories.
enum TimeCategory {
  unlimited(label: 'Unlimited'),
  bullet(label: 'Bullet'),
  blitz(label: 'Blitz'),
  rapid(label: 'Rapid'),
  daily(label: 'Daily');

  final String label;
  const TimeCategory({required this.label});
}

/// Represents a chess time control configuration (base time + increment)
/// and provides parsing and decisecond clock formatting.
class TimeControl {
  final String key;
  final String label;
  final int baseSeconds;
  final int incrementSeconds;
  final TimeCategory category;

  const TimeControl({
    required this.key,
    required this.label,
    required this.baseSeconds,
    required this.incrementSeconds,
    required this.category,
  });

  /// True when a countdown clock is active for this time control.
  bool get isTimed => baseSeconds > 0 && category != TimeCategory.unlimited;

  /// Initial clock time in milliseconds for each player.
  int get initialTimeMs => baseSeconds * 1000;

  /// Per-move increment in milliseconds.
  int get incrementMs => incrementSeconds * 1000;

  /// Estimated total game duration in seconds (`baseTime + 40 * increment`),
  /// matching the `WO(e)` categorization formula.
  int get estimatedTotalSeconds => baseSeconds + 40 * incrementSeconds;

  static const TimeControl unlimited = TimeControl(
    key: 'none',
    label: 'Unlimited',
    baseSeconds: 0,
    incrementSeconds: 0,
    category: TimeCategory.unlimited,
  );

  static const TimeControl bullet1m = TimeControl(
    key: '60',
    label: '1 min',
    baseSeconds: 60,
    incrementSeconds: 0,
    category: TimeCategory.bullet,
  );

  static const TimeControl bullet1m1s = TimeControl(
    key: '60|1',
    label: '1 | 1',
    baseSeconds: 60,
    incrementSeconds: 1,
    category: TimeCategory.bullet,
  );

  static const TimeControl bullet2m1s = TimeControl(
    key: '120|1',
    label: '2 | 1',
    baseSeconds: 120,
    incrementSeconds: 1,
    category: TimeCategory.bullet,
  );

  static const TimeControl blitz3m = TimeControl(
    key: '180',
    label: '3 min',
    baseSeconds: 180,
    incrementSeconds: 0,
    category: TimeCategory.blitz,
  );

  static const TimeControl blitz3m2s = TimeControl(
    key: '180|2',
    label: '3 | 2',
    baseSeconds: 180,
    incrementSeconds: 2,
    category: TimeCategory.blitz,
  );

  static const TimeControl blitz5m = TimeControl(
    key: '300',
    label: '5 min',
    baseSeconds: 300,
    incrementSeconds: 0,
    category: TimeCategory.blitz,
  );

  static const TimeControl blitz5m5s = TimeControl(
    key: '300|5',
    label: '5 | 5',
    baseSeconds: 300,
    incrementSeconds: 5,
    category: TimeCategory.blitz,
  );

  static const TimeControl rapid10m = TimeControl(
    key: '600',
    label: '10 min',
    baseSeconds: 600,
    incrementSeconds: 0,
    category: TimeCategory.rapid,
  );

  static const TimeControl rapid10m5s = TimeControl(
    key: '600|5',
    label: '10 | 5',
    baseSeconds: 600,
    incrementSeconds: 5,
    category: TimeCategory.rapid,
  );

  static const TimeControl rapid15m10s = TimeControl(
    key: '900|10',
    label: '15 | 10',
    baseSeconds: 900,
    incrementSeconds: 10,
    category: TimeCategory.rapid,
  );

  static const TimeControl rapid30m = TimeControl(
    key: '1800',
    label: '30 min',
    baseSeconds: 1800,
    incrementSeconds: 0,
    category: TimeCategory.rapid,
  );

  /// Standard preset time controls (`oP` list).
  static const List<TimeControl> presets = [
    unlimited,
    bullet1m,
    bullet1m1s,
    bullet2m1s,
    blitz3m,
    blitz3m2s,
    blitz5m,
    blitz5m5s,
    rapid10m,
    rapid10m5s,
    rapid15m10s,
    rapid30m,
  ];

  /// Parses a time control specification string (e.g. `'180|2'`, `'600'`,
  /// `'300+5'`, `'3d'`, `'none'`), clamping base time to `<= 7200` seconds and
  /// increment to `0..60` seconds.
  static TimeControl parse(String spec) {
    final trimmed = spec.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed == 'none' || trimmed == 'unlimited') {
      return unlimited;
    }

    for (final preset in presets) {
      if (preset.key == trimmed) return preset;
    }

    if (trimmed.endsWith('d')) {
      final days = int.tryParse(trimmed.substring(0, trimmed.length - 1)) ?? 1;
      return TimeControl(
        key: '${days}d',
        label: '$days ${days == 1 ? 'day' : 'days'}',
        baseSeconds: days * 86400,
        incrementSeconds: 0,
        category: TimeCategory.daily,
      );
    }

    final parts = trimmed.split(RegExp(r'[+|]'));
    var base = int.tryParse(parts[0]) ?? 600;
    var inc = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    if (inc < 0 || inc > 60) inc = 0;
    if (base > 7200) base = 7200;
    if (base <= 0) return unlimited;

    final key = inc > 0 ? '$base|$inc' : '$base';
    final est = base + 40 * inc;
    final category = est < 180
        ? TimeCategory.bullet
        : est < 600
        ? TimeCategory.blitz
        : TimeCategory.rapid;

    final mins = base ~/ 60;
    final label = inc > 0 ? '$mins | $inc' : '$mins min';
    return TimeControl(
      key: key,
      label: label,
      baseSeconds: base,
      incrementSeconds: inc,
      category: category,
    );
  }

  /// Formats remaining clock milliseconds into a display string:
  /// - `0:00` when `<= 0`
  /// - `M:SS.d` (with tenths of a second) when `<= 20.0` seconds (`<= 200` deciseconds)
  /// - `H:MM:SS` when `>= 1` hour
  /// - `M:SS` otherwise
  static String formatClockMs(int remainingMs) {
    if (remainingMs <= 0) return '0:00';
    final totalDeciseconds = remainingMs ~/ 100;
    if (totalDeciseconds <= 0) return '0:00';

    var tenths = totalDeciseconds;
    final showTenths = tenths <= 200; // <= 20.0 seconds

    var seconds = tenths ~/ 10;
    tenths -= seconds * 10;

    var minutes = seconds ~/ 60;
    seconds -= minutes * 60;

    var hours = minutes ~/ 60;
    minutes -= hours * 60;

    final secStr = seconds < 10 ? '0$seconds' : '$seconds';
    if (hours > 0) {
      final minStr = minutes < 10 ? '0$minutes' : '$minutes';
      return '$hours:$minStr:$secStr';
    }
    if (showTenths) {
      return '$minutes:$secStr.$tenths';
    }
    return '$minutes:$secStr';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeControl &&
          other.key == key &&
          other.baseSeconds == baseSeconds &&
          other.incrementSeconds == incrementSeconds &&
          other.category == category;

  @override
  int get hashCode =>
      Object.hash(key, baseSeconds, incrementSeconds, category);
}
