import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as ch;
import 'package:chess_vectors_flutter/chess_vectors_flutter.dart';
import 'board_theme.dart';

export 'board_theme.dart';

enum ChessBoardOrientation { white, black }

class ChessBoardWidget extends StatefulWidget {
  final String fen;
  final BoardTheme theme;
  final double size;
  final bool interactive;
  final ChessBoardOrientation orientation;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final void Function(String from, String to, {String? promotion}) onMove;

  const ChessBoardWidget({
    super.key,
    required this.fen,
    required this.size,
    required this.onMove,
    this.theme = BoardTheme.forest,
    this.interactive = true,
    this.orientation = ChessBoardOrientation.white,
    this.lastMoveFrom,
    this.lastMoveTo,
  });

  /// Rounds [rawSize] down to the nearest multiple of 8 pixels so every square
  /// on the 8×8 chessboard has exact integer pixel dimensions (`size - size % 8`).
  static double snapTo8Px(double rawSize, {double minSize = 96.0}) {
    final clamped = rawSize < minSize ? minSize : rawSize;
    final floored = clamped.floor();
    final aligned = floored - (floored % 8);
    return (aligned < 8 ? 8 : aligned).toDouble();
  }

  @override
  State<ChessBoardWidget> createState() => ChessBoardWidgetState();
}

class ChessBoardWidgetState extends State<ChessBoardWidget> {
  late ch.Chess _chess;
  String? _selected;
  List<String> _targets = [];
  Set<String> _captures = {};

  // Drag state
  bool _isDragging = false;
  String? _draggingFrom;
  String? _draggingCode;
  Offset? _dragPosition;
  Offset? _panStart;
  static const _kDragThreshold = 6.0;

  // Pre-computed 8×8 grid of square names for the current orientation.
  late List<List<String>> _grid;

  @override
  void initState() {
    super.initState();
    _initFrom(widget.fen);
  }

  @override
  void didUpdateWidget(ChessBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fenChanged = widget.fen != oldWidget.fen;
    final orientationChanged = widget.orientation != oldWidget.orientation;
    final evalFinishedOutOfSync =
        widget.interactive && !oldWidget.interactive && _chess.fen != widget.fen;
    if (fenChanged || orientationChanged || evalFinishedOutOfSync) {
      setState(() => _initFrom(widget.fen));
    }
  }

  void _initFrom(String fen) {
    _chess = ch.Chess();
    _chess.load(fen);
    _selected = null;
    _targets = [];
    _captures = {};
    _isDragging = false;
    _draggingFrom = null;
    _draggingCode = null;
    _dragPosition = null;
    _panStart = null;
    _grid = _buildGrid();
  }

  /// Called by GamePage on blunder — reverts the optimistic local move.
  void undoLastMove() {
    setState(() => _initFrom(widget.fen));
  }

  // ── grid / coordinates ────────────────────────────────────────────────────

  double get _alignedSize => ChessBoardWidget.snapTo8Px(widget.size);

  bool get _whiteDown => widget.orientation == ChessBoardOrientation.white;

  List<List<String>> _buildGrid() {
    return List.generate(8, (row) {
      return List.generate(8, (col) {
        final file = _whiteDown ? col : 7 - col;
        final rank = _whiteDown ? 8 - row : row + 1;
        return String.fromCharCode('a'.codeUnitAt(0) + file) + rank.toString();
      });
    });
  }

  // ── interaction ───────────────────────────────────────────────────────────

  void _onTap(Offset local) {
    if (!widget.interactive) return;
    final sq = _alignedSize / 8;
    final col = (local.dx / sq).floor().clamp(0, 7);
    final row = (local.dy / sq).floor().clamp(0, 7);
    _onSquareTapped(_grid[row][col]);
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.interactive) return;
    _panStart = d.localPosition;
    _isDragging = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.interactive || _panStart == null) return;
    final pos = d.localPosition;
    if (!_isDragging) {
      if ((pos - _panStart!).distance < _kDragThreshold) return;
      final sq = _alignedSize / 8;
      final col = (_panStart!.dx / sq).floor().clamp(0, 7);
      final row = (_panStart!.dy / sq).floor().clamp(0, 7);
      final square = _grid[row][col];
      final piece = _chess.get(square);
      if (piece == null || piece.color != _chess.turn) return;
      final colorCode = piece.color == ch.Color.WHITE ? 'w' : 'b';
      _isDragging = true;
      _draggingFrom = square;
      _draggingCode = '$colorCode${piece.type.name.toUpperCase()}';
      _dragPosition = pos;
      _select(square); // triggers setState
    } else {
      setState(() => _dragPosition = pos);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (!widget.interactive) return;
    if (!_isDragging) {
      if (_panStart != null) _onTap(_panStart!);
      _panStart = null;
      return;
    }
    final dropPos = _dragPosition;
    final from = _draggingFrom;
    setState(() {
      _isDragging = false;
      _draggingFrom = null;
      _draggingCode = null;
      _dragPosition = null;
    });
    _panStart = null;
    if (dropPos == null || from == null) return;
    final sq = _alignedSize / 8;
    final col = (dropPos.dx / sq).floor().clamp(0, 7);
    final row = (dropPos.dy / sq).floor().clamp(0, 7);
    final target = _grid[row][col];
    if (_targets.contains(target)) {
      _commitMove(from, target);
    } else if (target != from) {
      setState(() { _selected = null; _targets = []; _captures = {}; });
    }
  }

  void _onPanCancel() {
    setState(() {
      _isDragging = false;
      _draggingFrom = null;
      _draggingCode = null;
      _dragPosition = null;
      _selected = null;
      _targets = [];
      _captures = {};
    });
    _panStart = null;
  }

  void _onSquareTapped(String square) {
    final piece = _chess.get(square);
    final isOwn = piece != null && piece.color == _chess.turn;

    if (_selected == null) {
      if (isOwn) _select(square);
      return;
    }

    if (square == _selected) {
      setState(() { _selected = null; _targets = []; _captures = {}; });
      return;
    }

    if (_targets.contains(square)) {
      _commitMove(_selected!, square);
      return;
    }

    if (isOwn) {
      _select(square);
    } else {
      setState(() { _selected = null; _targets = []; _captures = {}; });
    }
  }

  void _select(String square) {
    final moves = _chess.generate_moves({'square': square});
    final targets = <String>[];
    final captures = <String>{};
    for (final m in moves) {
      final to = ch.Chess.algebraic(m.to);
      targets.add(to);
      if (_chess.get(to) != null) captures.add(to);
    }
    setState(() {
      _selected = square;
      _targets = targets;
      _captures = captures;
    });
  }

  Future<void> _commitMove(String from, String to) async {
    final moves = _chess.generate_moves({'square': from});
    final isPromotion =
        moves.any((m) => ch.Chess.algebraic(m.to) == to && m.promotion != null);

    String? promotion;
    if (isPromotion) {
      promotion = await _askPromotion();
      if (promotion == null || !mounted) return;
    }

    _chess.move({'from': from, 'to': to, 'promotion': promotion});
    setState(() { _selected = null; _targets = []; _captures = {}; });
    widget.onMove(from, to, promotion: promotion);
  }

  Future<String?> _askPromotion() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF243324),
        title: const Text('Promote pawn',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final p in ['q', 'r', 'b', 'n'])
              GestureDetector(
                onTap: () => Navigator.pop(ctx, p),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E4A2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _pieceWidget('w${p.toUpperCase()}', 48),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── rendering ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final aligned = _alignedSize;
    final sq = aligned / 8;
    final checkSq = _findCheckSquare();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      child: SizedBox(
        width: aligned,
        height: aligned,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Layer 1: coloured squares + hints
            CustomPaint(
              size: Size(aligned, aligned),
              painter: _BoardPainter(
                theme: widget.theme,
                grid: _grid,
                selected: _selected,
                targets: _targets,
                captures: _captures,
                lastFrom: widget.lastMoveFrom,
                lastTo: widget.lastMoveTo,
                checkSq: checkSq,
              ),
            ),
            // Layer 2: pieces (source square hidden while dragging)
            ..._buildPieces(sq),
            // Layer 3: coordinates
            ..._buildCoords(sq, aligned),
            // Layer 4: floating piece following the pointer
            if (_isDragging && _draggingCode != null && _dragPosition != null)
              Positioned(
                left: _dragPosition!.dx - sq / 2,
                top: _dragPosition!.dy - sq / 2,
                width: sq,
                height: sq,
                child: IgnorePointer(child: _pieceWidget(_draggingCode!, sq)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPieces(double sq) {
    final result = <Widget>[];
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final square = _grid[row][col];
        if (square == _draggingFrom) continue; // rendered as floating piece
        final piece = _chess.get(square);
        if (piece == null) continue;
        final colorCode = piece.color == ch.Color.WHITE ? 'w' : 'b';
        final code = '$colorCode${piece.type.name.toUpperCase()}';
        result.add(Positioned(
          left: col * sq,
          top: row * sq,
          width: sq,
          height: sq,
          child: IgnorePointer(
            child: _pieceWidget(code, sq),
          ),
        ));
      }
    }
    return result;
  }

  List<Widget> _buildCoords(double sq, double boardSize) {
    const style = TextStyle(fontSize: 10, fontWeight: FontWeight.w700);
    final result = <Widget>[];

    for (int col = 0; col < 8; col++) {
      final file = _whiteDown ? col : 7 - col;
      final letter = String.fromCharCode('a'.codeUnitAt(0) + file);
      final isLight = (7 + col) % 2 == 0;
      result.add(Positioned(
        left: col * sq + sq - 12,
        top: boardSize - 14,
        child: IgnorePointer(
          child: Text(letter,
              style: style.copyWith(
                  color: isLight ? widget.theme.darkSquare : widget.theme.lightSquare)),
        ),
      ));
    }

    for (int row = 0; row < 8; row++) {
      final rank = _whiteDown ? 8 - row : row + 1;
      final isLight = row % 2 == 0;
      result.add(Positioned(
        left: 2,
        top: row * sq + 2,
        child: IgnorePointer(
          child: Text('$rank',
              style: style.copyWith(
                  color: isLight ? widget.theme.darkSquare : widget.theme.lightSquare)),
        ),
      ));
    }

    return result;
  }

  String? _findCheckSquare() {
    if (!_chess.in_check) return null;
    final turn = _chess.turn;
    for (final file in 'abcdefgh'.split('')) {
      for (final rank in ['1', '2', '3', '4', '5', '6', '7', '8']) {
        final sq = '$file$rank';
        final piece = _chess.get(sq);
        if (piece != null && piece.color == turn && piece.type == ch.PieceType.KING) {
          return sq;
        }
      }
    }
    return null;
  }
}

// ── Piece widget ──────────────────────────────────────────────────────────────

Widget buildChessPiece(String code, double size) => _pieceWidget(code, size);

Widget _pieceWidget(String code, double size) {
  switch (code) {
    case 'wP': return WhitePawn(size: size);
    case 'wN': return WhiteKnight(size: size);
    case 'wB': return WhiteBishop(size: size);
    case 'wR': return WhiteRook(size: size);
    case 'wQ': return WhiteQueen(size: size);
    case 'wK': return WhiteKing(size: size);
    case 'bP': return BlackPawn(size: size);
    case 'bN': return BlackKnight(size: size);
    case 'bB': return BlackBishop(size: size);
    case 'bR': return BlackRook(size: size);
    case 'bQ': return BlackQueen(size: size);
    case 'bK': return BlackKing(size: size);
    default:   return const SizedBox.shrink();
  }
}

// ── Board painter ─────────────────────────────────────────────────────────────

class _BoardPainter extends CustomPainter {
  final BoardTheme theme;
  final List<List<String>> grid;
  final String? selected;
  final List<String> targets;
  final Set<String> captures;
  final String? lastFrom;
  final String? lastTo;
  final String? checkSq;

  const _BoardPainter({
    required this.theme,
    required this.grid,
    required this.selected,
    required this.targets,
    required this.captures,
    required this.lastFrom,
    required this.lastTo,
    required this.checkSq,
  });

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.selected != selected ||
      old.targets != targets ||
      old.captures != captures ||
      old.lastFrom != lastFrom ||
      old.lastTo != lastTo ||
      old.checkSq != checkSq ||
      old.theme != theme;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;

    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final square = grid[row][col];
        final isLight = (row + col) % 2 == 0;

        Color color = isLight ? theme.lightSquare : theme.darkSquare;

        if (square == lastFrom || square == lastTo) {
          color = Color.alphaBlend(theme.lastMove, color);
        }
        if (square == checkSq) {
          color = Color.alphaBlend(theme.check, color);
        }
        if (square == selected) {
          color = theme.selectedSquare;
        }

        canvas.drawRect(
          Rect.fromLTWH(col * sq, row * sq, sq, sq),
          Paint()..color = color,
        );

        // Legal move hints
        if (targets.contains(square)) {
          final cx = col * sq + sq / 2;
          final cy = row * sq + sq / 2;
          if (captures.contains(square)) {
            canvas.drawCircle(
              Offset(cx, cy),
              sq * 0.46,
              Paint()
                ..color = theme.legalMoveHint
                ..style = PaintingStyle.stroke
                ..strokeWidth = sq * 0.085,
            );
          } else {
            canvas.drawCircle(
              Offset(cx, cy),
              sq * 0.15,
              Paint()..color = theme.legalMoveHint,
            );
          }
        }
      }
    }
  }
}
