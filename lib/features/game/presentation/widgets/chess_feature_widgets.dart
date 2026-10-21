import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/widgets/chess_board/chess_board_widget.dart';
import '../../domain/entities/time_control.dart';
import '../../domain/usecases/game_review_analyzer.dart';

const _cardBg = Color(0xFF243324);
const _darkBg = Color(0xFF1A2B1A);
const _accent = Color(0xFF7BBF44);
const _muted = Color(0xFF8AAD8A);
const _accentFill = Color(0x287BBF44);
const _accentBorder = Color(0x647BBF44);
const _borderSubtle = Color(0xFF3A5A3A);

// Colors from snippet 1
const kBrilliantMoveColor = Color(0xFF1BACA6);
const kGreatFindMoveColor = Color(0xFF5C8BB0);
const kBestMoveColor = Color(0xFF7BBF44);
const kBookMoveColor = Color(0xFFD5A47D);
const kInaccuracyColor = Color(0xFFF7C631);
const kMistakeColor = Color(0xFFFFA459);
const kBlunderColor = Color(0xFFFA412D);

Color classificationColor(MoveClassification c) {
  switch (c) {
    case MoveClassification.brilliant:
      return kBrilliantMoveColor;
    case MoveClassification.great:
      return kGreatFindMoveColor;
    case MoveClassification.best:
    case MoveClassification.good:
      return kBestMoveColor;
    case MoveClassification.book:
      return kBookMoveColor;
    case MoveClassification.inaccuracy:
      return kInaccuracyColor;
    case MoveClassification.mistake:
      return kMistakeColor;
    case MoveClassification.blunder:
      return kBlunderColor;
  }
}

// ── 1. Rotating Ticker Icon & MoveTime Clock Widget ──────────────────────────

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
          color: _darkBg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _borderSubtle),
        ),
        child: const Text(
          '∞',
          style: TextStyle(
            color: _muted,
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
      fgColor = widget.isDarkTheme ? Colors.white : _darkBg;
      borderColor = _accent;
    } else {
      bgColor = _darkBg;
      fgColor = _muted;
      borderColor = _borderSubtle;
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

// ── 2. 8px Grid-Aligned & Drag-to-Resize Board Frame ─────────────────────────

/// Wraps [child] (the chessboard) with an interactive corner drag-to-resize
/// handle that snaps dimensions to multiples of 8px (`size - size % 8`).
class ResizableBoardFrame extends StatefulWidget {
  final Widget child;
  final double boardSize;
  final double minSize;
  final double maxSize;
  final ValueChanged<double?> onSizeChanged;

  const ResizableBoardFrame({
    super.key,
    required this.child,
    required this.boardSize,
    required this.minSize,
    required this.maxSize,
    required this.onSizeChanged,
  });

  @override
  State<ResizableBoardFrame> createState() => _ResizableBoardFrameState();
}

class _ResizableBoardFrameState extends State<ResizableBoardFrame> {
  double? _dragStartSize;
  Offset? _dragStartPos;
  bool _isResizing = false;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _isResizing = true;
      _dragStartSize = widget.boardSize;
      _dragStartPos = details.globalPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStartSize == null || _dragStartPos == null) return;
    final delta = details.globalPosition - _dragStartPos!;
    final deltaMax = delta.dx.abs() > delta.dy.abs() ? delta.dx : delta.dy;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final signedDelta = isRtl ? -deltaMax : deltaMax;
    final rawTarget = (_dragStartSize! + signedDelta).clamp(
      widget.minSize,
      widget.maxSize,
    );
    final snapped = ChessBoardWidget.snapTo8Px(
      rawTarget,
      minSize: widget.minSize,
    );
    widget.onSizeChanged(snapped);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isResizing = false;
      _dragStartSize = null;
      _dragStartPos = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final aligned = ChessBoardWidget.snapTo8Px(
      widget.boardSize,
      minSize: widget.minSize,
    );
    return SizedBox(
      width: aligned,
      height: aligned,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned(
            right: 2,
            bottom: 2,
            child: Tooltip(
              message: 'Drag to resize board (double-tap to reset)',
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  key: const ValueKey('boardResizeHandle'),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => widget.onSizeChanged(null),
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: Container(
                    width: 20,
                    height: 20,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _isResizing
                          ? _accent.withValues(alpha: 0.85)
                          : _darkBg.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _isResizing ? Colors.white : _accentBorder,
                        width: 1,
                      ),
                    ),
                    child: CustomPaint(
                      painter: _ResizeGripPainter(
                        color: _isResizing ? _darkBg : _accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  final Color color;
  const _ResizeGripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.3, size.height),
      Offset(size.width, size.height * 0.3),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, size.height),
      Offset(size.width, size.height * 0.65),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ResizeGripPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── 3. Bot Crowns & Play-Side / Time-Control Selectors ───────────────────────

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
                color: i < clamped ? const Color(0xFFFFD54F) : _muted,
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
            color: _accent,
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
            color: isSelected ? _accentFill : _darkBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? _accent : _borderSubtle,
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
                    color: isSelected ? _accent : _muted,
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
            const Icon(Icons.timer_outlined, size: 14, color: _muted),
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
                  color: _accent,
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
                            color: isSelected ? _accentFill : _darkBg,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: isSelected ? _accent : _borderSubtle,
                              width: isSelected ? 1.4 : 1.0,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tc.label,
                            style: TextStyle(
                              color: isSelected ? _accent : _muted,
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

// ── 4. SAN Move List & Live Move Feedback Bar (`move-feedback-row`) ──────────

/// Displays the opening name (`eco-opening-panel`), live evaluation score pill
/// (`score-text`), latest move feedback (`move-feedback-row`), and clickable
/// SAN move chips (`move-san`).
class MoveHistoryAndFeedbackBar extends StatelessWidget {
  final List<String> sanMoves;
  final int currentPly;
  final List<MoveClassification> classifications;
  final String evalScoreText;
  final int whiteCp;
  final String? openingName;
  final ValueChanged<int> onSelectPly;

  const MoveHistoryAndFeedbackBar({
    super.key,
    required this.sanMoves,
    required this.currentPly,
    required this.classifications,
    required this.evalScoreText,
    required this.whiteCp,
    required this.openingName,
    required this.onSelectPly,
  });

  @override
  Widget build(BuildContext context) {
    final currentClassification =
        (currentPly > 0 && currentPly - 1 < classifications.length)
        ? classifications[currentPly - 1]
        : null;
    final currentMoveSan = (currentPly > 0 && currentPly - 1 < sanMoves.length)
        ? sanMoves[currentPly - 1]
        : null;
    final isNegativeEval = whiteCp < 0 || evalScoreText.startsWith('-');

    return Container(
      key: const ValueKey('moveHistoryFeedbackBar'),
      color: _cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Evaluation score pill (`score-text`)
              Container(
                key: const ValueKey('evalScorePill'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isNegativeEval
                      ? const Color(0xFF403D39)
                      : const Color(0xFFF5F5F0),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Text(
                  evalScoreText,
                  style: TextStyle(
                    color: isNegativeEval ? Colors.white : _darkBg,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Opening name (`eco-opening-panel`)
              if (openingName != null) ...[
                Flexible(
                  child: Text(
                    openingName!,
                    key: const ValueKey('openingNameLabel'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              // Move feedback badge (`move-feedback-row`)
              if (currentMoveSan != null && currentClassification != null)
                Container(
                  key: const ValueKey('moveFeedbackBadge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: classificationColor(
                      currentClassification,
                    ).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: classificationColor(currentClassification),
                    ),
                  ),
                  child: Text(
                    '$currentMoveSan is ${currentClassification.label} ${currentClassification.symbol}',
                    style: TextStyle(
                      color: classificationColor(currentClassification),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          if (sanMoves.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 22,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: sanMoves.length,
                itemBuilder: (context, idx) {
                  final ply = idx + 1;
                  final isWhiteMove = idx.isEven;
                  final moveNum = (idx ~/ 2) + 1;
                  final san = sanMoves[idx];
                  final isSelected = ply == currentPly;
                  final cls = idx < classifications.length
                      ? classifications[idx]
                      : null;

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      key: ValueKey('movePly_$ply'),
                      onTap: () => onSelectPly(ply),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? _accentFill : _darkBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? _accent : _borderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isWhiteMove)
                              Text(
                                '$moveNum. ',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                ),
                              ),
                            Text(
                              san,
                              style: TextStyle(
                                color: isSelected ? _accent : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 10,
                              ),
                            ),
                            if (cls != null &&
                                cls != MoveClassification.good &&
                                cls != MoveClassification.book) ...[
                              const SizedBox(width: 2),
                              Text(
                                cls.symbol,
                                style: TextStyle(
                                  color: classificationColor(cls),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 5. Eval Bar & Eval Graph ──────────────────────────────────────────────

/// Vertical bar beside the board showing who's winning and by how much —
/// White's share of `winPercentFromWhiteCp(whiteCp)` filled from whichever
/// end White's own pieces are displayed on (so it stays visually consistent
/// when the board is flipped to play Black).
class EvalBar extends StatelessWidget {
  final int whiteCp;
  final double height;
  final bool boardFlipped;

  const EvalBar({
    super.key,
    required this.whiteCp,
    required this.height,
    this.boardFlipped = false,
  });

  @override
  Widget build(BuildContext context) {
    final whiteFraction =
        (GameReviewAnalyzer.winPercentFromWhiteCp(whiteCp) / 100.0).clamp(
          0.02,
          0.98,
        );
    return ClipRRect(
      key: const ValueKey('evalBar'),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 14,
        height: height,
        color: _darkBg,
        child: Align(
          alignment: boardFlipped
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: whiteFraction,
            widthFactor: 1,
            child: Container(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Line graph of White's win% across the whole game (from `plyWhiteCpHistory`),
/// with dots marking "key moves" (brilliant/great/mistake/blunder) and a
/// marker at the currently-displayed ply. Tapping/dragging jumps to the
/// nearest ply, mirroring the SAN move chips above it.
class EvalGraph extends StatelessWidget {
  final List<int> whiteCpHistory;
  final List<MoveClassification> classifications;
  final int currentPly;
  final ValueChanged<int> onSelectPly;

  const EvalGraph({
    super.key,
    required this.whiteCpHistory,
    required this.classifications,
    required this.currentPly,
    required this.onSelectPly,
  });

  @override
  Widget build(BuildContext context) {
    if (whiteCpHistory.length < 2) return const SizedBox.shrink();
    final maxPly = whiteCpHistory.length - 1;

    void handleTapAt(double dx, double width) {
      if (width <= 0) return;
      final ply = (dx / width * maxPly).round().clamp(0, maxPly);
      onSelectPly(ply);
    }

    return LayoutBuilder(
      key: const ValueKey('evalGraph'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapUp: (d) => handleTapAt(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => handleTapAt(d.localPosition.dx, width),
          child: CustomPaint(
            size: Size(width, 36),
            painter: _EvalGraphPainter(
              whiteCpHistory: whiteCpHistory,
              classifications: classifications,
              currentPly: currentPly,
            ),
          ),
        );
      },
    );
  }
}

class _EvalGraphPainter extends CustomPainter {
  final List<int> whiteCpHistory;
  final List<MoveClassification> classifications;
  final int currentPly;

  _EvalGraphPainter({
    required this.whiteCpHistory,
    required this.classifications,
    required this.currentPly,
  });

  double _xOf(int ply, Size size) =>
      size.width * ply / (whiteCpHistory.length - 1);

  double _yOf(int cp, Size size) {
    final winPct = GameReviewAnalyzer.winPercentFromWhiteCp(cp);
    return size.height * (1 - winPct / 100.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (whiteCpHistory.length < 2) return;

    final midPaint = Paint()
      ..color = _borderSubtle
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      midPaint,
    );

    final linePaint = Paint()
      ..color = _accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(_xOf(0, size), _yOf(whiteCpHistory[0], size));
    for (var i = 1; i < whiteCpHistory.length; i++) {
      path.lineTo(_xOf(i, size), _yOf(whiteCpHistory[i], size));
    }
    canvas.drawPath(path, linePaint);

    const keyMoves = {
      MoveClassification.brilliant,
      MoveClassification.great,
      MoveClassification.mistake,
      MoveClassification.blunder,
    };
    for (var i = 0; i < classifications.length; i++) {
      final cls = classifications[i];
      if (!keyMoves.contains(cls)) continue;
      final ply = i + 1;
      final dotPaint = Paint()..color = classificationColor(cls);
      canvas.drawCircle(
        Offset(_xOf(ply, size), _yOf(whiteCpHistory[ply], size)),
        3.5,
        dotPaint,
      );
    }

    final markerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final markerX = _xOf(currentPly.clamp(0, whiteCpHistory.length - 1), size);
    canvas.drawLine(
      Offset(markerX, 0),
      Offset(markerX, size.height),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EvalGraphPainter oldDelegate) {
    return oldDelegate.whiteCpHistory != whiteCpHistory ||
        oldDelegate.currentPly != currentPly ||
        oldDelegate.classifications != classifications;
  }
}
