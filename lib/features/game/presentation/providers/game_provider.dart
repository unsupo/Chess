import 'dart:developer' as developer;
import 'dart:math' show Random;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../../data/repositories/chess_engine_repository_impl.dart';
import '../../domain/entities/bot_move_pipeline.dart';
import '../../domain/entities/bot_move_strategy.dart';
import '../../domain/entities/bot_personality.dart';
import '../../domain/entities/chess_move_analysis.dart' show applyUciToFen;
import '../../domain/entities/chess_opening.dart';
import '../../domain/entities/move_result.dart';
import '../../domain/entities/time_control.dart';
import '../../domain/repositories/chess_engine_repository.dart';
import '../../domain/usecases/attempt_move_usecase.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import '../../domain/usecases/pgn_codec.dart';
import '../../domain/usecases/scholars_mate_hunter_policy.dart';
import 'clock_service.dart';
import 'game_review_service.dart';

export '../../domain/entities/chess_opening.dart';
export '../../domain/entities/time_control.dart';

// --- Dependency Injection ---
final engineRepositoryProvider = Provider<ChessEngineRepository>((ref) {
  final repo = ChessEngineRepositoryImpl();
  ref.onDispose(() => repo.dispose());
  return repo;
});

final attemptMoveUseCaseProvider = Provider<AttemptMoveUseCase>((ref) {
  return AttemptMoveUseCase(ref.watch(engineRepositoryProvider));
});

// --- State ---
class SideMaterial {
  /// Codes of opponent pieces captured by this side (e.g. 'bQ', 'bP'),
  /// ordered from highest value to lowest value.
  final List<String> capturedPieces;

  /// Total point value of opponent pieces captured by this side.
  final int capturedScore;

  /// Net material advantage on the board (`> 0` if this side is ahead).
  final int netAdvantage;

  const SideMaterial({
    required this.capturedPieces,
    required this.capturedScore,
    required this.netAdvantage,
  });
}

class GameState {
  final String fen;
  final String initialFen;
  final List<String> sanMoves;
  final bool isEvaluating;
  final String? errorMessage;
  final int botElo;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final bool undoRequested;
  final BotPersonality personality;
  final bool boardFlipped;
  final bool antiBlunderEnabled;
  final bool mateSafetyEnabled;
  final int mateSafetyN;
  final int? viewPly;
  final bool lockHistory;
  final GameReviewSummary? gameReview;
  final bool isAnalyzingGameReview;
  final TimeControl timeControl;
  final int whiteTimeMs;
  final int blackTimeMs;
  final String? timeoutWinner;
  final PlaySide playSide;
  final Map<String, int> botCrowns;
  final Map<String, int> evalByFenKey;
  final ChessOpening? selectedOpening;
  final bool showEvalBar;

  const GameState({
    required this.fen,
    this.initialFen = chess_lib.Chess.DEFAULT_POSITION,
    this.sanMoves = const [],
    this.isEvaluating = false,
    this.errorMessage,
    this.botElo = 900,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.undoRequested = false,
    this.personality = kDefaultPersonality,
    this.boardFlipped = false,
    this.antiBlunderEnabled = true,
    this.mateSafetyEnabled = false,
    this.mateSafetyN = 3,
    this.viewPly,
    this.lockHistory = true,
    this.gameReview,
    this.isAnalyzingGameReview = false,
    this.timeControl = TimeControl.unlimited,
    this.whiteTimeMs = 0,
    this.blackTimeMs = 0,
    this.timeoutWinner,
    this.playSide = PlaySide.white,
    this.botCrowns = const {},
    this.evalByFenKey = const {},
    this.selectedOpening,
    this.showEvalBar = true,
  });

  /// The ply index currently displayed on the board (`0..sanMoves.length`).
  int get currentPly => (viewPly ?? sanMoves.length).clamp(0, sanMoves.length);

  /// True when the user has stepped back to view an earlier move.
  bool get isViewingHistory => currentPly < sanMoves.length;

  bool get canStepBack => currentPly > 0 && !isEvaluating;

  bool get canStepForward => currentPly < sanMoves.length && !isEvaluating;

  /// True when it is White's turn in the live position.
  bool get isWhiteTurn {
    final parts = fen.split(RegExp(r'\s+'));
    return parts.length < 2 || parts[1] != 'b';
  }

  /// Number of crowns (0..3) earned against [botId].
  int crownsForBot(String botId) => (botCrowns[botId] ?? 0).clamp(0, 3);

  /// Detected ECO / opening name up to [currentPly], or `null` if none.
  String? get openingName =>
      OpeningBookClassifier.detectOpeningName(sanMoves.sublist(0, currentPly));

  /// Live move classifications for all moves played so far.
  List<MoveClassification> get liveMoveClassifications {
    if (gameReview != null &&
        gameReview!.plyClassifications.length == sanMoves.length) {
      return gameReview!.plyClassifications;
    }
    if (sanMoves.isEmpty) return const [];
    return GameReviewAnalyzer.analyze(
      initialFen: initialFen,
      sanMoves: sanMoves,
      evalByFenKey: evalByFenKey,
      botElo: botElo,
      humanIsWhite: !boardFlipped,
    ).plyClassifications;
  }

  /// Classification of the move that produced [currentPly], or `null` at ply 0.
  MoveClassification? get currentPlyClassification {
    if (currentPly <= 0) return null;
    final list = liveMoveClassifications;
    if (currentPly - 1 >= list.length) return null;
    return list[currentPly - 1];
  }

  /// Centipawn evaluation of [displayedFen] from White's perspective.
  int get currentWhiteCp {
    final dFen = displayedFen;
    final key = GameReviewAnalyzer.fenKey(dFen);
    final raw = evalByFenKey[key] ?? 0;
    final parts = dFen.split(RegExp(r'\s+'));
    final whiteToMove = parts.length < 2 || parts[1] != 'b';
    return whiteToMove ? raw : -raw;
  }

  /// White-perspective centipawn eval at each ply `0..sanMoves.length`
  /// (index 0 is the starting position), for the eval graph. Replays
  /// `sanMoves` from `initialFen` and looks up each resulting position in
  /// `evalByFenKey` (already populated by the blunder check / bot move
  /// search as the game was played — no extra engine calls here). A ply
  /// whose position was never evaluated (e.g. anti-blunder was off and no
  /// bot-candidate search ran) falls back to the previous ply's value so
  /// the graph has no gaps.
  List<int> get plyWhiteCpHistory {
    final history = <int>[];
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(initialFen)['valid'] != true ||
        !chess.load(initialFen)) {
      return [0];
    }

    int whiteCpOf(String fen) {
      final key = GameReviewAnalyzer.fenKey(fen);
      final raw = evalByFenKey[key];
      if (raw == null) return history.isNotEmpty ? history.last : 0;
      final parts = fen.split(RegExp(r'\s+'));
      final whiteToMove = parts.length < 2 || parts[1] != 'b';
      return whiteToMove ? raw : -raw;
    }

    history.add(whiteCpOf(chess.fen));
    for (final san in sanMoves) {
      if (!chess.move(san)) break;
      history.add(whiteCpOf(chess.fen));
    }
    return history;
  }

  /// Formatted evaluation string from White's perspective (e.g. `+0.3`, `-1.2`).
  String get formattedEvalScore {
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(displayedFen)['valid'] == true &&
        chess.load(displayedFen) &&
        chess.in_checkmate) {
      return chess.turn == chess_lib.Color.WHITE ? '0-1' : '1-0';
    }
    final pawns = currentWhiteCp / 100.0;
    final sign = pawns > 0 ? '+' : '';
    return '$sign${pawns.toStringAsFixed(1)}';
  }

  /// Returns `(displayedFen, lastMoveFrom, lastMoveTo)` at [currentPly].
  (String, String?, String?) get _displayedSnapshot {
    if (!isViewingHistory) {
      return (fen, lastMoveFrom, lastMoveTo);
    }
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(initialFen)['valid'] != true ||
        !chess.load(initialFen)) {
      return (fen, lastMoveFrom, lastMoveTo);
    }
    String? from;
    String? to;
    for (var i = 0; i < currentPly; i++) {
      final san = sanMoves[i];
      String? stepFrom;
      String? stepTo;
      for (final m in chess.generate_moves()) {
        if (chess.move_to_san(m) == san) {
          stepFrom = m.fromAlgebraic;
          stepTo = m.toAlgebraic;
          break;
        }
      }
      if (!chess.move(san)) break;
      from = stepFrom;
      to = stepTo;
    }
    return (chess.fen, from, to);
  }

  /// The FEN currently shown on the board (either live [fen] or historical ply).
  String get displayedFen => _displayedSnapshot.$1;

  /// The `from` square highlight for the currently displayed ply.
  String? get displayedLastMoveFrom => _displayedSnapshot.$2;

  /// The `to` square highlight for the currently displayed ply.
  String? get displayedLastMoveTo => _displayedSnapshot.$3;

  /// True if the currently displayed board position is a game-over position.
  bool get isDisplayedGameOver {
    if (!isViewingHistory) return isGameOver;
    final dFen = displayedFen;
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(dFen)['valid'] == true) {
      chess.load(dFen);
    }
    return chess.game_over ||
        ScholarsMateHunterPolicy.isInsufficientMatingMaterial(dFen);
  }

  chess_lib.Chess _buildGameChess() {
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(initialFen)['valid'] != true ||
        !chess.load(initialFen)) {
      if (chess_lib.Chess.validate_fen(fen)['valid'] == true) {
        chess.load(fen);
      }
      return chess;
    }
    for (final san in sanMoves) {
      if (!chess.move(san)) {
        if (chess_lib.Chess.validate_fen(fen)['valid'] == true) {
          chess.load(fen);
        }
        return chess;
      }
    }
    if (chess.fen != fen &&
        chess_lib.Chess.validate_fen(fen)['valid'] == true) {
      chess.load(fen);
    }
    return chess;
  }

  bool get isCheckmate => _buildGameChess().in_checkmate;

  bool get isDraw {
    if (timeoutWinner != null) return false;
    final chess = _buildGameChess();
    return chess.in_draw ||
        ScholarsMateHunterPolicy.isInsufficientMatingMaterial(fen);
  }

  bool get isGameOver =>
      timeoutWinner != null ||
      _buildGameChess().game_over ||
      ScholarsMateHunterPolicy.isInsufficientMatingMaterial(fen);

  /// Map of 4-field position keys (`board turn castling ep`) to the number
  /// of times each position has occurred in the current game so far.
  /// Used by bot move selection to avoid repeating positions / 3-fold draws.
  Map<String, int> get positionCounts {
    final counts = <String, int>{};
    void record(String f) {
      final key = f.split(RegExp(r'\s+')).take(4).join(' ');
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(initialFen)['valid'] != true ||
        !chess.load(initialFen)) {
      record(fen);
      return counts;
    }
    record(chess.fen);
    for (final san in sanMoves) {
      if (!chess.move(san)) break;
      record(chess.fen);
    }
    return counts;
  }

  /// Human-readable game-over or draw status message, or `null` if the game
  /// is still in progress.
  String? get gameOverMessage {
    if (timeoutWinner != null) {
      final whiteWon = timeoutWinner == 'white';
      final humanIsWhite = !boardFlipped;
      final humanWon = whiteWon == humanIsWhite;
      return humanWon
          ? 'Time out — You win!'
          : 'Time out — ${personality.name} wins!';
    }
    final chess = _buildGameChess();
    if (chess.in_checkmate) {
      final whiteWon = chess.turn == chess_lib.Color.BLACK;
      final humanIsWhite = !boardFlipped;
      final humanWon = whiteWon == humanIsWhite;
      return humanWon
          ? 'Checkmate — You win!'
          : 'Checkmate — ${personality.name} wins!';
    }
    if (chess.in_stalemate) {
      return 'Draw by stalemate';
    }
    if (chess.in_threefold_repetition) {
      return 'Draw by threefold repetition';
    }
    if (chess.insufficient_material ||
        ScholarsMateHunterPolicy.isInsufficientMatingMaterial(fen)) {
      return 'Draw by insufficient material';
    }
    if (chess.half_moves >= 100) {
      return 'Draw by 50-move rule';
    }
    return null;
  }

  /// Full PGN string including standard tag headers and move list.
  String get pgn => PgnCodec.toPgn(
    initialFen: initialFen,
    fen: fen,
    sanMoves: sanMoves,
    timeoutWinner: timeoutWinner,
    isDraw: isDraw,
    boardFlipped: boardFlipped,
    personalityName: personality.name,
    botElo: botElo,
    isTimedControl: timeControl.isTimed,
    timeControlKey: timeControl.key,
  );

  /// Computes captured pieces and material score for White (`isWhite: true`)
  /// or Black (`isWhite: false`) from the currently displayed board position.
  SideMaterial materialFor({required bool isWhite}) {
    final boardPart = displayedFen.split(RegExp(r'\s+')).first;
    final counts = <String, int>{};
    for (final ch in boardPart.split('')) {
      if ('PNBRQKpnbrqk'.contains(ch)) {
        counts[ch] = (counts[ch] ?? 0) + 1;
      }
    }

    const startCounts = {'q': 1, 'r': 2, 'b': 2, 'n': 2, 'p': 8};
    const values = {'q': 9, 'r': 5, 'b': 3, 'n': 3, 'p': 1};

    int sideBoardMaterial(bool white) {
      var total = 0;
      for (final entry in values.entries) {
        final key = white ? entry.key.toUpperCase() : entry.key;
        total += (counts[key] ?? 0) * entry.value;
      }
      return total;
    }

    final whiteMat = sideBoardMaterial(true);
    final blackMat = sideBoardMaterial(false);

    final captured = <String>[];
    var capturedScore = 0;
    final oppPrefix = isWhite ? 'b' : 'w';
    for (final type in const ['q', 'r', 'b', 'n', 'p']) {
      final oppChar = isWhite ? type : type.toUpperCase();
      final remaining = counts[oppChar] ?? 0;
      final missing = (startCounts[type]! - remaining).clamp(0, 8);
      for (var i = 0; i < missing; i++) {
        captured.add('$oppPrefix${type.toUpperCase()}');
        capturedScore += values[type]!;
      }
    }

    final netAdvantage = isWhite
        ? (whiteMat - blackMat)
        : (blackMat - whiteMat);
    return SideMaterial(
      capturedPieces: captured,
      capturedScore: capturedScore,
      netAdvantage: netAdvantage,
    );
  }

  GameState copyWith({
    String? fen,
    String? initialFen,
    List<String>? sanMoves,
    bool? isEvaluating,
    String? errorMessage,
    int? botElo,
    String? lastMoveFrom,
    String? lastMoveTo,
    bool? undoRequested,
    BotPersonality? personality,
    bool? boardFlipped,
    bool? antiBlunderEnabled,
    bool? mateSafetyEnabled,
    int? mateSafetyN,
    int? viewPly,
    bool? lockHistory,
    GameReviewSummary? gameReview,
    bool? isAnalyzingGameReview,
    TimeControl? timeControl,
    int? whiteTimeMs,
    int? blackTimeMs,
    String? timeoutWinner,
    PlaySide? playSide,
    Map<String, int>? botCrowns,
    Map<String, int>? evalByFenKey,
    ChessOpening? selectedOpening,
    bool? showEvalBar,
    bool clearError = false,
    bool clearLastMove = false,
    bool clearViewPly = false,
    bool clearGameReview = false,
    bool clearTimeoutWinner = false,
    bool clearSelectedOpening = false,
  }) {
    return GameState(
      fen: fen ?? this.fen,
      initialFen: initialFen ?? this.initialFen,
      sanMoves: sanMoves ?? this.sanMoves,
      isEvaluating: isEvaluating ?? this.isEvaluating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      botElo: botElo ?? this.botElo,
      lastMoveFrom: clearLastMove ? null : (lastMoveFrom ?? this.lastMoveFrom),
      lastMoveTo: clearLastMove ? null : (lastMoveTo ?? this.lastMoveTo),
      undoRequested: undoRequested ?? this.undoRequested,
      personality: personality ?? this.personality,
      boardFlipped: boardFlipped ?? this.boardFlipped,
      antiBlunderEnabled: antiBlunderEnabled ?? this.antiBlunderEnabled,
      mateSafetyEnabled: mateSafetyEnabled ?? this.mateSafetyEnabled,
      mateSafetyN: mateSafetyN ?? this.mateSafetyN,
      viewPly: clearViewPly ? null : (viewPly ?? this.viewPly),
      lockHistory: lockHistory ?? this.lockHistory,
      gameReview: clearGameReview ? null : (gameReview ?? this.gameReview),
      isAnalyzingGameReview:
          isAnalyzingGameReview ?? this.isAnalyzingGameReview,
      timeControl: timeControl ?? this.timeControl,
      whiteTimeMs: whiteTimeMs ?? this.whiteTimeMs,
      blackTimeMs: blackTimeMs ?? this.blackTimeMs,
      timeoutWinner: clearTimeoutWinner
          ? null
          : (timeoutWinner ?? this.timeoutWinner),
      playSide: playSide ?? this.playSide,
      botCrowns: botCrowns ?? this.botCrowns,
      evalByFenKey: evalByFenKey ?? this.evalByFenKey,
      selectedOpening: clearSelectedOpening
          ? null
          : (selectedOpening ?? this.selectedOpening),
      showEvalBar: showEvalBar ?? this.showEvalBar,
    );
  }
}

final gameProvider = StateNotifierProvider<GameNotifier, GameState>((ref) {
  return GameNotifier(
    ref.watch(engineRepositoryProvider),
    ref.watch(attemptMoveUseCaseProvider),
  );
});

bool get isFlutterTest =>
    !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

class GameNotifier extends StateNotifier<GameState> {
  final ChessEngineRepository _engine;
  final AttemptMoveUseCase _attemptMove;
  final ClockService _clockService = ClockService();
  final GameReviewService _gameReviewService;
  final bool enableBotDelay;

  GameNotifier(
    this._engine,
    this._attemptMove, {
    bool? enableBotDelay,
  }) : enableBotDelay = enableBotDelay ?? !isFlutterTest,
       _gameReviewService = GameReviewService(_engine),
       super(
        GameState(
          fen: chess_lib.Chess().fen,
          evalByFenKey: {
            GameReviewAnalyzer.fenKey(chess_lib.Chess.DEFAULT_POSITION): 20,
          },
        ),
      ) {
    _engine.setBotElo(state.botElo);
    _registerDebugMoveExtension();
  }

  @override
  void dispose() {
    _clockService.dispose();
    super.dispose();
  }

  // Lets a dev tool (e.g. a script talking to the VM service) drive the
  // board by UCI move instead of requiring a real tap on the board widget.
  // `dart:developer` extensions can only be registered once per name per
  // isolate — a second GameNotifier in the same isolate (hot restart, or
  // multiple tests in one test file each constructing their own notifier)
  // would otherwise throw "Extension already registered". The guard means
  // the hook stays bound to whichever GameNotifier registered first; fine
  // for a debug-only convenience nothing else depends on.
  static bool _debugExtensionRegistered = false;

  void _registerDebugMoveExtension() {
    if (kReleaseMode || _debugExtensionRegistered) return;
    _debugExtensionRegistered = true;
    developer.registerExtension('ext.chess_teacher.makeUciMove', (
      method,
      params,
    ) async {
      final uci = params['uci'];
      if (uci == null || uci.length < 4) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'pass a 4-5 char uci move, e.g. uci=e2e4',
        );
      }
      try {
        final newFen = applyUciToFen(state.fen, uci);
        await onUserMove(newFen);
        return developer.ServiceExtensionResponse.result(
          '{"fen":"${state.fen}","error":${state.errorMessage == null ? 'null' : '"${state.errorMessage}"'}}',
        );
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$e',
        );
      }
    });
  }

  final _random = Random();

  /// Builds the context one bot turn needs for
  /// `MateSafetyDecorator(kDefaultBotMovePipeline).selectMove(ctx)` — see
  /// docs/features/done/refactor_04_bot_move_pipeline.md.
  BotMoveContext _botMoveContext(String fen, int elo) => BotMoveContext(
    fen: fen,
    elo: elo,
    engine: _engine,
    positionCounts: state.positionCounts,
    personalityId: state.personality.id,
    ply: state.sanMoves.length,
    selectedOpening: state.selectedOpening,
    mateSafetyEnabled: state.mateSafetyEnabled,
    mateSafetyN: state.mateSafetyN,
    recordEval: _gameReviewService.recordEval,
  );

  Future<void> setDifficulty(int elo) async {
    state = state.copyWith(botElo: elo);
    await _engine.setBotElo(elo);
  }

  Future<void> setPersonality(BotPersonality p) async {
    state = state.copyWith(personality: p, botElo: p.defaultElo);
    await _engine.setBotElo(p.defaultElo);
  }

  void setAntiBlunderEnabled(bool enabled) {
    state = state.copyWith(antiBlunderEnabled: enabled);
  }

  void setMateSafetyEnabled(bool enabled) {
    state = state.copyWith(mateSafetyEnabled: enabled);
  }

  void setMateSafetyN(int n) {
    state = state.copyWith(mateSafetyN: n);
  }

  void setLockHistory(bool locked) {
    state = state.copyWith(lockHistory: locked);
  }

  void setShowEvalBar(bool shown) {
    state = state.copyWith(showEvalBar: shown);
  }

  /// Picks an opening to practice (or `null` for free play) and always
  /// starts a fresh game — see docs/features/done/opening_book_follower.md for
  /// why re-picking mid-game isn't supported. `newGame()` carries
  /// `selectedOpening` through, so it must be set first.
  Future<void> setOpening(ChessOpening? opening) async {
    state = state.copyWith(
      selectedOpening: opening,
      clearSelectedOpening: opening == null,
    );
    await newGame();
  }

  /// Sets the active time control and resets both players' clocks.
  void setTimeControl(TimeControl tc) {
    _clockService.stop();
    state = state.copyWith(
      timeControl: tc,
      whiteTimeMs: tc.initialTimeMs,
      blackTimeMs: tc.initialTimeMs,
      clearTimeoutWinner: true,
    );
    _syncClockTimer();
  }

  /// Sets the preferred play side (`white`, `random`, or `black`) and resolves
  /// board orientation.
  void setPlaySide(PlaySide side) {
    final bool flipped;
    switch (side) {
      case PlaySide.white:
        flipped = false;
      case PlaySide.black:
        flipped = true;
      case PlaySide.random:
        flipped = _random.nextBool();
    }
    state = state.copyWith(playSide: side, boardFlipped: flipped);
    _maybeBotMove();
  }

  /// Jumps directly to [ply] (`0..sanMoves.length`) in the move list.
  void selectPly(int ply) {
    if (state.isEvaluating) return;
    final clamped = ply.clamp(0, state.sanMoves.length);
    if (clamped >= state.sanMoves.length) {
      state = state.copyWith(clearViewPly: true, clearError: true);
    } else {
      state = state.copyWith(viewPly: clamped, clearError: true);
    }
  }

  /// Advances the active player's countdown clock by [elapsedMs] milliseconds.
  void tickClock(int elapsedMs) {
    if (!state.timeControl.isTimed || state.isGameOver || elapsedMs <= 0) {
      return;
    }
    if (state.sanMoves.isEmpty && !state.isEvaluating) return;

    if (state.isWhiteTurn) {
      final next = (state.whiteTimeMs - elapsedMs).clamp(0, 86400000);
      if (next <= 0) {
        _clockService.stop();
        state = state.copyWith(whiteTimeMs: 0, timeoutWinner: 'black');
        _awardCrownsIfHumanWon();
        _computeGameReview();
      } else {
        state = state.copyWith(whiteTimeMs: next);
      }
    } else {
      final next = (state.blackTimeMs - elapsedMs).clamp(0, 86400000);
      if (next <= 0) {
        _clockService.stop();
        state = state.copyWith(blackTimeMs: 0, timeoutWinner: 'white');
        _awardCrownsIfHumanWon();
        _computeGameReview();
      } else {
        state = state.copyWith(blackTimeMs: next);
      }
    }
  }

  void _syncClockTimer() {
    _clockService.stop();
    if (!state.timeControl.isTimed || state.isGameOver) return;
    if (state.sanMoves.isEmpty) return;
    _clockService.start((elapsedMs) {
      if (!mounted) {
        _clockService.stop();
        return;
      }
      tickClock(elapsedMs);
    });
  }

  void _awardCrownsIfHumanWon() {
    final humanIsWhite = !state.boardFlipped;
    bool humanWon = false;
    if (state.timeoutWinner != null) {
      humanWon = (state.timeoutWinner == 'white') == humanIsWhite;
    } else {
      final chess = chess_lib.Chess();
      if (chess_lib.Chess.validate_fen(state.fen)['valid'] == true &&
          chess.load(state.fen) &&
          chess.in_checkmate) {
        final whiteWon = chess.turn == chess_lib.Color.BLACK;
        humanWon = whiteWon == humanIsWhite;
      }
    }
    if (!humanWon) return;

    final int earned;
    if (!state.antiBlunderEnabled && !state.mateSafetyEnabled) {
      earned = 3;
    } else if (!state.mateSafetyEnabled) {
      earned = 2;
    } else {
      earned = 1;
    }
    final botId = state.personality.id;
    final prev = state.crownsForBot(botId);
    if (earned > prev) {
      state = state.copyWith(botCrowns: {...state.botCrowns, botId: earned});
    }
  }

  /// Steps back one half-move (ply) in the move history for viewing or branching.
  void stepBack() {
    if (!state.canStepBack) return;
    final nextPly = state.currentPly - 1;
    state = state.copyWith(viewPly: nextPly, clearError: true);
  }

  /// Steps forward one half-move (ply) in the move history.
  void stepForward() {
    if (!state.canStepForward) return;
    final nextPly = state.currentPly + 1;
    if (nextPly >= state.sanMoves.length) {
      state = state.copyWith(clearViewPly: true, clearError: true);
    } else {
      state = state.copyWith(viewPly: nextPly, clearError: true);
    }
  }

  /// Whether the human plays White (`!boardFlipped`) or Black (`boardFlipped`).
  /// The board itself has no notion of "whose side" a piece's color belongs
  /// to — it only ever lets you move the side whose turn it currently is —
  /// so this is what decides whether the *bot* owes the next move.
  bool get _botToMove {
    final chess = chess_lib.Chess();
    chess.load(state.fen);
    final botIsWhite = state.boardFlipped;
    return botIsWhite
        ? chess.turn == chess_lib.Color.WHITE
        : chess.turn == chess_lib.Color.BLACK;
  }

  /// If it's currently the bot's move (e.g. right after flipping to play
  /// Black on a fresh board, where White — the bot — must move first),
  /// play it. No-op otherwise.
  Future<void> _maybeBotMove() async {
    if (state.isGameOver || !_botToMove) return;
    await _playBotReply(state.fen);
  }

  void flipBoard() {
    final nextFlipped = !state.boardFlipped;
    state = state.copyWith(
      boardFlipped: nextFlipped,
      playSide: nextFlipped ? PlaySide.black : PlaySide.white,
    );
    _maybeBotMove();
  }

  bool loadFen(String fen) {
    final trimmed = fen.trim();
    final validation = chess_lib.Chess.validate_fen(trimmed);
    if (validation['valid'] != true) return false;
    final chess = chess_lib.Chess();
    if (!chess.load(trimmed)) return false; // invalid FEN — ignore
    // If the user submits the exact current board FEN while a game with move
    // history is already in progress, keep the existing initialFen and
    // sanMoves intact instead of wiping out the PGN move history.
    if (trimmed == state.fen.trim() && state.sanMoves.isNotEmpty) {
      return true;
    }
    _clockService.stop();
    state = GameState(
      fen: trimmed,
      initialFen: trimmed,
      botElo: state.botElo,
      personality: state.personality,
      boardFlipped: state.boardFlipped,
      antiBlunderEnabled: state.antiBlunderEnabled,
      mateSafetyEnabled: state.mateSafetyEnabled,
      mateSafetyN: state.mateSafetyN,
      lockHistory: state.lockHistory,
      timeControl: state.timeControl,
      whiteTimeMs: state.timeControl.initialTimeMs,
      blackTimeMs: state.timeControl.initialTimeMs,
      playSide: state.playSide,
      botCrowns: state.botCrowns,
      evalByFenKey: _gameReviewService.evalByFenKey,
      showEvalBar: state.showEvalBar,
    );
    if (state.isGameOver) {
      _awardCrownsIfHumanWon();
      _computeGameReview();
    } else {
      _maybeBotMove();
    }
    return true;
  }

  bool loadPgn(String pgn) {
    final trimmed = pgn.trim();
    if (trimmed == state.pgn.trim() && state.sanMoves.isNotEmpty) {
      return true;
    }
    final parsed = PgnCodec.parse(trimmed);
    if (parsed == null) return false;
    final (
      initialFen: initialFen,
      finalFen: finalFen,
      sanMoves: sanMoves,
      lastFrom: lastFrom,
      lastTo: lastTo,
    ) = parsed;
    _clockService.stop();
    state = GameState(
      fen: finalFen,
      initialFen: initialFen,
      sanMoves: sanMoves,
      lastMoveFrom: lastFrom,
      lastMoveTo: lastTo,
      botElo: state.botElo,
      personality: state.personality,
      boardFlipped: state.boardFlipped,
      antiBlunderEnabled: state.antiBlunderEnabled,
      mateSafetyEnabled: state.mateSafetyEnabled,
      mateSafetyN: state.mateSafetyN,
      lockHistory: state.lockHistory,
      timeControl: state.timeControl,
      whiteTimeMs: state.timeControl.initialTimeMs,
      blackTimeMs: state.timeControl.initialTimeMs,
      playSide: state.playSide,
      botCrowns: state.botCrowns,
      evalByFenKey: _gameReviewService.evalByFenKey,
      showEvalBar: state.showEvalBar,
    );
    if (state.isGameOver) {
      _awardCrownsIfHumanWon();
      _computeGameReview();
    } else {
      _syncClockTimer();
      _maybeBotMove();
    }
    return true;
  }

  /// Accepts either a FEN string or a PGN string and loads it into the game.
  bool loadFenOrPgn(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    if (loadFen(trimmed)) return true;
    return loadPgn(trimmed);
  }

  Future<void> newGame() async {
    _clockService.stop();
    final bool nextFlipped;
    switch (state.playSide) {
      case PlaySide.white:
        nextFlipped = false;
      case PlaySide.black:
        nextFlipped = true;
      case PlaySide.random:
        nextFlipped = _random.nextBool();
    }
    state = GameState(
      fen: chess_lib.Chess().fen,
      botElo: state.botElo,
      personality: state.personality,
      boardFlipped: nextFlipped,
      antiBlunderEnabled: state.antiBlunderEnabled,
      mateSafetyEnabled: state.mateSafetyEnabled,
      mateSafetyN: state.mateSafetyN,
      lockHistory: state.lockHistory,
      timeControl: state.timeControl,
      whiteTimeMs: state.timeControl.initialTimeMs,
      blackTimeMs: state.timeControl.initialTimeMs,
      playSide: state.playSide,
      botCrowns: state.botCrowns,
      evalByFenKey: _gameReviewService.evalByFenKey,
      selectedOpening: state.selectedOpening,
      showEvalBar: state.showEvalBar,
    );
    await _engine.setBotElo(state.botElo);
    await _maybeBotMove();
  }

  /// Called when the user completes a move on the board.
  /// [newFen] is the position after the user's move.
  Future<void> onUserMove(String newFen) async {
    if (state.isViewingHistory && state.lockHistory) {
      state = state.copyWith(undoRequested: true);
      return;
    }
    final preMoveFen = state.displayedFen;
    final baseMoves = state.sanMoves.sublist(0, state.currentPly);
    final preMoveParts = preMoveFen.split(RegExp(r'\s+'));
    final userMovedWhite = preMoveParts.length < 2 || preMoveParts[1] != 'b';

    // 0. Opening-book conformance — checked before the blunder check so an
    // off-book move gets the more specific message. Once the ply index is
    // past the end of the stored line, enforcement silently stops applying.
    final opening = state.selectedOpening;
    if (opening != null && baseMoves.length < opening.uciMoves.length) {
      final userUci = PgnCodec.findMove(preMoveFen, newFen)?.uci;
      if (userUci != opening.uciMoves[baseMoves.length]) {
        state = state.copyWith(
          fen: state.isViewingHistory ? state.fen : preMoveFen,
          undoRequested: true,
          errorMessage: "That's not the ${opening.name} — try again.",
          clearLastMove: !state.isViewingHistory,
        );
        return;
      }
    }

    state = state.copyWith(
      isEvaluating: true,
      clearError: true,
      undoRequested: false,
    );

    try {
      final postUserChess = chess_lib.Chess()..load(newFen);

      // 1. Blunder check (~600ms with movetime 300ms evals) — skippable via
      // the anti-blunder toggle, or if the user's move immediately delivers
      // checkmate.
      if (state.antiBlunderEnabled && !postUserChess.in_checkmate) {
        final result = await _attemptMove.execute(
          currentFen: preMoveFen,
          newFen: newFen,
        );
        if (_attemptMove.lastCurrentEval != null) {
          _gameReviewService.recordEval(
            preMoveFen,
            _attemptMove.lastCurrentEval!,
          );
        }
        if (_attemptMove.lastNewEval != null) {
          _gameReviewService.recordEval(newFen, _attemptMove.lastNewEval!);
        }

        if (result == MoveResult.blunder) {
          // Board already shows user's move optimistically — revert it
          state = state.copyWith(
            isEvaluating: false,
            fen: state.isViewingHistory ? state.fen : preMoveFen,
            undoRequested: true,
            errorMessage: 'Blunder! Find a better move.',
            clearLastMove: !state.isViewingHistory,
            evalByFenKey: _gameReviewService.evalByFenKey,
          );
          return;
        }
      }

      // 2. Accepted — lock in user move (branching from currentPly if we were
      // viewing history with lockHistory == false), then get bot reply.
      final userMove = PgnCodec.findMove(preMoveFen, newFen);
      final userSan = userMove?.san;
      final userUci = userMove?.uci;
      final userFrom = userUci != null && userUci.length >= 4
          ? userUci.substring(0, 2)
          : null;
      final userTo = userUci != null && userUci.length >= 4
          ? userUci.substring(2, 4)
          : null;
      final incMs = state.timeControl.isTimed
          ? state.timeControl.incrementMs
          : 0;
      state = state.copyWith(
        fen: newFen,
        sanMoves: userSan != null ? [...baseMoves, userSan] : baseMoves,
        lastMoveFrom: userFrom,
        lastMoveTo: userTo,
        whiteTimeMs: userMovedWhite
            ? state.whiteTimeMs + incMs
            : state.whiteTimeMs,
        blackTimeMs: !userMovedWhite
            ? state.blackTimeMs + incMs
            : state.blackTimeMs,
        evalByFenKey: _gameReviewService.evalByFenKey,
        clearViewPly: true,
        clearGameReview: true,
      );
      _syncClockTimer();
      if (state.isGameOver) {
        _clockService.stop();
        state = state.copyWith(isEvaluating: false);
        _awardCrownsIfHumanWon();
        _computeGameReview();
        return;
      }
      if (!_botToMove) {
        state = state.copyWith(isEvaluating: false);
        return;
      }
      await _playBotReply(newFen);
    } catch (_) {
      state = state.copyWith(
        isEvaluating: false,
        fen: state.isViewingHistory ? state.fen : preMoveFen,
        undoRequested: true,
        errorMessage: 'Engine error. Try again.',
      );
    }
  }

  /// Asks the engine for a reply to [fen] and applies it. Shared by the
  /// post-user-move flow and `_maybeBotMove` (flip / new game / load FEN
  /// landing on a position where the bot owes the next move).
  Future<void> _playBotReply(String fen) async {
    state = state.copyWith(isEvaluating: true, clearError: true);
    try {
      // Natural humanized bot thinking delay (300ms - 650ms) to allow the player's
      // piece animation to finish settling and feel like a real opponent.
      if (enableBotDelay) {
        final botDelayMs = 300 + _random.nextInt(350);
        await Future.delayed(Duration(milliseconds: botDelayMs));
        if (!mounted) return;
      }

      final preBotParts = fen.split(RegExp(r'\s+'));
      final botMovedWhite = preBotParts.length < 2 || preBotParts[1] != 'b';
      final ctx = _botMoveContext(fen, state.botElo);
      final botUci = await MateSafetyDecorator(
        kDefaultBotMovePipeline,
      ).selectMove(ctx);

      if (botUci == '(none)' || botUci.isEmpty) {
        state = state.copyWith(isEvaluating: false);
        return;
      }

      final (afterBot, botSan) = PgnCodec.applyUciWithSan(fen, botUci);
      final incMs = state.timeControl.isTimed
          ? state.timeControl.incrementMs
          : 0;
      state = state.copyWith(
        fen: afterBot,
        sanMoves: botSan != null ? [...state.sanMoves, botSan] : state.sanMoves,
        whiteTimeMs: botMovedWhite
            ? state.whiteTimeMs + incMs
            : state.whiteTimeMs,
        blackTimeMs: !botMovedWhite
            ? state.blackTimeMs + incMs
            : state.blackTimeMs,
        evalByFenKey: _gameReviewService.evalByFenKey,
        isEvaluating: false,
        lastMoveFrom: botUci.substring(0, 2),
        lastMoveTo: botUci.substring(2, 4),
      );
      _syncClockTimer();
      if (state.isGameOver) {
        _clockService.stop();
        _awardCrownsIfHumanWon();
        _computeGameReview();
      }
    } catch (_) {
      state = state.copyWith(
        isEvaluating: false,
        errorMessage: 'Engine error. Try again.',
      );
    }
  }

  /// Computes the post-game performance rating & accuracy review for both
  /// players. Immediately sets a preliminary [GameReviewSummary] from cached
  /// evaluations, then fills in any uncached positions asynchronously.
  Future<void> _computeGameReview() async {
    final snapInitialFen = state.initialFen;
    final snapSanMoves = List<String>.from(state.sanMoves);
    final snapBotElo = state.botElo;
    final snapHumanIsWhite = !state.boardFlipped;

    final initialSummary = _gameReviewService.analyze(
      initialFen: snapInitialFen,
      sanMoves: snapSanMoves,
      botElo: snapBotElo,
      humanIsWhite: snapHumanIsWhite,
    );

    final chess = chess_lib.Chess();
    final missingFens = <String>[];
    if (chess_lib.Chess.validate_fen(snapInitialFen)['valid'] == true &&
        chess.load(snapInitialFen)) {
      void checkFen(String f) {
        if (!_gameReviewService.containsEval(f)) {
          missingFens.add(f);
        }
      }

      checkFen(chess.fen);
      for (final san in snapSanMoves) {
        if (!chess.move(san)) break;
        if (!chess.game_over &&
            !ScholarsMateHunterPolicy.isInsufficientMatingMaterial(chess.fen)) {
          checkFen(chess.fen);
        }
      }
    }

    if (missingFens.isEmpty) {
      state = state.copyWith(
        gameReview: initialSummary,
        evalByFenKey: _gameReviewService.evalByFenKey,
        isAnalyzingGameReview: false,
      );
      return;
    }

    state = state.copyWith(
      gameReview: initialSummary,
      evalByFenKey: _gameReviewService.evalByFenKey,
      isAnalyzingGameReview: true,
    );

    try {
      for (final f in missingFens) {
        if (!mounted || state.sanMoves.length != snapSanMoves.length) return;
        await _gameReviewService.ensureEvaluated(f);
      }
      if (!mounted || state.sanMoves.length != snapSanMoves.length) return;
      final refinedSummary = _gameReviewService.analyze(
        initialFen: snapInitialFen,
        sanMoves: snapSanMoves,
        botElo: snapBotElo,
        humanIsWhite: snapHumanIsWhite,
      );
      state = state.copyWith(
        gameReview: refinedSummary,
        evalByFenKey: _gameReviewService.evalByFenKey,
        isAnalyzingGameReview: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isAnalyzingGameReview: false);
    }
  }

  /// Clears the undo signal after the board widget has handled it.
  void clearUndo() {
    state = state.copyWith(undoRequested: false);
  }
}
