import 'dart:math' show min;
import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/chess_board/chess_board_widget.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import '../providers/game_provider.dart';
import '../widgets/bot_panel.dart';
import '../widgets/controls_panel.dart';
import '../widgets/eval_bar_and_graph.dart';
import '../widgets/game_over_banner.dart';
import '../widgets/game_theme.dart';
import '../widgets/move_history_feedback_bar.dart';
import '../widgets/player_bar.dart';
import '../widgets/resizable_board_frame.dart';
import '../widgets/sidebar.dart';

// fixed heights used to size the board
const _botPanelH = 128.0;
const _playerBarH = 54.0;
const _controlsH = 220.0;

// side-panel layout: used instead of the bottom controls strip once the
// viewport is wide enough that a right-hand sidebar doesn't cramp the board.
const _sidePanelBreakpoint = 700.0;
const _sidebarWidthExpanded = 280.0;
const _sidebarWidthCollapsed = 56.0;

/// The classification worth a board badge for, or `null` if there's no
/// move yet or the move was unremarkable — same `good`/`book` exclusion
/// `MoveHistoryAndFeedbackBar` already uses for its own per-move symbols,
/// so the on-board badge and the move-strip badge never disagree about
/// which moves are "notable".
MoveClassification? _notableClassification(GameState state) {
  final c = state.currentPlyClassification;
  if (c == null ||
      c == MoveClassification.good ||
      c == MoveClassification.book) {
    return null;
  }
  return c;
}

class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  final _boardKey = GlobalKey<ChessBoardWidgetState>();

  // Pure in-memory UI state for the side panel — no persistence, always
  // starts expanded (see docs/features/done/controls_side_panel.md).
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
        backgroundColor: kCard,
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
                      icon: const Icon(Icons.copy, size: 15, color: kAccent),
                      label: const Text(
                        'Copy FEN',
                        style: TextStyle(color: kAccent, fontSize: 12),
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
                    hintStyle: TextStyle(color: kMuted),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: kMuted),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: kAccent),
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
                      icon: const Icon(Icons.copy, size: 15, color: kAccent),
                      label: const Text(
                        'Copy PGN',
                        style: TextStyle(color: kAccent, fontSize: 12),
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
                    hintStyle: TextStyle(color: kMuted),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: kMuted),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: kAccent),
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
            child: const Text('Close', style: TextStyle(color: kMuted)),
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
            child: const Text('Load PGN', style: TextStyle(color: kAccent)),
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
            child: const Text('Load FEN', style: TextStyle(color: kAccent)),
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
            backgroundColor: kCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kAccent, width: 1.5),
            ),
            title: Row(
              children: [
                Icon(
                  isDraw
                      ? Icons.handshake_outlined
                      : Icons.emoji_events_outlined,
                  color: kAccent,
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
                            color: kMuted,
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
                              color: kAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Analyzing…',
                            style: TextStyle(color: kAccent, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PlayerReviewCard(
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
                          child: PlayerReviewCard(
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
                  style: TextStyle(color: kMuted),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showFenDialog(fen, pgn);
                },
                child: const Text(
                  'FEN / PGN',
                  style: TextStyle(color: kAccent),
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
      backgroundColor: kBg,
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

            final notableClassification = _notableClassification(state);

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
              badgeSquare: notableClassification != null
                  ? state.displayedLastMoveTo
                  : null,
              badgeSymbol: notableClassification?.symbol,
              badgeColor: notableClassification != null
                  ? classificationColor(notableClassification)
                  : null,
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
                    child: GameOverBanner(
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
                        BotPanel(
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
                        PlayerBar(
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
                  Sidebar(
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
                BotPanel(
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
                PlayerBar(
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
                ControlsPanel(
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
