import 'dart:async' show Timer;
import 'dart:developer' as developer;
import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../../data/repositories/chess_engine_repository_impl.dart';
import '../../domain/entities/bot_personality.dart';
import '../../domain/entities/bot_style_policy.dart';
import '../../domain/entities/chess_opening.dart';
import '../../domain/entities/move_result.dart';
import '../../domain/entities/time_control.dart';
import '../../domain/repositories/chess_engine_repository.dart';
import '../../domain/usecases/attempt_move_usecase.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import '../../domain/usecases/pawn_pusher_policy.dart';
import '../../domain/usecases/scholars_mate_hunter_policy.dart';

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
  String get pgn {
    final chess = _buildGameChess();
    final String result;
    if (timeoutWinner != null) {
      result = timeoutWinner == 'white' ? '1-0' : '0-1';
    } else if (chess.in_checkmate) {
      result = chess.turn == chess_lib.Color.WHITE ? '0-1' : '1-0';
    } else if (isDraw) {
      result = '1/2-1/2';
    } else {
      result = '*';
    }

    final whiteName = boardFlipped ? '${personality.name} ($botElo)' : 'You';
    final blackName = boardFlipped ? 'You' : '${personality.name} ($botElo)';

    final headers = <String>[
      '[Event "Anti-Blunder Chess"]',
      '[Site "Local"]',
      '[White "$whiteName"]',
      '[Black "$blackName"]',
      '[Result "$result"]',
      if (timeControl.isTimed) '[TimeControl "${timeControl.key}"]',
      if (initialFen != chess_lib.Chess.DEFAULT_POSITION) ...[
        '[SetUp "1"]',
        '[FEN "$initialFen"]',
      ],
    ];

    final initTokens = initialFen.split(RegExp(r'\s+'));
    var whiteToMove = initTokens.length > 1 ? initTokens[1] == 'w' : true;
    var moveNumber =
        (initTokens.length > 5 ? int.tryParse(initTokens[5]) : null) ?? 1;

    final moveTokens = <String>[];
    for (var i = 0; i < sanMoves.length; i++) {
      final san = sanMoves[i];
      if (whiteToMove) {
        moveTokens.add('$moveNumber. $san');
        whiteToMove = false;
      } else {
        if (i == 0) {
          moveTokens.add('$moveNumber... $san');
        } else {
          moveTokens.add(san);
        }
        moveNumber++;
        whiteToMove = true;
      }
    }
    moveTokens.add(result);

    return '${headers.join('\n')}\n\n${moveTokens.join(' ')}';
  }

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

class GameNotifier extends StateNotifier<GameState> {
  final ChessEngineRepository _engine;
  final AttemptMoveUseCase _attemptMove;
  final Map<String, int> _fenEvalCache = {
    GameReviewAnalyzer.fenKey(chess_lib.Chess.DEFAULT_POSITION): 20,
  };
  Timer? _clockTimer;

  GameNotifier(this._engine, this._attemptMove)
    : super(
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
    _clockTimer?.cancel();
    _clockTimer = null;
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
        final newFen = _applyUci(state.fen, uci);
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

  int _moveTimeMs(int elo) => (elo / 1.5).floor().clamp(400, 2000);

  // Stockfish's `Skill Level` bottoms out at ~1300 real playing strength
  // even at its own minimum (see docs/GOTCHAS.md — the Skill Level knob
  // was never designed to emulate a genuinely weak human). Below 1000 ELO
  // on the difficulty slider, it can't get any weaker on its own, so below
  // that we blend in two increasingly common substitutes for the engine's
  // real choice, matching the "weak bot" behavior chess.com's own
  // low-rated bots use (shallow/blundering, not a strong engine turned
  // down) and, at the very bottom, active self-sabotage:
  //   - a uniformly random legal move ("blunder"): 0% at 1000 ELO, rising
  //     to 50% at 250 and below — the same trick
  //     web_engine_repository.dart's mock already uses for every move.
  //   - the worst move out of a small sample ("worst move"): 0% at 250
  //     ELO and above, rising to 100% at the slider's floor (0) — "trying
  //     to lose as fast as possible".
  // The two bands meet at 250 (50%/0%) so the transition from "normal
  // weak play" to "actively trying to lose" is continuous, not a jump.
  static const _worstMoveThreshold = 250;
  final _random = Random();

  double _blunderChance(int elo) {
    if (elo >= 1000) return 0;
    return ((1000 - elo) / (1000 - _worstMoveThreshold)).clamp(0.0, 1.0) * 0.5;
  }

  double _worstMoveChance(int elo) {
    if (elo >= _worstMoveThreshold) return 0;
    return (1 - elo / _worstMoveThreshold).clamp(0.0, 1.0);
  }

  /// Evaluates a small random sample of legal moves and returns whichever
  /// leaves the bot worst off. Sampling (not every legal move) keeps this
  /// from taking seconds in the opening, where there are 20+ legal moves;
  /// "worst of ~5" is still a clearly self-destructive choice almost all
  /// the time without the latency of exhaustively checking every option.
  Future<String> _pickWorstMove(String fen) async {
    final chess = chess_lib.Chess()..load(fen);
    final moves = chess.generate_moves()..shuffle(_random);
    if (moves.isEmpty) return '(none)';

    String worstUci = '';
    int? worstEvalForOpponent;
    for (final m in moves.take(5)) {
      final from = chess_lib.Chess.algebraic(m.from);
      final to = chess_lib.Chess.algebraic(m.to);
      final promo = m.promotion != null ? m.promotion!.name : '';
      final uci = '$from$to$promo';
      final afterFen = _applyUci(fen, uci);
      // evaluateFen is from the perspective of the side to move in
      // afterFen — i.e. the opponent. The higher that is, the worse this
      // move was for the bot.
      final evalForOpponent = await _engine.evaluateFen(afterFen);
      if (worstEvalForOpponent == null ||
          evalForOpponent > worstEvalForOpponent) {
        worstEvalForOpponent = evalForOpponent;
        worstUci = uci;
      }
    }
    return worstUci;
  }

  Future<String> _pickBotMove(String fen, int elo) async {
    // Opening-book conformance: while an opening is selected, the bot plays
    // the book reply too (so both sides rehearse the exact line) rather
    // than its usual personality/difficulty logic, until the stored line
    // runs out.
    final opening = state.selectedOpening;
    final ply = state.sanMoves.length;
    if (opening != null && ply < opening.uciMoves.length) {
      return opening.uciMoves[ply];
    }

    final posCounts = state.positionCounts;

    // Below 1000 ELO, apply the difficulty weakening curve to all personalities
    // so dragging the ELO slider down to Beginner / Very Easy / Trying to Lose
    // genuinely weakens custom personalities too.
    final roll = _random.nextDouble();
    if (roll < _worstMoveChance(elo)) {
      return _pickWorstMove(fen);
    }
    if (roll < _worstMoveChance(elo) + _blunderChance(elo)) {
      final chess = chess_lib.Chess()..load(fen);
      final moves = chess.generate_moves();
      if (moves.isNotEmpty) {
        final nonDrawing = moves.where((m) {
          final uci =
              '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';
          return !ScholarsMateHunterPolicy.wouldCauseDraw(
                fen,
                uci,
                posCounts,
              ) &&
              !ScholarsMateHunterPolicy.wouldRepeatPosition(
                fen,
                uci,
                posCounts,
              );
        }).toList();
        var pool = nonDrawing.isNotEmpty ? nonDrawing : moves;
        // If Pawn Pusher blunders at low ELO, still prefer pushing a random pawn!
        if (state.personality.id == 'pawn_pusher') {
          final pawnPool = pool
              .where((m) => m.piece == chess_lib.PieceType.PAWN)
              .toList();
          if (pawnPool.isNotEmpty) {
            pool = pawnPool;
          }
        }
        final m = pool[_random.nextInt(pool.length)];
        final from = chess_lib.Chess.algebraic(m.from);
        final to = chess_lib.Chess.algebraic(m.to);
        final promo = m.promotion != null ? m.promotion!.name : '';
        return '$from$to$promo';
      }
    }

    if (state.personality.id == 'aggressor') {
      final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(fen);
      if (mateIn1 != null) return mateIn1;

      final mateIn2 = ScholarsMateHunterPolicy.findForcedMateIn2(
        fen,
        posCounts,
      );
      if (mateIn2 != null) return mateIn2;

      final candidates = await _engine.getTopMoves(
        fen,
        movetimeMs: _moveTimeMs(elo),
        multiPv: 10,
        mateLimit: 8,
      );
      if (candidates.isNotEmpty) {
        _fenEvalCache[GameReviewAnalyzer.fenKey(fen)] =
            candidates.first.scoreCp;
      }
      final chosen = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: candidates,
        positionCounts: posCounts,
      );
      if (chosen != null && chosen.isNotEmpty) {
        return chosen;
      }
    }

    if (state.personality.id == 'pawn_pusher') {
      final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(fen);
      if (mateIn1 != null) return mateIn1;

      final candidates = await _engine.getTopMoves(
        fen,
        movetimeMs: _moveTimeMs(elo),
        multiPv: 10,
      );
      if (candidates.isNotEmpty) {
        _fenEvalCache[GameReviewAnalyzer.fenKey(fen)] =
            candidates.first.scoreCp;
      }
      final chosen = PawnPusherPolicy.selectMove(
        fen: fen,
        candidates: candidates,
        positionCounts: posCounts,
      );
      if (chosen != null && chosen.isNotEmpty) {
        return chosen;
      }
    }

    final stylePolicy = styleForPersonalityId(state.personality.id);
    if (stylePolicy != null) {
      final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(fen);
      if (mateIn1 != null) return mateIn1;

      final candidates = await _engine.getTopMoves(
        fen,
        movetimeMs: _moveTimeMs(elo),
        multiPv: 6,
      );
      if (candidates.isNotEmpty) {
        _fenEvalCache[GameReviewAnalyzer.fenKey(fen)] =
            candidates.first.scoreCp;
      }
      final nonDrawing = candidates
          .where(
            (c) =>
                !ScholarsMateHunterPolicy.wouldCauseDraw(
                  fen,
                  c.uci,
                  posCounts,
                ) &&
                !ScholarsMateHunterPolicy.wouldRepeatPosition(
                  fen,
                  c.uci,
                  posCounts,
                ),
          )
          .toList();
      final chosen = stylePolicy.pickMove(
        fen,
        nonDrawing.isNotEmpty ? nonDrawing : candidates,
      );
      if (chosen != null && chosen.isNotEmpty) {
        return chosen;
      }
    }

    final bestMove = await _engine.getBestMove(
      fen,
      movetimeMs: _moveTimeMs(elo),
    );
    if (bestMove.isNotEmpty &&
        bestMove != '(none)' &&
        (ScholarsMateHunterPolicy.wouldCauseDraw(fen, bestMove, posCounts) ||
            ScholarsMateHunterPolicy.wouldRepeatPosition(
              fen,
              bestMove,
              posCounts,
            ))) {
      final candidates = await _engine.getTopMoves(
        fen,
        movetimeMs: _moveTimeMs(elo),
        multiPv: 5,
      );
      for (final c in candidates) {
        if (c.mateIn != null && c.mateIn! < 0) continue;
        if (!ScholarsMateHunterPolicy.wouldCauseDraw(fen, c.uci, posCounts) &&
            !ScholarsMateHunterPolicy.wouldRepeatPosition(
              fen,
              c.uci,
              posCounts,
            )) {
          return c.uci;
        }
      }
      for (final c in candidates) {
        if (c.mateIn != null && c.mateIn! < 0) continue;
        if (!ScholarsMateHunterPolicy.wouldCauseDraw(fen, c.uci, posCounts)) {
          return c.uci;
        }
      }
    }
    return bestMove;
  }

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
  /// starts a fresh game — see docs/features/opening_book_follower.md for
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
    _clockTimer?.cancel();
    _clockTimer = null;
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
        _clockTimer?.cancel();
        _clockTimer = null;
        state = state.copyWith(whiteTimeMs: 0, timeoutWinner: 'black');
        _awardCrownsIfHumanWon();
        _computeGameReview();
      } else {
        state = state.copyWith(whiteTimeMs: next);
      }
    } else {
      final next = (state.blackTimeMs - elapsedMs).clamp(0, 86400000);
      if (next <= 0) {
        _clockTimer?.cancel();
        _clockTimer = null;
        state = state.copyWith(blackTimeMs: 0, timeoutWinner: 'white');
        _awardCrownsIfHumanWon();
        _computeGameReview();
      } else {
        state = state.copyWith(blackTimeMs: next);
      }
    }
  }

  void _syncClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = null;
    if (!state.timeControl.isTimed || state.isGameOver) return;
    if (state.sanMoves.isEmpty) return;
    _clockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        _clockTimer?.cancel();
        _clockTimer = null;
        return;
      }
      tickClock(100);
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

  // If mate safety is on, checks whether [candidateUci] (played from
  // [fen]) hands the human a forced mate within `state.mateSafetyN`
  // moves — if so, substitutes the engine's own straightforward best move
  // instead. This is a best-effort single retry, not a guarantee: in a
  // position where literally every legal move allows a short mate, the
  // fallback can still be unsafe, and this doesn't re-check it. The mate
  // search always runs at full engine strength regardless of bot
  // difficulty (same reasoning as the anti-blunder shield — see
  // GOTCHAS #14), since the whole point is "no matter how weak" the bot is.
  Future<String> _applyMateSafety(String fen, String candidateUci) async {
    if (!state.mateSafetyEnabled) return candidateUci;
    final n = state.mateSafetyN;
    final afterCandidate = _applyUci(fen, candidateUci);
    final humanMateIn = await _engine.getMateDistance(
      afterCandidate,
      movetimeMs: (n * 200).clamp(300, 3000),
    );
    final isUnsafe = humanMateIn != null && humanMateIn > 0 && humanMateIn <= n;
    if (!isUnsafe) return candidateUci;
    return _engine.getBestMove(fen, movetimeMs: _moveTimeMs(state.botElo));
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
    _clockTimer?.cancel();
    _clockTimer = null;
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
      evalByFenKey: Map<String, int>.from(_fenEvalCache),
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
    final parsed = _parsePgn(trimmed);
    if (parsed == null) return false;
    final (initialFen, finalFen, sanMoves, lastFrom, lastTo) = parsed;
    _clockTimer?.cancel();
    _clockTimer = null;
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
      evalByFenKey: Map<String, int>.from(_fenEvalCache),
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
    _clockTimer?.cancel();
    _clockTimer = null;
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
      evalByFenKey: Map<String, int>.from(_fenEvalCache),
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
      final userUci = _findUciMove(preMoveFen, newFen);
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
          _fenEvalCache[GameReviewAnalyzer.fenKey(preMoveFen)] =
              _attemptMove.lastCurrentEval!;
        }
        if (_attemptMove.lastNewEval != null) {
          _fenEvalCache[GameReviewAnalyzer.fenKey(newFen)] =
              _attemptMove.lastNewEval!;
        }

        if (result == MoveResult.blunder) {
          // Board already shows user's move optimistically — revert it
          state = state.copyWith(
            isEvaluating: false,
            fen: state.isViewingHistory ? state.fen : preMoveFen,
            undoRequested: true,
            errorMessage: 'Blunder! Find a better move.',
            clearLastMove: !state.isViewingHistory,
            evalByFenKey: Map<String, int>.from(_fenEvalCache),
          );
          return;
        }
      }

      // 2. Accepted — lock in user move (branching from currentPly if we were
      // viewing history with lockHistory == false), then get bot reply.
      final userSan = _findSanMove(preMoveFen, newFen);
      final incMs = state.timeControl.isTimed
          ? state.timeControl.incrementMs
          : 0;
      state = state.copyWith(
        fen: newFen,
        sanMoves: userSan != null ? [...baseMoves, userSan] : baseMoves,
        whiteTimeMs: userMovedWhite
            ? state.whiteTimeMs + incMs
            : state.whiteTimeMs,
        blackTimeMs: !userMovedWhite
            ? state.blackTimeMs + incMs
            : state.blackTimeMs,
        evalByFenKey: Map<String, int>.from(_fenEvalCache),
        clearViewPly: true,
        clearLastMove: true,
        clearGameReview: true,
      );
      _syncClockTimer();
      if (state.isGameOver) {
        _clockTimer?.cancel();
        _clockTimer = null;
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
      final preBotParts = fen.split(RegExp(r'\s+'));
      final botMovedWhite = preBotParts.length < 2 || preBotParts[1] != 'b';
      final rawUci = await _pickBotMove(fen, state.botElo);

      if (rawUci == '(none)' || rawUci.isEmpty) {
        state = state.copyWith(isEvaluating: false);
        return;
      }

      final botUci = await _applyMateSafety(fen, rawUci);
      final (afterBot, botSan) = _applyUciWithSan(fen, botUci);
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
        evalByFenKey: Map<String, int>.from(_fenEvalCache),
        isEvaluating: false,
        lastMoveFrom: botUci.substring(0, 2),
        lastMoveTo: botUci.substring(2, 4),
      );
      _syncClockTimer();
      if (state.isGameOver) {
        _clockTimer?.cancel();
        _clockTimer = null;
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

    final initialSummary = GameReviewAnalyzer.analyze(
      initialFen: snapInitialFen,
      sanMoves: snapSanMoves,
      evalByFenKey: Map<String, int>.from(_fenEvalCache),
      botElo: snapBotElo,
      humanIsWhite: snapHumanIsWhite,
    );

    final chess = chess_lib.Chess();
    final missingFens = <String>[];
    if (chess_lib.Chess.validate_fen(snapInitialFen)['valid'] == true &&
        chess.load(snapInitialFen)) {
      void checkFen(String f) {
        final key = GameReviewAnalyzer.fenKey(f);
        if (!_fenEvalCache.containsKey(key)) {
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
        evalByFenKey: Map<String, int>.from(_fenEvalCache),
        isAnalyzingGameReview: false,
      );
      return;
    }

    state = state.copyWith(
      gameReview: initialSummary,
      evalByFenKey: Map<String, int>.from(_fenEvalCache),
      isAnalyzingGameReview: true,
    );

    try {
      for (final f in missingFens) {
        if (!mounted || state.sanMoves.length != snapSanMoves.length) return;
        final key = GameReviewAnalyzer.fenKey(f);
        if (_fenEvalCache.containsKey(key)) continue;
        final score = await _engine.evaluateFen(f);
        _fenEvalCache[key] = score;
      }
      if (!mounted || state.sanMoves.length != snapSanMoves.length) return;
      final refinedSummary = GameReviewAnalyzer.analyze(
        initialFen: snapInitialFen,
        sanMoves: snapSanMoves,
        evalByFenKey: Map<String, int>.from(_fenEvalCache),
        botElo: snapBotElo,
        humanIsWhite: snapHumanIsWhite,
      );
      state = state.copyWith(
        gameReview: refinedSummary,
        evalByFenKey: Map<String, int>.from(_fenEvalCache),
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

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Finds the SAN representation of the legal move that transitions
  /// [fromFen] to [toFen], or `null` if no legal move matches.
  static String? _findSanMove(String fromFen, String toFen) {
    final chess = chess_lib.Chess()..load(fromFen);
    final moves = chess.generate_moves();
    String? boardMatchSan;
    final toBoardPart = toFen.split(RegExp(r'\s+')).take(4).join(' ');
    for (final move in moves) {
      final san = chess.move_to_san(move);
      chess.make_move(move);
      final resultingFen = chess.fen;
      chess.undo_move();
      if (resultingFen == toFen) {
        return san;
      }
      if (boardMatchSan == null &&
          resultingFen.split(RegExp(r'\s+')).take(4).join(' ') == toBoardPart) {
        boardMatchSan = san;
      }
    }
    return boardMatchSan;
  }

  /// Same idea as `_findSanMove`, but returns the UCI form — used to check
  /// a user's move against `selectedOpening`'s scripted line.
  static String? _findUciMove(String fromFen, String toFen) {
    final chess = chess_lib.Chess()..load(fromFen);
    for (final move in chess.generate_moves()) {
      final from = chess_lib.Chess.algebraic(move.from);
      final to = chess_lib.Chess.algebraic(move.to);
      final promo = move.promotion != null ? move.promotion!.name : '';
      chess.make_move(move);
      final resultingFen = chess.fen;
      chess.undo_move();
      if (resultingFen == toFen) {
        return '$from$to$promo';
      }
    }
    return null;
  }

  /// Applies a UCI move string to a FEN and returns the resulting FEN and SAN.
  static (String, String?) _applyUciWithSan(String fen, String uci) {
    final chess = chess_lib.Chess()..load(fen);
    final moved = chess.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return (chess.fen, null);
    final history = chess.getHistory();
    final san = history.isNotEmpty ? history.last as String : null;
    return (chess.fen, san);
  }

  /// Applies a UCI move string to a FEN and returns the resulting FEN.
  static String _applyUci(String fen, String uci) {
    final (afterFen, _) = _applyUciWithSan(fen, uci);
    return afterFen;
  }

  /// Parses a PGN string (with or without headers) and returns
  /// `(initialFen, finalFen, sanMoves, lastMoveFrom, lastMoveTo)` if valid,
  /// or `null` if the PGN cannot be parsed or contains illegal moves.
  static (String, String, List<String>, String?, String?)? _parsePgn(
    String pgn,
  ) {
    final trimmed = pgn.trim();
    if (trimmed.isEmpty) return null;

    final headerRegex = RegExp(
      r'^\s*\[([A-Za-z0-9_]+)\s+"([^"]*)"\]\s*$',
      multiLine: true,
    );
    final headers = <String, String>{};
    for (final match in headerRegex.allMatches(trimmed)) {
      headers[match.group(1)!] = match.group(2)!;
    }

    var movetext = trimmed.replaceAll(headerRegex, ' ');
    movetext = movetext.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
    movetext = movetext.replaceAll(RegExp(r';[^\r\n]*'), ' ');
    final variationRegex = RegExp(r'\([^()]*\)');
    while (variationRegex.hasMatch(movetext)) {
      movetext = movetext.replaceAll(variationRegex, ' ');
    }
    movetext = movetext.replaceAll(RegExp(r'\$\d+'), ' ');
    movetext = movetext.replaceAll(RegExp(r'\d+\.+'), ' ');

    const results = {'1-0', '0-1', '1/2-1/2', '*'};
    final tokens = movetext
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !results.contains(t))
        .toList();

    if (headers.isEmpty && tokens.isEmpty) return null;

    final chess = chess_lib.Chess();
    var initialFen = chess_lib.Chess.DEFAULT_POSITION;
    if (headers.containsKey('FEN')) {
      final fenHeader = headers['FEN']!.trim();
      if (chess_lib.Chess.validate_fen(fenHeader)['valid'] != true) {
        return null;
      }
      if (!chess.load(fenHeader)) return null;
      initialFen = fenHeader;
    }

    final sanMoves = <String>[];
    String? lastFrom;
    String? lastTo;

    for (final rawToken in tokens) {
      final cleanToken = rawToken
          .replaceAll(RegExp(r'[+#?!]+$'), '')
          .replaceAll('0', 'O');
      chess_lib.Move? matchedMove;
      String? matchedSan;
      for (final m in chess.generate_moves()) {
        final san = chess.move_to_san(m);
        final cleanSan = san.replaceAll(RegExp(r'[+#?!]+$'), '');
        final uci =
            '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';
        if (san == rawToken || cleanSan == cleanToken || uci == rawToken) {
          matchedMove = m;
          matchedSan = san;
          break;
        }
      }
      if (matchedMove == null || matchedSan == null) {
        return null;
      }
      sanMoves.add(matchedSan);
      lastFrom = matchedMove.fromAlgebraic;
      lastTo = matchedMove.toAlgebraic;
      chess.make_move(matchedMove);
    }

    return (initialFen, chess.fen, sanMoves, lastFrom, lastTo);
  }
}
