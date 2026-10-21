import 'package:flutter/material.dart';
import 'game_theme.dart';

class AntiBlunderToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const AntiBlunderToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Anti-Blunder',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Switch(
          value: enabled,
          activeThumbColor: kAccent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class EvalBarToggle extends StatelessWidget {
  final bool shown;
  final ValueChanged<bool> onChanged;

  const EvalBarToggle({
    super.key,
    required this.shown,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Eval Bar & Graph',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Switch(
          key: const ValueKey('evalBarToggle'),
          value: shown,
          activeThumbColor: kAccent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class HistoryLockToggle extends StatelessWidget {
  final bool locked;
  final ValueChanged<bool> onChanged;

  const HistoryLockToggle({
    super.key,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: locked
          ? 'ON: Going back is view-only (cannot change past moves)'
          : 'OFF: Going back lets you play a new move from that turn',
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'View-Only History',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Switch(
            key: const ValueKey('lockHistorySwitch'),
            value: locked,
            activeThumbColor: kAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class MateSafetyControl extends StatelessWidget {
  final bool enabled;
  final int n;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onNChanged;

  const MateSafetyControl({
    super.key,
    required this.enabled,
    required this.n,
    required this.onEnabledChanged,
    required this.onNChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Mate Safety',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Switch(
              value: enabled,
              activeThumbColor: kAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: onEnabledChanged,
            ),
          ],
        ),
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Row(
            children: [
              Text(
                'Avoid mate in ≤ $n',
                style: const TextStyle(color: kMuted, fontSize: 11),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: n.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: enabled ? (v) => onNChanged(v.toInt()) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
