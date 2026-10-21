import 'package:flutter/material.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import 'game_theme.dart';
import 'move_history_feedback_bar.dart';

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
        color: kBg,
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
      ..color = kBorderSubtle
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      midPaint,
    );

    final linePaint = Paint()
      ..color = kAccent
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
