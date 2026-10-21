import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/entities/time_control.dart';
import 'game_theme.dart';
import 'move_history_feedback_bar.dart';

/// Clock icon that rotates 90 degrees on every tick, matching `TickerIcon` (`RR`).
class TickerIconWidget extends StatelessWidget {
  final int quarterTurns;
  final Color color;
  final double size;

  const TickerIconWidget({
    super.key,
    required this.quarterTurns,
    required this.color,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: (quarterTurns % 4) * (math.pi / 2),
      child: CustomPaint(
        size: Size(size, size),
        painter: _TickerClockPainter(color: color),
      ),
    );
  }
}

class _TickerClockPainter extends CustomPainter {
  final Color color;
  const _TickerClockPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.2;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, radius, strokePaint);

    final handPaint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8;
    canvas.drawLine(
      center,
      Offset(center.dx + radius * 0.55, center.dy),
      handPaint,
    );
  }

  @override
  bool shouldRepaint(_TickerClockPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Chess clock display (`MoveTime`) with sub-20s tenths and rotating ticker icon.
class MoveTimeWidget extends StatefulWidget {
  final TimeControl timeControl;
  final int timeMs;
  final bool isActive;
  final bool isDarkTheme;

  const MoveTimeWidget({
    super.key,
    required this.timeControl,
    required this.timeMs,
    required this.isActive,
    this.isDarkTheme = false,
  });

  @override
  State<MoveTimeWidget> createState() => _MoveTimeWidgetState();
}

class _MoveTimeWidgetState extends State<MoveTimeWidget> {
  int _quarterTurns = 0;

  @override
  void didUpdateWidget(MoveTimeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && widget.timeMs != oldWidget.timeMs) {
      _quarterTurns = (_quarterTurns + 1) % 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.timeControl.isTimed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kBorderSubtle),
        ),
        child: const Text(
          '∞',
          style: TextStyle(
            color: kMuted,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }

    final isLowTime = widget.timeMs > 0 && widget.timeMs <= 20000;
    final formatted = TimeControl.formatClockMs(widget.timeMs);

    final Color bgColor;
    final Color fgColor;
    final Color borderColor;
    if (isLowTime && widget.isActive) {
      bgColor = const Color(0xFF5A1A1A);
      fgColor = const Color(0xFFFF8080);
      borderColor = kBlunderColor;
    } else if (widget.isActive) {
      bgColor = widget.isDarkTheme
          ? const Color(0xFF403D39)
          : const Color(0xFFF5F5F0);
      fgColor = widget.isDarkTheme ? Colors.white : kBg;
      borderColor = kAccent;
    } else {
      bgColor = kBg;
      fgColor = kMuted;
      borderColor = kBorderSubtle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: borderColor,
          width: widget.isActive ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isActive) ...[
            TickerIconWidget(
              key: const ValueKey('clockTickerIcon'),
              quarterTurns: _quarterTurns,
              color: fgColor,
              size: 13,
            ),
            const SizedBox(width: 5),
          ] else ...[
            Icon(Icons.schedule, size: 13, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            formatted,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
