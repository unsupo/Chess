import 'package:flutter/material.dart';
import '../../domain/entities/time_control.dart';
import 'game_theme.dart';

/// Displays 0..3 crowns (`👑`) earned against a bot (`bot-crowns`).
class BotCrownsWidget extends StatelessWidget {
  final int crowns;
  final double size;

  const BotCrownsWidget({super.key, required this.crowns, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final clamped = crowns.clamp(0, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.5),
            child: Opacity(
              opacity: i < clamped ? 1.0 : 0.25,
              child: Icon(
                Icons.workspace_premium,
                size: size,
                color: i < clamped ? const Color(0xFFFFD54F) : kMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// 3-way selector for playing as White, Random, or Black (`play-side-selector`).
class PlaySideSelectorWidget extends StatelessWidget {
  final PlaySide selected;
  final ValueChanged<PlaySide> onChanged;

  const PlaySideSelectorWidget({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Flexible(
          child: Text(
            'Play As',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 6),
        for (final side in PlaySide.values) ...[
          if (side != PlaySide.values.first) const SizedBox(width: 4),
          Flexible(
            child: _PlaySideButton(
              key: ValueKey('playSide_${side.name}'),
              side: side,
              isSelected: selected == side,
              onTap: () => onChanged(side),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlaySideButton extends StatelessWidget {
  final PlaySide side;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlaySideButton({
    super.key,
    required this.side,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget iconWidget;
    switch (side) {
      case PlaySide.white:
        iconWidget = Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black54),
          ),
        );
      case PlaySide.random:
        iconWidget = const Text(
          '?',
          style: TextStyle(
            color: kAccent,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        );
      case PlaySide.black:
        iconWidget = Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white54),
          ),
        );
    }

    return Tooltip(
      message: 'Play as ${side.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? kAccentFill : kBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? kAccent : kBorderSubtle,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  side.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? kAccent : kMuted,
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal time control preset selector (`time-selector`).
class TimeControlSelectorWidget extends StatelessWidget {
  final TimeControl selected;
  final ValueChanged<TimeControl> onChanged;

  const TimeControlSelectorWidget({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.timer_outlined, size: 14, color: kMuted),
            const SizedBox(width: 5),
            const Expanded(
              child: Text(
                'Time Control',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${selected.category.label} · ${selected.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 26,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (
                  int index = 0;
                  index < TimeControl.presets.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Builder(
                    builder: (context) {
                      final tc = TimeControl.presets[index];
                      final isSelected = tc.key == selected.key;
                      return GestureDetector(
                        key: ValueKey('timeControl_${tc.key}'),
                        onTap: () => onChanged(tc),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? kAccentFill : kBg,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: isSelected ? kAccent : kBorderSubtle,
                              width: isSelected ? 1.4 : 1.0,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tc.label,
                            style: TextStyle(
                              color: isSelected ? kAccent : kMuted,
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
