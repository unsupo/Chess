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

  /// Square to show a move-quality badge on (typically the last move's
  /// destination), or `null` for no badge. Deliberately primitive —
  /// `core/widgets/` has no dependency on the `MoveClassification` enum
  /// that decides [badgeSymbol]/[badgeColor]; the caller resolves that.
  final String? badgeSquare;
  final String? badgeSymbol;
  final Color? badgeColor;

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
    this.badgeSquare,
    this.badgeSymbol,
    this.badgeColor,
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

class ChessBoardWidgetState extends State<ChessBoardWidget>
    with TickerProviderStateMixin {
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

  // Active move animation (tap moves or bot moves)
  late AnimationController _moveController;
  late Animation<double> _moveAnimation;
  _ActiveMoveAnimation? _activeAnimation;

  // Snap-back animation for cancelled/illegal drag-drops
  late AnimationController _snapBackController;
  late Animation<double> _snapBackAnimation;
  _SnapBackAnimation? _snapBack;

  // Pre-computed 8×8 grid of square names for the current orientation.
  late List<List<String>> _grid;

  @override
  void initState() {
    super.initState();
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _moveAnimation =
        CurvedAnimation(parent: _moveController, curve: Curves.easeOutCubic)
          ..addListener(() {
            if (mounted) setState(() {});
          });

    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _snapBackAnimation =
        CurvedAnimation(parent: _snapBackController, curve: Curves.easeOutCubic)
          ..addListener(() {
            if (mounted) setState(() {});
          });

    _initFrom(widget.fen);
  }

  @override
  void dispose() {
    _moveController.dispose();
    _snapBackController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChessBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final orientationChanged = widget.orientation != oldWidget.orientation;
    final fenChanged = widget.fen != oldWidget.fen;
    final evalFinishedOutOfSync =
        widget.interactive &&
        !oldWidget.interactive &&
        _chess.fen != widget.fen;

    if (orientationChanged) {
      _cancelAnimations();
      setState(() => _initFrom(widget.fen));
      return;
    }

    if (fenChanged) {
      if (_chess.fen == widget.fen) {
        // Local board already matches widget.fen (e.g. from user move).
        return;
      }

      // Check if this is an incoming move (e.g. bot reply) that can be animated smoothly.
      if (widget.lastMoveFrom != null &&
          widget.lastMoveTo != null &&
          _canAnimateMove(widget.lastMoveFrom!, widget.lastMoveTo!)) {
        _startMoveAnimation(
          from: widget.lastMoveFrom!,
          to: widget.lastMoveTo!,
          targetFen: widget.fen,
        );
      } else {
        _cancelAnimations();
        setState(() => _initFrom(widget.fen));
      }
    } else if (evalFinishedOutOfSync) {
      _cancelAnimations();
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
    _cancelAnimations();
    setState(() => _initFrom(widget.fen));
  }

  void _cancelAnimations() {
    if (_activeAnimation != null) {
      _moveController.stop();
      _chess.load(_activeAnimation!.targetFen);
      _activeAnimation = null;
    }
    if (_snapBack != null) {
      _snapBackController.stop();
      _snapBack = null;
    }
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

  Offset _squareCenter(String square, double sq) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]);
    final col = _whiteDown ? file : 7 - file;
    final row = _whiteDown ? 8 - rank : rank - 1;
    return Offset(col * sq, row * sq);
  }

  bool _canAnimateMove(String from, String to) {
    if (from.length != 2 || to.length != 2) return false;
    final piece = _chess.get(from);
    return piece != null;
  }

  // ── animation triggers ────────────────────────────────────────────────────

  void _startMoveAnimation({
    required String from,
    required String to,
    required String targetFen,
    VoidCallback? onComplete,
  }) {
    final sq = _alignedSize / 8;
    final piece = _chess.get(from);
    if (piece == null) {
      _chess.load(targetFen);
      setState(() {});
      onComplete?.call();
      return;
    }

    final colorCode = piece.color == ch.Color.WHITE ? 'w' : 'b';
    final pieceCode = '$colorCode${piece.type.name.toUpperCase()}';
    final startOffset = _squareCenter(from, sq);
    final targetOffset = _squareCenter(to, sq);

    // Castling secondary rook detection
    String? rookPieceCode;
    Offset? rookStartOffset;
    Offset? rookTargetOffset;
    String? rookFrom;

    if (piece.type == ch.PieceType.KING) {
      if (from == 'e1' && to == 'g1') {
        rookPieceCode = 'wR';
        rookFrom = 'h1';
        rookStartOffset = _squareCenter('h1', sq);
        rookTargetOffset = _squareCenter('f1', sq);
      } else if (from == 'e1' && to == 'c1') {
        rookPieceCode = 'wR';
        rookFrom = 'a1';
        rookStartOffset = _squareCenter('a1', sq);
        rookTargetOffset = _squareCenter('d1', sq);
      } else if (from == 'e8' && to == 'g8') {
        rookPieceCode = 'bR';
        rookFrom = 'h8';
        rookStartOffset = _squareCenter('h8', sq);
        rookTargetOffset = _squareCenter('f8', sq);
      } else if (from == 'e8' && to == 'c8') {
        rookPieceCode = 'bR';
        rookFrom = 'a8';
        rookStartOffset = _squareCenter('a8', sq);
        rookTargetOffset = _squareCenter('d8', sq);
      }
    }

    // Capture detection (including en passant)
    String? capturedPieceCode;
    Offset? capturedOffset;
    final destPiece = _chess.get(to);
    if (destPiece != null) {
      final destColor = destPiece.color == ch.Color.WHITE ? 'w' : 'b';
      capturedPieceCode = '$destColor${destPiece.type.name.toUpperCase()}';
      capturedOffset = targetOffset;
    } else if (piece.type == ch.PieceType.PAWN && from[0] != to[0]) {
      // En passant capture
      final epSquare = '${to[0]}${from[1]}';
      final epPiece = _chess.get(epSquare);
      if (epPiece != null) {
        final epColor = epPiece.color == ch.Color.WHITE ? 'w' : 'b';
        capturedPieceCode = '$epColor${epPiece.type.name.toUpperCase()}';
        capturedOffset = _squareCenter(epSquare, sq);
      }
    }

    _activeAnimation = _ActiveMoveAnimation(
      from: from,
      to: to,
      pieceCode: pieceCode,
      startOffset: startOffset,
      targetOffset: targetOffset,
      capturedPieceCode: capturedPieceCode,
      capturedOffset: capturedOffset,
      rookPieceCode: rookPieceCode,
      rookStartOffset: rookStartOffset,
      rookTargetOffset: rookTargetOffset,
      rookFrom: rookFrom,
      targetFen: targetFen,
      onComplete: onComplete,
    );

    _moveController.forward(from: 0.0).then((_) {
      if (!mounted || _activeAnimation == null) return;
      _chess.load(targetFen);
      final callback = _activeAnimation?.onComplete;
      setState(() {
        _activeAnimation = null;
        _selected = null;
        _targets = [];
        _captures = {};
      });
      callback?.call();
    });
  }

  void _startSnapBackAnimation({
    required String pieceCode,
    required String sourceSquare,
    required Offset fromOffset,
    required Offset toOffset,
  }) {
    _snapBack = _SnapBackAnimation(
      pieceCode: pieceCode,
      sourceSquare: sourceSquare,
      fromOffset: fromOffset,
      toOffset: toOffset,
    );
    _snapBackController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      setState(() {
        _snapBack = null;
        _selected = null;
        _targets = [];
        _captures = {};
      });
    });
  }

  // ── interaction ───────────────────────────────────────────────────────────

  void _onTap(Offset local) {
    if (!widget.interactive || _activeAnimation != null) return;
    final sq = _alignedSize / 8;
    final col = (local.dx / sq).floor().clamp(0, 7);
    final row = (local.dy / sq).floor().clamp(0, 7);
    _onSquareTapped(_grid[row][col]);
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.interactive || _activeAnimation != null) return;
    _panStart = d.localPosition;
    _isDragging = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.interactive || _panStart == null || _activeAnimation != null) {
      return;
    }
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
    final code = _draggingCode;

    setState(() {
      _isDragging = false;
      _draggingFrom = null;
      _draggingCode = null;
      _dragPosition = null;
    });
    _panStart = null;

    if (dropPos == null || from == null || code == null) return;
    final sq = _alignedSize / 8;
    final col = (dropPos.dx / sq).floor().clamp(0, 7);
    final row = (dropPos.dy / sq).floor().clamp(0, 7);
    final target = _grid[row][col];

    if (_targets.contains(target)) {
      _commitMove(from, target, wasDragged: true);
    } else if (target != from) {
      // Smooth snap-back glide from drop point back to source square
      _startSnapBackAnimation(
        pieceCode: code,
        sourceSquare: from,
        fromOffset: dropPos - Offset(sq / 2, sq / 2),
        toOffset: _squareCenter(from, sq),
      );
    } else {
      setState(() {
        _selected = null;
        _targets = [];
        _captures = {};
      });
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
      setState(() {
        _selected = null;
        _targets = [];
        _captures = {};
      });
      return;
    }

    if (_targets.contains(square)) {
      _commitMove(_selected!, square, wasDragged: false);
      return;
    }

    if (isOwn) {
      _select(square);
    } else {
      setState(() {
        _selected = null;
        _targets = [];
        _captures = {};
      });
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

  Future<void> _commitMove(
    String from,
    String to, {
    bool wasDragged = false,
  }) async {
    final moves = _chess.generate_moves({'square': from});
    final isPromotion = moves.any(
      (m) => ch.Chess.algebraic(m.to) == to && m.promotion != null,
    );

    String? promotion;
    if (isPromotion) {
      promotion = await _askPromotion();
      if (promotion == null || !mounted) return;
    }

    final simulated = ch.Chess()..load(_chess.fen);
    simulated.move({'from': from, 'to': to, 'promotion': promotion});
    final targetFen = simulated.fen;

    if (wasDragged) {
      // Piece was already placed at destination by hand — update immediately
      _chess.move({'from': from, 'to': to, 'promotion': promotion});
      setState(() {
        _selected = null;
        _targets = [];
        _captures = {};
      });
      widget.onMove(from, to, promotion: promotion);
    } else {
      // Tap-tap move — smoothly glide piece across the board
      _startMoveAnimation(
        from: from,
        to: to,
        targetFen: targetFen,
        onComplete: () {
          widget.onMove(from, to, promotion: promotion);
        },
      );
    }
  }

  Future<String?> _askPromotion() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF243324),
        title: const Text(
          'Promote pawn',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
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
            // Layer 1: coloured squares + move/check highlights + legal hints
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
            // Layer 2: pieces (source square hidden while dragging or in flight)
            ..._buildPieces(sq),
            // Layer 3: coordinates
            ..._buildCoords(sq, aligned),
            // Layer 4: animated gliding pieces (active move, castling, snap-back, drag)
            ..._buildAnimatedOverlays(sq),
            // Layer 5: move-quality badge (best/blunder/mate/...)
            ..._buildClassificationBadge(sq, aligned),
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

        // If piece is currently dragged, snap-backed, or in flight, skip static render
        if (square == _draggingFrom) continue;
        if (_snapBack != null && square == _snapBack!.sourceSquare) continue;
        if (_activeAnimation != null) {
          if (square == _activeAnimation!.from) continue;
          if (square == _activeAnimation!.rookFrom) continue;
        }

        final piece = _chess.get(square);
        if (piece == null) continue;
        final colorCode = piece.color == ch.Color.WHITE ? 'w' : 'b';
        final code = '$colorCode${piece.type.name.toUpperCase()}';

        // If this square is receiving a capture, smoothly fade it out as attacker lands
        if (_activeAnimation != null &&
            square == _activeAnimation!.to &&
            _activeAnimation!.capturedPieceCode != null) {
          final t = _moveAnimation.value;
          final opacity = (1.0 - (t - 0.5) * 2.0).clamp(0.0, 1.0);
          if (opacity > 0) {
            result.add(
              Positioned(
                left: col * sq,
                top: row * sq,
                width: sq,
                height: sq,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: opacity,
                    child: _pieceWidget(code, sq),
                  ),
                ),
              ),
            );
          }
          continue;
        }

        result.add(
          Positioned(
            left: col * sq,
            top: row * sq,
            width: sq,
            height: sq,
            child: IgnorePointer(child: _pieceWidget(code, sq)),
          ),
        );
      }
    }
    return result;
  }

  List<Widget> _buildAnimatedOverlays(double sq) {
    final overlays = <Widget>[];

    // 1. Active move animation (tap moves or bot moves)
    if (_activeAnimation != null) {
      final t = _moveAnimation.value;
      final currentPos = Offset.lerp(
        _activeAnimation!.startOffset,
        _activeAnimation!.targetOffset,
        t,
      )!;

      overlays.add(
        Positioned(
          left: currentPos.dx,
          top: currentPos.dy,
          width: sq,
          height: sq,
          child: IgnorePointer(
            child: _pieceWidget(_activeAnimation!.pieceCode, sq),
          ),
        ),
      );

      // Castling secondary rook glide
      if (_activeAnimation!.rookPieceCode != null &&
          _activeAnimation!.rookStartOffset != null &&
          _activeAnimation!.rookTargetOffset != null) {
        final rookPos = Offset.lerp(
          _activeAnimation!.rookStartOffset!,
          _activeAnimation!.rookTargetOffset!,
          t,
        )!;
        overlays.add(
          Positioned(
            left: rookPos.dx,
            top: rookPos.dy,
            width: sq,
            height: sq,
            child: IgnorePointer(
              child: _pieceWidget(_activeAnimation!.rookPieceCode!, sq),
            ),
          ),
        );
      }
    }

    // 2. Snap-back animation for cancelled or illegal drags
    if (_snapBack != null) {
      final t = _snapBackAnimation.value;
      final pos = Offset.lerp(_snapBack!.fromOffset, _snapBack!.toOffset, t)!;
      overlays.add(
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: sq,
          height: sq,
          child: IgnorePointer(child: _pieceWidget(_snapBack!.pieceCode, sq)),
        ),
      );
    }

    // 3. Floating piece following user drag pointer
    if (_isDragging && _draggingCode != null && _dragPosition != null) {
      overlays.add(
        Positioned(
          left: _dragPosition!.dx - sq / 2,
          top: _dragPosition!.dy - sq / 2,
          width: sq,
          height: sq,
          child: IgnorePointer(child: _pieceWidget(_draggingCode!, sq)),
        ),
      );
    }

    return overlays;
  }

  /// Small move-quality chip (best-move star, blunder X, mate icon, ...)
  /// anchored at [widget.badgeSquare]'s top-right corner — mirroring
  /// Chess.com's board badges — but "tucked" inward when that square sits
  /// on the board's own top row or right column, so the badge never
  /// renders outside the board's bounds.
  List<Widget> _buildClassificationBadge(double sq, double aligned) {
    final square = widget.badgeSquare;
    final symbol = widget.badgeSymbol;
    final color = widget.badgeColor;
    if (square == null || symbol == null || color == null) return const [];

    const badgeSize = 18.0;
    final topLeft = _squareCenter(square, sq); // square's own top-left corner
    final onTopRow = topLeft.dy == 0;
    final onRightCol = topLeft.dx == aligned - sq;

    final centerX = onRightCol
        ? topLeft.dx + sq - badgeSize / 2
        : topLeft.dx + sq;
    final centerY = onTopRow ? topLeft.dy + badgeSize / 2 : topLeft.dy;

    return [
      Positioned(
        left: centerX - badgeSize / 2,
        top: centerY - badgeSize / 2,
        width: badgeSize,
        height: badgeSize,
        child: IgnorePointer(
          child: Container(
            key: const ValueKey('moveClassificationBadge'),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x40000000), blurRadius: 2),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              symbol,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildCoords(double sq, double boardSize) {
    const style = TextStyle(fontSize: 10, fontWeight: FontWeight.w700);
    final result = <Widget>[];

    for (int col = 0; col < 8; col++) {
      final file = _whiteDown ? col : 7 - col;
      final letter = String.fromCharCode('a'.codeUnitAt(0) + file);
      final isLight = (7 + col) % 2 == 0;
      result.add(
        Positioned(
          left: col * sq + sq - 12,
          top: boardSize - 14,
          child: IgnorePointer(
            child: Text(
              letter,
              style: style.copyWith(
                color: isLight
                    ? widget.theme.darkSquare
                    : widget.theme.lightSquare,
              ),
            ),
          ),
        ),
      );
    }

    for (int row = 0; row < 8; row++) {
      final rank = _whiteDown ? 8 - row : row + 1;
      final isLight = row % 2 == 0;
      result.add(
        Positioned(
          left: 2,
          top: row * sq + 2,
          child: IgnorePointer(
            child: Text(
              '$rank',
              style: style.copyWith(
                color: isLight
                    ? widget.theme.darkSquare
                    : widget.theme.lightSquare,
              ),
            ),
          ),
        ),
      );
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
        if (piece != null &&
            piece.type == ch.PieceType.KING &&
            piece.color == turn) {
          return sq;
        }
      }
    }
    return null;
  }
}

// ── Piece animation data structures ─────────────────────────────────────────

class _ActiveMoveAnimation {
  final String from;
  final String to;
  final String pieceCode;
  final Offset startOffset;
  final Offset targetOffset;
  final String? capturedPieceCode;
  final Offset? capturedOffset;
  final String? rookPieceCode;
  final Offset? rookStartOffset;
  final Offset? rookTargetOffset;
  final String? rookFrom;
  final String targetFen;
  final VoidCallback? onComplete;

  const _ActiveMoveAnimation({
    required this.from,
    required this.to,
    required this.pieceCode,
    required this.startOffset,
    required this.targetOffset,
    this.capturedPieceCode,
    this.capturedOffset,
    this.rookPieceCode,
    this.rookStartOffset,
    this.rookTargetOffset,
    this.rookFrom,
    required this.targetFen,
    this.onComplete,
  });
}

class _SnapBackAnimation {
  final String pieceCode;
  final String sourceSquare;
  final Offset fromOffset;
  final Offset toOffset;

  const _SnapBackAnimation({
    required this.pieceCode,
    required this.sourceSquare,
    required this.fromOffset,
    required this.toOffset,
  });
}

// ── Piece widget ──────────────────────────────────────────────────────────────

Widget buildChessPiece(String code, double size) => _pieceWidget(code, size);

Widget _pieceWidget(String code, double size) {
  switch (code) {
    case 'wP':
      return WhitePawn(size: size);
    case 'wN':
      return WhiteKnight(size: size);
    case 'wB':
      return WhiteBishop(size: size);
    case 'wR':
      return WhiteRook(size: size);
    case 'wQ':
      return WhiteQueen(size: size);
    case 'wK':
      return WhiteKing(size: size);
    case 'bP':
      return BlackPawn(size: size);
    case 'bN':
      return BlackKnight(size: size);
    case 'bB':
      return BlackBishop(size: size);
    case 'bR':
      return BlackRook(size: size);
    case 'bQ':
      return BlackQueen(size: size);
    case 'bK':
      return BlackKing(size: size);
    default:
      return const SizedBox.shrink();
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
