import 'package:flutter/material.dart';
import '../../../../core/widgets/chess_board/chess_board_widget.dart';
import 'game_theme.dart';

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
                          ? kAccent.withValues(alpha: 0.85)
                          : kBg.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _isResizing ? Colors.white : kAccentBorder,
                        width: 1,
                      ),
                    ),
                    child: CustomPaint(
                      painter: _ResizeGripPainter(
                        color: _isResizing ? kBg : kAccent,
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
