import 'dart:math' show min;
import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/chess_board/chess_board_widget.dart';
import '../../domain/entities/bot_personality.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import '../providers/game_provider.dart';
import '../widgets/chess_feature_widgets.dart';

// chess.com bot-play forest palette
const _bg = Color(0xFF1A2B1A);
const _card = Color(0xFF243324);
const _accent = Color(0xFF7BBF44);
const _muted = Color(0xFF8AAD8A);
const _accentFill = Color(0x287BBF44);
const _accentBorder = Color(0x647BBF44);
const _bubble = Color(0xFFF5F5F0);

// fixed heights used to size the board
const _botPanelH = 128.0;
const _playerBarH = 54.0;
const _controlsH = 220.0;

// side-panel layout: used instead of the bottom controls strip once the
// viewport is wide enough that a right-hand sidebar doesn't cramp the board.
const _sidePanelBreakpoint = 700.0;
const _sidebarWidthExpanded = 280.0;
const _sidebarWidthCollapsed = 56.0;
const _sidebarAnimDuration = Duration(milliseconds: 200);

class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  final _boardKey = GlobalKey<ChessBoardWidgetState>();

  // Pure in-memory UI state for the side panel — no persistence, always
  // starts expanded (see docs/features/controls_side_panel.md).
  bool _sidebarCollapsed = false;

  // Optional custom board size set via the drag-to-resize handle.
  double? _customBoardSize;

  void _toggleSidebar() =>
      setState(() => _sidebarCollapsed = !_sidebarCollapsed);

  void _newGame() => ref.read(gameProvider.notifier).newGame();
  void _flipBoard() => ref.read(gameProvider.notifier).flipBoard();

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: const Color(0xFF2E4A2E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFenDialog(String currentFen, String currentPgn) {
    final fenCtrl = TextEditingController(text: currentFen);
    final pgnCtrl = TextEditingController(text: currentPgn);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'FEN / PGN',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'FEN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('copyFenButton'),
                      onPressed: () =>
                          _copyToClipboard(fenCtrl.text.trim(), 'FEN'),
                      icon: const Icon(Icons.copy, size: 15, color: _accent),
                      label: const Text(
                        'Copy FEN',
                        style: TextStyle(color: _accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: const ValueKey('fenTextField'),
                  controller: fenCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Paste FEN string…',
                    hintStyle: TextStyle(color: _muted),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _muted),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _accent),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'PGN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('copyPgnButton'),
                      onPressed: () =>
                          _copyToClipboard(pgnCtrl.text.trim(), 'PGN'),
                      icon: const Icon(Icons.copy, size: 15, color: _accent),
                      label: const Text(
                        'Copy PGN',
                        style: TextStyle(color: _accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: const ValueKey('pgnTextField'),
                  controller: pgnCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Paste PGN…',
                    hintStyle: TextStyle(color: _muted),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _muted),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _muted)),
          ),
          TextButton(
            key: const ValueKey('loadPgnSubmitButton'),
            onPressed: () {
              final pgnInput = pgnCtrl.text.trim();
              if (pgnInput != currentPgn.trim()) {
                ref.read(gameProvider.notifier).loadFenOrPgn(pgnInput);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Load PGN', style: TextStyle(color: _accent)),
          ),
          TextButton(
            key: const ValueKey('loadFenSubmitButton'),
            onPressed: () {
              final fenInput = fenCtrl.text.trim();
              final pgnInput = pgnCtrl.text.trim();
              final notifier = ref.read(gameProvider.notifier);
              if (fenInput != currentFen.trim()) {
                notifier.loadFenOrPgn(fenInput);
              } else if (pgnInput != currentPgn.trim()) {
                notifier.loadFenOrPgn(pgnInput);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Load FEN', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog({
    required String message,
    required bool isDraw,
    required String fen,
    required String pgn,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final liveState = ref.watch(gameProvider);
          final review = liveState.gameReview;
          final humanIsWhite = !liveState.boardFlipped;
          final youReview = review?.playerReview(humanIsWhite: humanIsWhite);
          final botReview = review?.botReview(humanIsWhite: humanIsWhite);

          return AlertDialog(
            key: const ValueKey('gameOverDialog'),
            backgroundColor: _card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _accent, width: 1.5),
            ),
            title: Row(
              children: [
                Icon(
                  isDraw
                      ? Icons.handshake_outlined
                      : Icons.emoji_events_outlined,
                  color: _accent,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  isDraw ? 'Game Drawn' : 'Game Over',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (youReview != null &&
                      botReview != null &&
                      (youReview.moveCount > 0 || botReview.moveCount > 0)) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text(
                          'GAME REVIEW',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        if (liveState.isAnalyzingGameReview) ...[
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: _accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Analyzing…',
                            style: TextStyle(color: _accent, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _PlayerReviewCard(
                            key: const ValueKey('youReviewCard'),
                            emoji: '👤',
                            name: 'You',
                            colorLabel: humanIsWhite ? 'White' : 'Black',
                            review: youReview,
                            highlight: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PlayerReviewCard(
                            key: const ValueKey('botReviewCard'),
                            emoji: liveState.personality.emoji,
                            name: liveState.personality.name,
                            colorLabel: humanIsWhite ? 'Black' : 'White',
                            review: botReview,
                            highlight: false,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'View Board',
                  style: TextStyle(color: _muted),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showFenDialog(fen, pgn);
                },
                child: const Text(
                  'FEN / PGN',
                  style: TextStyle(color: _accent),
                ),
              ),
              ElevatedButton(
                key: const ValueKey('gameOverModalNewGameButton'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _newGame();
                },
                child: const Text(
                  'New Game',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);

    ref.listen<GameState>(gameProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      // undoRequested is kept for board undo (triggered via game_page listener)
      if (next.undoRequested && !(prev?.undoRequested ?? false)) {
        _boardKey.currentState?.undoLastMove();
        ref.read(gameProvider.notifier).clearUndo();
      }
      if (next.gameOverMessage != null &&
          next.gameOverMessage != prev?.gameOverMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showGameOverDialog(
            message: next.gameOverMessage!,
            isDraw: next.isDraw,
            fen: next.fen,
            pgn: next.pgn,
          );
        });
      }
    });

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useSidePanel = constraints.maxWidth >= _sidePanelBreakpoint;
            const moveBarH = 44.0;

            final maxBoardSize = useSidePanel
                ? min(
                    constraints.maxWidth -
                        (_sidebarCollapsed
                            ? _sidebarWidthCollapsed
                            : _sidebarWidthExpanded),
                    constraints.maxHeight - _botPanelH - _playerBarH - moveBarH,
                  ).clamp(100.0, 1000.0)
                : min(
                    constraints.maxWidth,
                    constraints.maxHeight -
                        _botPanelH -
                        _playerBarH -
                        moveBarH -
                        _controlsH,
                  ).clamp(100.0, 600.0);

            final effectiveBoardSize = ChessBoardWidget.snapTo8Px(
              (_customBoardSize ?? maxBoardSize).clamp(96.0, maxBoardSize),
            );

            final boardWidget = ChessBoardWidget(
              key: _boardKey,
              fen: state.displayedFen,
              size: effectiveBoardSize,
              theme: BoardTheme.forest,
              interactive:
                  !state.isEvaluating &&
                  !state.isDisplayedGameOver &&
                  (!state.isViewingHistory || !state.lockHistory),
              orientation: state.boardFlipped
                  ? ChessBoardOrientation.black
                  : ChessBoardOrientation.white,
              lastMoveFrom: state.displayedLastMoveFrom,
              lastMoveTo: state.displayedLastMoveTo,
              onMove: (from, to, {promotion}) {
                final chess = ch.Chess();
                chess.load(state.displayedFen);
                chess.move({'from': from, 'to': to, 'promotion': promotion});
                ref.read(gameProvider.notifier).onUserMove(chess.fen);
              },
            );

            final resizableBoard = ResizableBoardFrame(
              boardSize: effectiveBoardSize,
              minSize: 96.0,
              maxSize: maxBoardSize,
              onSizeChanged: (nextSize) {
                setState(() => _customBoardSize = nextSize);
              },
              child: boardWidget,
            );

            final boardStack = Stack(
              alignment: Alignment.bottomCenter,
              children: [
                resizableBoard,
                if (state.gameOverMessage != null && !state.isViewingHistory)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _GameOverBanner(
                      key: const ValueKey('gameOverBanner'),
                      message: state.gameOverMessage!,
                      isDraw: state.isDraw,
                      onReview: () => _showGameOverDialog(
                        message: state.gameOverMessage!,
                        isDraw: state.isDraw,
                        fen: state.fen,
                        pgn: state.pgn,
                      ),
                      onNewGame: _newGame,
                    ),
                  ),
              ],
            );

            final board = state.showEvalBar
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      EvalBar(
                        whiteCp: state.currentWhiteCp,
                        height: effectiveBoardSize,
                        boardFlipped: state.boardFlipped,
                      ),
                      const SizedBox(width: 6),
                      boardStack,
                    ],
                  )
                : boardStack;

            final botIsWhite = state.boardFlipped;
            final botMaterial = state.materialFor(isWhite: botIsWhite);
            final playerMaterial = state.materialFor(isWhite: !botIsWhite);
            final botTimeMs = botIsWhite
                ? state.whiteTimeMs
                : state.blackTimeMs;
            final playerTimeMs = botIsWhite
                ? state.blackTimeMs
                : state.whiteTimeMs;
            final isClockRunning =
                state.timeControl.isTimed &&
                !state.isGameOver &&
                !state.isViewingHistory &&
                state.sanMoves.isNotEmpty;
            final isBotClockActive =
                isClockRunning && (state.isWhiteTurn == botIsWhite);
            final isPlayerClockActive =
                isClockRunning && (state.isWhiteTurn != botIsWhite);

            final notifier = ref.read(gameProvider.notifier);

            final moveBar = Column(
              children: [
                MoveHistoryAndFeedbackBar(
                  sanMoves: state.sanMoves,
                  currentPly: state.currentPly,
                  classifications: state.liveMoveClassifications,
                  evalScoreText: state.formattedEvalScore,
                  whiteCp: state.currentWhiteCp,
                  openingName: state.openingName,
                  onSelectPly: notifier.selectPly,
                ),
                if (state.showEvalBar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: EvalGraph(
                      whiteCpHistory: state.plyWhiteCpHistory,
                      classifications: state.liveMoveClassifications,
                      currentPly: state.currentPly,
                      onSelectPly: notifier.selectPly,
                    ),
                  ),
              ],
            );

            if (useSidePanel) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _BotPanel(
                          personality: state.personality,
                          botElo: state.botElo,
                          isThinking: state.isEvaluating,
                          material: botMaterial,
                          crowns: state.crownsForBot(state.personality.id),
                          timeControl: state.timeControl,
                          botTimeMs: botTimeMs,
                          isBotClockActive: isBotClockActive,
                        ),
                        Expanded(child: Center(child: board)),
                        moveBar,
                        _PlayerBar(
                          flipped: state.boardFlipped,
                          material: playerMaterial,
                          canStepBack: state.canStepBack,
                          canStepForward: state.canStepForward,
                          currentPly: state.currentPly,
                          totalPlies: state.sanMoves.length,
                          isViewingHistory: state.isViewingHistory,
                          lockHistory: state.lockHistory,
                          onStepBack: notifier.stepBack,
                          onStepForward: notifier.stepForward,
                          timeControl: state.timeControl,
                          playerTimeMs: playerTimeMs,
                          isPlayerClockActive: isPlayerClockActive,
                        ),
                      ],
                    ),
                  ),
                  _Sidebar(
                    collapsed: _sidebarCollapsed,
                    onToggle: _toggleSidebar,
                    elo: state.botElo,
                    selectedPersonality: state.personality,
                    onPersonalitySelected: (p) => notifier.setPersonality(p),
                    onEloChanged: (val) => notifier.setDifficulty(val),
                    onNewGame: _newGame,
                    onFlipBoard: _flipBoard,
                    onLoadFen: () => _showFenDialog(state.fen, state.pgn),
                    canStepBack: state.canStepBack,
                    canStepForward: state.canStepForward,
                    onStepBack: notifier.stepBack,
                    onStepForward: notifier.stepForward,
                    lockHistory: state.lockHistory,
                    onLockHistoryChanged: notifier.setLockHistory,
                    antiBlunderEnabled: state.antiBlunderEnabled,
                    onAntiBlunderChanged: notifier.setAntiBlunderEnabled,
                    mateSafetyEnabled: state.mateSafetyEnabled,
                    mateSafetyN: state.mateSafetyN,
                    onMateSafetyEnabledChanged: notifier.setMateSafetyEnabled,
                    onMateSafetyNChanged: notifier.setMateSafetyN,
                    playSide: state.playSide,
                    onPlaySideChanged: notifier.setPlaySide,
                    timeControl: state.timeControl,
                    onTimeControlChanged: notifier.setTimeControl,
                    botCrowns: state.botCrowns,
                    selectedOpening: state.selectedOpening,
                    onOpeningChanged: notifier.setOpening,
                    showEvalBar: state.showEvalBar,
                    onShowEvalBarChanged: notifier.setShowEvalBar,
                  ),
                ],
              );
            }

            return Column(
              children: [
                _BotPanel(
                  personality: state.personality,
                  botElo: state.botElo,
                  isThinking: state.isEvaluating,
                  material: botMaterial,
                  crowns: state.crownsForBot(state.personality.id),
                  timeControl: state.timeControl,
                  botTimeMs: botTimeMs,
                  isBotClockActive: isBotClockActive,
                ),
                board,
                moveBar,
                _PlayerBar(
                  flipped: state.boardFlipped,
                  material: playerMaterial,
                  canStepBack: state.canStepBack,
                  canStepForward: state.canStepForward,
                  currentPly: state.currentPly,
                  totalPlies: state.sanMoves.length,
                  isViewingHistory: state.isViewingHistory,
                  lockHistory: state.lockHistory,
                  onStepBack: notifier.stepBack,
                  onStepForward: notifier.stepForward,
                  timeControl: state.timeControl,
                  playerTimeMs: playerTimeMs,
                  isPlayerClockActive: isPlayerClockActive,
                ),
                _ControlsPanel(
                  elo: state.botElo,
                  selectedPersonality: state.personality,
                  onPersonalitySelected: (p) => notifier.setPersonality(p),
                  onEloChanged: (val) => notifier.setDifficulty(val),
                  onNewGame: _newGame,
                  onFlipBoard: _flipBoard,
                  onLoadFen: () => _showFenDialog(state.fen, state.pgn),
                  canStepBack: state.canStepBack,
                  canStepForward: state.canStepForward,
                  onStepBack: notifier.stepBack,
                  onStepForward: notifier.stepForward,
                  lockHistory: state.lockHistory,
                  onLockHistoryChanged: notifier.setLockHistory,
                  antiBlunderEnabled: state.antiBlunderEnabled,
                  onAntiBlunderChanged: notifier.setAntiBlunderEnabled,
                  mateSafetyEnabled: state.mateSafetyEnabled,
                  mateSafetyN: state.mateSafetyN,
                  onMateSafetyEnabledChanged: notifier.setMateSafetyEnabled,
                  onMateSafetyNChanged: notifier.setMateSafetyN,
                  playSide: state.playSide,
                  onPlaySideChanged: notifier.setPlaySide,
                  timeControl: state.timeControl,
                  onTimeControlChanged: notifier.setTimeControl,
                  botCrowns: state.botCrowns,
                  selectedOpening: state.selectedOpening,
                  onOpeningChanged: notifier.setOpening,
                  showEvalBar: state.showEvalBar,
                  onShowEvalBarChanged: notifier.setShowEvalBar,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Game Over / Draw Banner ───────────────────────────────────────────────────

class _PlayerReviewCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String colorLabel;
  final PlayerGameReview review;
  final bool highlight;

  const _PlayerReviewCard({
    super.key,
    required this.emoji,
    required this.name,
    required this.colorLabel,
    required this.review,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight ? _accentFill : const Color(0xFF1A2B1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? _accent : const Color(0xFF3A5A3A),
          width: highlight ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          Text(colorLabel, style: const TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 8),
          const Text(
            'Performance ELO',
            style: TextStyle(color: _muted, fontSize: 10),
          ),
          Text(
            '${review.estimatedElo}',
            style: TextStyle(
              color: highlight ? _accent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Accuracy',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
              Text(
                '${review.accuracyPercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Avg. CPL',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
              Text(
                '${review.acpl.round()}',
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GameOverBanner extends StatelessWidget {
  final String message;
  final bool isDraw;
  final VoidCallback onReview;
  final VoidCallback onNewGame;

  const _GameOverBanner({
    super.key,
    required this.message,
    required this.isDraw,
    required this.onReview,
    required this.onNewGame,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isDraw ? Icons.handshake_outlined : Icons.emoji_events_outlined,
            color: _accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onReview,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            child: const Text(
              'Review',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onNewGame,
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text(
              'New Game',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bot panel ─────────────────────────────────────────────────────────────────

class _BotPanel extends StatelessWidget {
  final BotPersonality personality;
  final int botElo;
  final bool isThinking;
  final SideMaterial material;
  final int crowns;
  final TimeControl timeControl;
  final int botTimeMs;
  final bool isBotClockActive;

  const _BotPanel({
    required this.personality,
    required this.botElo,
    required this.isThinking,
    required this.material,
    required this.crowns,
    required this.timeControl,
    required this.botTimeMs,
    required this.isBotClockActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF2E4A2E),
            child: Text(
              personality.emoji,
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      personality.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    BotCrownsWidget(
                      key: const ValueKey('botPanelCrowns'),
                      crowns: crowns,
                      size: 11,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${_eloLabel(botElo)} · $botElo',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isThinking)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        ),
                      ),
                    MoveTimeWidget(
                      key: const ValueKey('botClockBadge'),
                      timeControl: timeControl,
                      timeMs: botTimeMs,
                      isActive: isBotClockActive,
                      isDarkTheme: true,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    color: _bubble,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    personality.greeting,
                    style: const TextStyle(
                      color: Color(0xFF1A2B1A),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _CapturedPiecesBar(
                  key: const ValueKey('botCapturedBar'),
                  material: material,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Player bar ────────────────────────────────────────────────────────────────

class _PlayerBar extends StatelessWidget {
  final bool flipped;
  final SideMaterial material;
  final bool canStepBack;
  final bool canStepForward;
  final int currentPly;
  final int totalPlies;
  final bool isViewingHistory;
  final bool lockHistory;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final TimeControl timeControl;
  final int playerTimeMs;
  final bool isPlayerClockActive;

  const _PlayerBar({
    required this.flipped,
    required this.material,
    required this.canStepBack,
    required this.canStepForward,
    required this.currentPly,
    required this.totalPlies,
    required this.isViewingHistory,
    required this.lockHistory,
    required this.onStepBack,
    required this.onStepForward,
    required this.timeControl,
    required this.playerTimeMs,
    required this.isPlayerClockActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF2E4A2E),
            child: const Text('👤', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (isViewingHistory) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _accentFill,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _accentBorder),
                      ),
                      child: Text(
                        lockHistory
                            ? 'Ply $currentPly/$totalPlies (View Only)'
                            : 'Ply $currentPly/$totalPlies (Editable)',
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'Playing as ${flipped ? "Black" : "White"}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(width: 8),
          _HistoryStepBtn(
            key: const ValueKey('playerBarStepBackButton'),
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Previous move',
            enabled: canStepBack,
            onTap: onStepBack,
          ),
          const SizedBox(width: 4),
          _HistoryStepBtn(
            key: const ValueKey('playerBarStepForwardButton'),
            icon: Icons.arrow_forward_ios,
            tooltip: 'Next move',
            enabled: canStepForward,
            onTap: onStepForward,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _CapturedPiecesBar(
                key: const ValueKey('playerCapturedBar'),
                material: material,
              ),
            ),
          ),
          const SizedBox(width: 8),
          MoveTimeWidget(
            key: const ValueKey('playerClockBadge'),
            timeControl: timeControl,
            timeMs: playerTimeMs,
            isActive: isPlayerClockActive,
            isDarkTheme: false,
          ),
        ],
      ),
    );
  }
}

class _HistoryStepBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _HistoryStepBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2B1A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: enabled ? _accentBorder : const Color(0xFF3A5A3A),
              ),
            ),
            child: Icon(icon, color: enabled ? _accent : _muted, size: 15),
          ),
        ),
      ),
    );
  }
}

class _CapturedPiecesBar extends StatelessWidget {
  final SideMaterial material;

  const _CapturedPiecesBar({super.key, required this.material});

  @override
  Widget build(BuildContext context) {
    final ptsLabel =
        '${material.capturedScore} ${material.capturedScore == 1 ? 'pt' : 'pts'}';
    final diffLabel = material.netAdvantage > 0
        ? ' (+${material.netAdvantage})'
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (material.capturedPieces.isNotEmpty) ...[
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFD8E4D0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Wrap(
                spacing: -3,
                runSpacing: 2,
                children: [
                  for (final code in material.capturedPieces)
                    buildChessPiece(code, 16),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: material.netAdvantage > 0
                  ? _accentFill
                  : const Color(0xFF1A2B1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: material.netAdvantage > 0
                    ? _accentBorder
                    : const Color(0xFF3A5A3A),
              ),
            ),
            child: Text(
              '$ptsLabel$diffLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: material.netAdvantage > 0 ? _accent : _muted,
                fontWeight: material.netAdvantage > 0
                    ? FontWeight.bold
                    : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────────────

class _ControlsPanel extends StatelessWidget {
  final int elo;
  final BotPersonality selectedPersonality;
  final ValueChanged<BotPersonality> onPersonalitySelected;
  final ValueChanged<int> onEloChanged;
  final VoidCallback onNewGame;
  final VoidCallback onFlipBoard;
  final VoidCallback onLoadFen;
  final bool canStepBack;
  final bool canStepForward;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final bool lockHistory;
  final ValueChanged<bool> onLockHistoryChanged;
  final bool antiBlunderEnabled;
  final ValueChanged<bool> onAntiBlunderChanged;
  final bool mateSafetyEnabled;
  final int mateSafetyN;
  final ValueChanged<bool> onMateSafetyEnabledChanged;
  final ValueChanged<int> onMateSafetyNChanged;
  final PlaySide playSide;
  final ValueChanged<PlaySide> onPlaySideChanged;
  final TimeControl timeControl;
  final ValueChanged<TimeControl> onTimeControlChanged;
  final Map<String, int> botCrowns;
  final ChessOpening? selectedOpening;
  final ValueChanged<ChessOpening?> onOpeningChanged;
  final bool showEvalBar;
  final ValueChanged<bool> onShowEvalBarChanged;

  const _ControlsPanel({
    required this.elo,
    required this.selectedPersonality,
    required this.onPersonalitySelected,
    required this.onEloChanged,
    required this.onNewGame,
    required this.onFlipBoard,
    required this.onLoadFen,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStepBack,
    required this.onStepForward,
    required this.lockHistory,
    required this.onLockHistoryChanged,
    required this.antiBlunderEnabled,
    required this.onAntiBlunderChanged,
    required this.mateSafetyEnabled,
    required this.mateSafetyN,
    required this.onMateSafetyEnabledChanged,
    required this.onMateSafetyNChanged,
    required this.playSide,
    required this.onPlaySideChanged,
    required this.timeControl,
    required this.onTimeControlChanged,
    required this.botCrowns,
    required this.selectedOpening,
    required this.onOpeningChanged,
    required this.showEvalBar,
    required this.onShowEvalBarChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        color: _card,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AntiBlunderToggle(
                enabled: antiBlunderEnabled,
                onChanged: onAntiBlunderChanged,
              ),
              _HistoryLockToggle(
                locked: lockHistory,
                onChanged: onLockHistoryChanged,
              ),
              _MateSafetyControl(
                enabled: mateSafetyEnabled,
                n: mateSafetyN,
                onEnabledChanged: onMateSafetyEnabledChanged,
                onNChanged: onMateSafetyNChanged,
              ),
              const SizedBox(height: 6),
              _EvalBarToggle(
                shown: showEvalBar,
                onChanged: onShowEvalBarChanged,
              ),
              const SizedBox(height: 6),
              _OpeningSelector(
                selected: selectedOpening,
                onChanged: onOpeningChanged,
              ),
              const SizedBox(height: 6),
              PlaySideSelectorWidget(
                selected: playSide,
                onChanged: onPlaySideChanged,
              ),
              const SizedBox(height: 6),
              TimeControlSelectorWidget(
                selected: timeControl,
                onChanged: onTimeControlChanged,
              ),
              const SizedBox(height: 8),
              // Personality picker
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Opponent',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    selectedPersonality.category,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kPersonalities.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = kPersonalities[i];
                    final selected = p.id == selectedPersonality.id;
                    final crowns = botCrowns[p.id] ?? 0;
                    return GestureDetector(
                      onTap: () => onPersonalitySelected(p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 64,
                        decoration: BoxDecoration(
                          color: selected
                              ? _accentFill
                              : const Color(0xFF1A2B1A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? _accent : const Color(0xFF3A5A3A),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(p.emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(height: 2),
                            Text(
                              p.name.split(' ').last,
                              style: TextStyle(
                                color: selected ? _accent : _muted,
                                fontSize: 9,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            BotCrownsWidget(crowns: crowns, size: 8),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Difficulty row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Difficulty',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _accentFill,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _accentBorder),
                    ),
                    child: Text(
                      '${_eloLabel(elo)}  ·  $elo',
                      style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('difficultySlider'),
                value: elo.toDouble(),
                min: 0,
                max: 2800,
                divisions: 56,
                onChanged: (val) => onEloChanged(val.toInt()),
              ),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onNewGame,
                      child: const Text(
                        'New Game',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HistoryStepBtn(
                    icon: Icons.arrow_back_ios_new,
                    tooltip: 'Previous move',
                    enabled: canStepBack,
                    onTap: onStepBack,
                  ),
                  const SizedBox(width: 4),
                  _HistoryStepBtn(
                    icon: Icons.arrow_forward_ios,
                    tooltip: 'Next move',
                    enabled: canStepForward,
                    onTap: onStepForward,
                  ),
                  const SizedBox(width: 8),
                  _IconBtn(
                    icon: Icons.swap_vert,
                    tooltip: 'Flip board',
                    onTap: onFlipBoard,
                  ),
                  const SizedBox(width: 8),
                  _IconBtn(
                    icon: Icons.edit_outlined,
                    tooltip: 'FEN / PGN',
                    onTap: onLoadFen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AntiBlunderToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AntiBlunderToggle({required this.enabled, required this.onChanged});

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
          activeThumbColor: _accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _EvalBarToggle extends StatelessWidget {
  final bool shown;
  final ValueChanged<bool> onChanged;

  const _EvalBarToggle({required this.shown, required this.onChanged});

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
          activeThumbColor: _accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Dropdown to pick an opening to practice ("None" for free play). Picking
/// one (including re-picking the active one) starts a fresh game and
/// enforces that line for both sides until it runs out — see
/// docs/features/opening_book_follower.md.
class _OpeningSelector extends StatelessWidget {
  final ChessOpening? selected;
  final ValueChanged<ChessOpening?> onChanged;

  const _OpeningSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Opening',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButton<ChessOpening?>(
          key: const ValueKey('openingSelector'),
          value: selected,
          isExpanded: true,
          dropdownColor: _card,
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: [
            const DropdownMenuItem<ChessOpening?>(
              value: null,
              child: Text('None', overflow: TextOverflow.ellipsis),
            ),
            for (final o in kOpenings)
              DropdownMenuItem<ChessOpening?>(
                value: o,
                child: Text(o.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _HistoryLockToggle extends StatelessWidget {
  final bool locked;
  final ValueChanged<bool> onChanged;

  const _HistoryLockToggle({required this.locked, required this.onChanged});

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
            activeThumbColor: _accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MateSafetyControl extends StatelessWidget {
  final bool enabled;
  final int n;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onNChanged;

  const _MateSafetyControl({
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
              activeThumbColor: _accent,
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
                style: const TextStyle(color: _muted, fontSize: 11),
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A2B1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A5A3A)),
          ),
          child: Icon(icon, color: _muted, size: 20),
        ),
      ),
    );
  }
}

// ── Sidebar (wide-viewport layout) ──────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggle;
  final int elo;
  final BotPersonality selectedPersonality;
  final ValueChanged<BotPersonality> onPersonalitySelected;
  final ValueChanged<int> onEloChanged;
  final VoidCallback onNewGame;
  final VoidCallback onFlipBoard;
  final VoidCallback onLoadFen;
  final bool canStepBack;
  final bool canStepForward;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final bool lockHistory;
  final ValueChanged<bool> onLockHistoryChanged;
  final bool antiBlunderEnabled;
  final ValueChanged<bool> onAntiBlunderChanged;
  final bool mateSafetyEnabled;
  final int mateSafetyN;
  final ValueChanged<bool> onMateSafetyEnabledChanged;
  final ValueChanged<int> onMateSafetyNChanged;
  final PlaySide playSide;
  final ValueChanged<PlaySide> onPlaySideChanged;
  final TimeControl timeControl;
  final ValueChanged<TimeControl> onTimeControlChanged;
  final Map<String, int> botCrowns;
  final ChessOpening? selectedOpening;
  final ValueChanged<ChessOpening?> onOpeningChanged;
  final bool showEvalBar;
  final ValueChanged<bool> onShowEvalBarChanged;

  const _Sidebar({
    required this.collapsed,
    required this.onToggle,
    required this.elo,
    required this.selectedPersonality,
    required this.onPersonalitySelected,
    required this.onEloChanged,
    required this.onNewGame,
    required this.onFlipBoard,
    required this.onLoadFen,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStepBack,
    required this.onStepForward,
    required this.lockHistory,
    required this.onLockHistoryChanged,
    required this.antiBlunderEnabled,
    required this.onAntiBlunderChanged,
    required this.mateSafetyEnabled,
    required this.mateSafetyN,
    required this.onMateSafetyEnabledChanged,
    required this.onMateSafetyNChanged,
    required this.playSide,
    required this.onPlaySideChanged,
    required this.timeControl,
    required this.onTimeControlChanged,
    required this.botCrowns,
    required this.selectedOpening,
    required this.onOpeningChanged,
    required this.showEvalBar,
    required this.onShowEvalBarChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _sidebarAnimDuration,
      curve: Curves.easeInOut,
      width: collapsed ? _sidebarWidthCollapsed : _sidebarWidthExpanded,
      color: _card,
      // The content below is always laid out at the full expanded width
      // (via OverflowBox) so it never has to render into a near-zero-width
      // box mid-animation, which would overflow. ClipRect then hides
      // whatever sticks out past the AnimatedContainer's current width.
      child: ClipRect(
        child: OverflowBox(
          minWidth: _sidebarWidthExpanded,
          maxWidth: _sidebarWidthExpanded,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _sidebarWidthExpanded,
            child: Stack(
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: collapsed ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: collapsed,
                    child: _SidebarExpanded(
                      onToggle: onToggle,
                      elo: elo,
                      selectedPersonality: selectedPersonality,
                      onPersonalitySelected: onPersonalitySelected,
                      onEloChanged: onEloChanged,
                      onNewGame: onNewGame,
                      onFlipBoard: onFlipBoard,
                      onLoadFen: onLoadFen,
                      canStepBack: canStepBack,
                      canStepForward: canStepForward,
                      onStepBack: onStepBack,
                      onStepForward: onStepForward,
                      lockHistory: lockHistory,
                      onLockHistoryChanged: onLockHistoryChanged,
                      antiBlunderEnabled: antiBlunderEnabled,
                      onAntiBlunderChanged: onAntiBlunderChanged,
                      mateSafetyEnabled: mateSafetyEnabled,
                      mateSafetyN: mateSafetyN,
                      onMateSafetyEnabledChanged: onMateSafetyEnabledChanged,
                      onMateSafetyNChanged: onMateSafetyNChanged,
                      playSide: playSide,
                      onPlaySideChanged: onPlaySideChanged,
                      timeControl: timeControl,
                      onTimeControlChanged: onTimeControlChanged,
                      botCrowns: botCrowns,
                      selectedOpening: selectedOpening,
                      onOpeningChanged: onOpeningChanged,
                      showEvalBar: showEvalBar,
                      onShowEvalBarChanged: onShowEvalBarChanged,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: collapsed ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !collapsed,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: _sidebarWidthCollapsed,
                        child: _SidebarCollapsedRail(
                          onToggle: onToggle,
                          onNewGame: onNewGame,
                          onFlipBoard: onFlipBoard,
                          onLoadFen: onLoadFen,
                          canStepBack: canStepBack,
                          canStepForward: canStepForward,
                          onStepBack: onStepBack,
                          onStepForward: onStepForward,
                          lockHistory: lockHistory,
                          onLockHistoryChanged: onLockHistoryChanged,
                          antiBlunderEnabled: antiBlunderEnabled,
                          onAntiBlunderChanged: onAntiBlunderChanged,
                          mateSafetyEnabled: mateSafetyEnabled,
                          onMateSafetyEnabledChanged:
                              onMateSafetyEnabledChanged,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapseToggleButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onTap;

  const _CollapseToggleButton({required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Expand panel' : 'Collapse panel',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            collapsed ? Icons.chevron_left : Icons.chevron_right,
            color: _muted,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _SidebarExpanded extends StatelessWidget {
  final VoidCallback onToggle;
  final int elo;
  final BotPersonality selectedPersonality;
  final ValueChanged<BotPersonality> onPersonalitySelected;
  final ValueChanged<int> onEloChanged;
  final VoidCallback onNewGame;
  final VoidCallback onFlipBoard;
  final VoidCallback onLoadFen;
  final bool canStepBack;
  final bool canStepForward;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final bool lockHistory;
  final ValueChanged<bool> onLockHistoryChanged;
  final bool antiBlunderEnabled;
  final ValueChanged<bool> onAntiBlunderChanged;
  final bool mateSafetyEnabled;
  final int mateSafetyN;
  final ValueChanged<bool> onMateSafetyEnabledChanged;
  final ValueChanged<int> onMateSafetyNChanged;
  final PlaySide playSide;
  final ValueChanged<PlaySide> onPlaySideChanged;
  final TimeControl timeControl;
  final ValueChanged<TimeControl> onTimeControlChanged;
  final Map<String, int> botCrowns;
  final ChessOpening? selectedOpening;
  final ValueChanged<ChessOpening?> onOpeningChanged;
  final bool showEvalBar;
  final ValueChanged<bool> onShowEvalBarChanged;

  const _SidebarExpanded({
    required this.onToggle,
    required this.elo,
    required this.selectedPersonality,
    required this.onPersonalitySelected,
    required this.onEloChanged,
    required this.onNewGame,
    required this.onFlipBoard,
    required this.onLoadFen,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStepBack,
    required this.onStepForward,
    required this.lockHistory,
    required this.onLockHistoryChanged,
    required this.antiBlunderEnabled,
    required this.onAntiBlunderChanged,
    required this.mateSafetyEnabled,
    required this.mateSafetyN,
    required this.onMateSafetyEnabledChanged,
    required this.onMateSafetyNChanged,
    required this.playSide,
    required this.onPlaySideChanged,
    required this.timeControl,
    required this.onTimeControlChanged,
    required this.botCrowns,
    required this.selectedOpening,
    required this.onOpeningChanged,
    required this.showEvalBar,
    required this.onShowEvalBarChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _CollapseToggleButton(collapsed: false, onTap: onToggle),
            ],
          ),
          const SizedBox(height: 4),
          _AntiBlunderToggle(
            enabled: antiBlunderEnabled,
            onChanged: onAntiBlunderChanged,
          ),
          _HistoryLockToggle(
            locked: lockHistory,
            onChanged: onLockHistoryChanged,
          ),
          _MateSafetyControl(
            enabled: mateSafetyEnabled,
            n: mateSafetyN,
            onEnabledChanged: onMateSafetyEnabledChanged,
            onNChanged: onMateSafetyNChanged,
          ),
          const SizedBox(height: 4),
          _EvalBarToggle(shown: showEvalBar, onChanged: onShowEvalBarChanged),
          const SizedBox(height: 6),
          _OpeningSelector(
            selected: selectedOpening,
            onChanged: onOpeningChanged,
          ),
          const SizedBox(height: 4),
          PlaySideSelectorWidget(
            selected: playSide,
            onChanged: onPlaySideChanged,
          ),
          const SizedBox(height: 6),
          TimeControlSelectorWidget(
            selected: timeControl,
            onChanged: onTimeControlChanged,
          ),
          const SizedBox(height: 6),
          const Text(
            'Opponent',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          // Vertical list — a sidebar is too narrow for the horizontal
          // scroller the bottom-panel layout uses.
          Expanded(
            child: ListView.separated(
              itemCount: kPersonalities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, i) {
                final p = kPersonalities[i];
                final selected = p.id == selectedPersonality.id;
                final crowns = botCrowns[p.id] ?? 0;
                return GestureDetector(
                  onTap: () => onPersonalitySelected(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? _accentFill : const Color(0xFF1A2B1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? _accent : const Color(0xFF3A5A3A),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(p.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${p.name} · ${p.category}',
                            style: TextStyle(
                              color: selected ? _accent : _muted,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        BotCrownsWidget(crowns: crowns, size: 10),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Difficulty',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _accentFill,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _accentBorder),
                  ),
                  child: Text(
                    '${_eloLabel(elo)}  ·  $elo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              key: const ValueKey('difficultySlider'),
              value: elo.toDouble(),
              min: 0,
              max: 2800,
              divisions: 56,
              onChanged: (val) => onEloChanged(val.toInt()),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNewGame,
              child: const Text(
                'New Game',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _HistoryStepBtn(
                icon: Icons.arrow_back_ios_new,
                tooltip: 'Previous move',
                enabled: canStepBack,
                onTap: onStepBack,
              ),
              _HistoryStepBtn(
                icon: Icons.arrow_forward_ios,
                tooltip: 'Next move',
                enabled: canStepForward,
                onTap: onStepForward,
              ),
              _IconBtn(
                icon: Icons.swap_vert,
                tooltip: 'Flip board',
                onTap: onFlipBoard,
              ),
              _IconBtn(
                icon: Icons.edit_outlined,
                tooltip: 'FEN / PGN',
                onTap: onLoadFen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarCollapsedRail extends StatelessWidget {
  final VoidCallback onToggle;
  final VoidCallback onNewGame;
  final VoidCallback onFlipBoard;
  final VoidCallback onLoadFen;
  final bool canStepBack;
  final bool canStepForward;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final bool lockHistory;
  final ValueChanged<bool> onLockHistoryChanged;
  final bool antiBlunderEnabled;
  final ValueChanged<bool> onAntiBlunderChanged;
  final bool mateSafetyEnabled;
  final ValueChanged<bool> onMateSafetyEnabledChanged;

  const _SidebarCollapsedRail({
    required this.onToggle,
    required this.onNewGame,
    required this.onFlipBoard,
    required this.onLoadFen,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStepBack,
    required this.onStepForward,
    required this.lockHistory,
    required this.onLockHistoryChanged,
    required this.antiBlunderEnabled,
    required this.onAntiBlunderChanged,
    required this.mateSafetyEnabled,
    required this.onMateSafetyEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          _CollapseToggleButton(collapsed: true, onTap: onToggle),
          const SizedBox(height: 16),
          _IconBtn(
            icon: antiBlunderEnabled ? Icons.shield : Icons.shield_outlined,
            tooltip: antiBlunderEnabled
                ? 'Anti-Blunder: on'
                : 'Anti-Blunder: off',
            onTap: () => onAntiBlunderChanged(!antiBlunderEnabled),
          ),
          const SizedBox(height: 10),
          _IconBtn(
            icon: lockHistory ? Icons.lock_outline : Icons.lock_open_outlined,
            tooltip: lockHistory
                ? 'View-Only History: on'
                : 'View-Only History: off (editable)',
            onTap: () => onLockHistoryChanged(!lockHistory),
          ),
          const SizedBox(height: 10),
          _IconBtn(
            icon: mateSafetyEnabled ? Icons.gpp_good : Icons.gpp_maybe_outlined,
            tooltip: mateSafetyEnabled ? 'Mate Safety: on' : 'Mate Safety: off',
            onTap: () => onMateSafetyEnabledChanged(!mateSafetyEnabled),
          ),
          const SizedBox(height: 10),
          _HistoryStepBtn(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Previous move',
            enabled: canStepBack,
            onTap: onStepBack,
          ),
          const SizedBox(height: 8),
          _HistoryStepBtn(
            icon: Icons.arrow_forward_ios,
            tooltip: 'Next move',
            enabled: canStepForward,
            onTap: onStepForward,
          ),
          const SizedBox(height: 10),
          _IconBtn(
            icon: Icons.restart_alt,
            tooltip: 'New Game',
            onTap: onNewGame,
          ),
          const SizedBox(height: 10),
          _IconBtn(
            icon: Icons.swap_vert,
            tooltip: 'Flip board',
            onTap: onFlipBoard,
          ),
          const SizedBox(height: 10),
          _IconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'FEN / PGN',
            onTap: onLoadFen,
          ),
        ],
      ),
    );
  }
}

String _eloLabel(int elo) {
  if (elo < 250) return 'Trying to Lose';
  if (elo < 700) return 'Very Easy';
  if (elo < 1000) return 'Beginner';
  if (elo < 1400) return 'Intermediate';
  if (elo < 1800) return 'Advanced';
  if (elo < 2200) return 'Expert';
  return 'Master';
}
