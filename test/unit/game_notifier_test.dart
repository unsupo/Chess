import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:chess_teacher/core/widgets/chess_board/chess_board_widget.dart';
import 'package:chess_teacher/features/game/domain/repositories/chess_engine_repository.dart';
import 'package:chess_teacher/features/game/domain/usecases/attempt_move_usecase.dart';
import 'package:chess_teacher/features/game/presentation/providers/game_provider.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _afterE4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
// FEN after e4 + e5 (bot reply)
const _afterE5Fen =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';

class _FakeEngine extends ChessEngineRepository {
  int eloSet = 0;
  String moveToReturn;

  _FakeEngine({this.moveToReturn = 'e7e5'});

  @override
  Future<void> setBotElo(int elo) async => eloSet = elo;

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async => 0;

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async =>
      moveToReturn;

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async =>
      null;

  @override
  void dispose() {}
}

GameNotifier _makeNotifier(ChessEngineRepository engine) {
  return GameNotifier(
    engine,
    AttemptMoveUseCase(engine),
    enableBotDelay: false,
  );
}

void main() {
  group('GameNotifier', () {
    test('initial state has starting FEN and 900 ELO (Martin default)', () {
      final notifier = _makeNotifier(_FakeEngine());
      expect(notifier.state.fen, _startFen);
      expect(notifier.state.botElo, 900);
      expect(notifier.state.isEvaluating, false);
    });

    test(
      'setDifficulty updates botElo and calls setBotElo on engine',
      () async {
        final engine = _FakeEngine();
        final notifier = _makeNotifier(engine);
        await notifier.setDifficulty(1600);
        expect(notifier.state.botElo, 1600);
        expect(engine.eloSet, 1600);
      },
    );

    test('newGame resets FEN to starting position and keeps ELO', () async {
      final engine = _FakeEngine();
      final notifier = _makeNotifier(engine);
      await notifier.setDifficulty(2000);
      // Simulate a move so FEN changes
      await notifier.onUserMove(_afterE4Fen);
      await notifier.newGame();
      expect(notifier.state.fen, chess_lib.Chess().fen);
      expect(notifier.state.botElo, 2000);
      expect(notifier.state.isEvaluating, false);
    });

    test('onUserMove sets isEvaluating then clears it', () async {
      final engine = _FakeEngine(moveToReturn: 'e7e5');
      final notifier = _makeNotifier(engine);

      bool sawEvaluating = false;
      notifier.addListener((state) {
        if (state.isEvaluating) sawEvaluating = true;
      });

      await notifier.onUserMove(_afterE4Fen);
      expect(sawEvaluating, true);
      expect(notifier.state.isEvaluating, false);
    });

    test('onUserMove applies bot reply to FEN and sets lastMove', () async {
      final engine = _FakeEngine(moveToReturn: 'e7e5');
      final notifier = _makeNotifier(engine);
      await notifier.setDifficulty(1200);
      await notifier.onUserMove(_afterE4Fen);
      expect(notifier.state.fen, _afterE5Fen);
      expect(notifier.state.lastMoveFrom, 'e7');
      expect(notifier.state.lastMoveTo, 'e5');
    });

    test('onUserMove reverts to preMoveFen on blunder', () async {
      // Engine evals: currentFen=0, newFen=400 → delta=-400 < -300 → blunder
      final blunderEngine = _OverrideEvalEngine(
        evals: [0, 400],
        moveToReturn: 'e7e5',
      );
      final notifier = GameNotifier(
        blunderEngine,
        AttemptMoveUseCase(blunderEngine),
      );
      await notifier.onUserMove(_afterE4Fen);
      // Blunder detected AFTER bot moves — state reverts to pre-move FEN
      expect(notifier.state.fen, _startFen);
      expect(notifier.state.undoRequested, true);
      expect(notifier.state.errorMessage, 'Blunder! Find a better move.');
      expect(notifier.state.isEvaluating, false);
    });

    test('clearUndo is a no-op when undoRequested is already false', () {
      final notifier = _makeNotifier(_FakeEngine());
      notifier.clearUndo();
      expect(notifier.state.undoRequested, false);
    });

    test(
      'pgn includes headers and SAN move history after accepted move',
      () async {
        final engine = _FakeEngine(moveToReturn: 'e7e5');
        final notifier = _makeNotifier(engine);
        await notifier.setDifficulty(1200);
        await notifier.onUserMove(_afterE4Fen);

        final pgn = notifier.state.pgn;
        expect(pgn, contains('[Event "Anti-Blunder Chess"]'));
        expect(pgn, contains('[White "You"]'));
        expect(pgn, contains('[Black "Martin (1200)"]'));
        expect(pgn, contains('[Result "*"]'));
        expect(pgn, contains('1. e4 e5 *'));
      },
    );

    test('pgn omits blundered moves and resets on newGame', () async {
      final blunderEngine = _OverrideEvalEngine(
        evals: [0, 400],
        moveToReturn: 'e7e5',
      );
      final notifier = GameNotifier(
        blunderEngine,
        AttemptMoveUseCase(blunderEngine),
      );
      await notifier.onUserMove(_afterE4Fen);
      expect(notifier.state.sanMoves, isEmpty);
      expect(notifier.state.pgn, endsWith('\n\n*'));
    });

    test('loadFen sets SetUp and FEN headers in pgn', () {
      final engine = _FakeEngine(moveToReturn: 'e7e5');
      final notifier = _makeNotifier(engine);
      // Load a custom FEN where White is to move on move 2
      notifier.loadFen(_afterE5Fen);

      final pgn = notifier.state.pgn;
      expect(pgn, contains('[SetUp "1"]'));
      expect(pgn, contains('[FEN "$_afterE5Fen"]'));
    });

    test('loadPgn loads full PGN with headers and moves', () {
      final engine = _FakeEngine(moveToReturn: 'e7e5');
      final notifier = _makeNotifier(engine);
      const samplePgn = '''
[Event "Anti-Blunder Chess"]
[Site "Local"]
[White "You"]
[Black "Martin (900)"]
[Result "*"]

1. e4 e5 *
''';
      final ok = notifier.loadPgn(samplePgn);
      expect(ok, true);
      expect(notifier.state.fen, _afterE5Fen);
      expect(notifier.state.sanMoves, ['e4', 'e5']);
      expect(notifier.state.lastMoveFrom, 'e7');
      expect(notifier.state.lastMoveTo, 'e5');
    });

    test(
      'loadFenOrPgn accepts either FEN or PGN and rejects invalid input',
      () {
        final engine = _FakeEngine(moveToReturn: 'e7e5');
        final notifier = _makeNotifier(engine);

        expect(notifier.loadFenOrPgn('1. e4 e5'), true);
        expect(notifier.state.fen, _afterE5Fen);
        expect(notifier.state.sanMoves, ['e4', 'e5']);

        expect(notifier.loadFenOrPgn(_startFen), true);
        expect(notifier.state.fen, _startFen);
        expect(notifier.state.sanMoves, isEmpty);

        expect(notifier.loadFenOrPgn('not a valid fen or pgn'), false);
      },
    );

    test('materialFor computes captured pieces and scores for both sides', () {
      final engine = _FakeEngine(moveToReturn: 'e7e5');
      final notifier = _makeNotifier(engine);

      // Position where White captured a Black knight and pawn (4 pts) and
      // Black captured a White pawn (1 pt) -> White is +3.
      notifier.loadFen(
        'r1bqkbnr/ppp1pppp/8/8/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1',
      );

      final whiteMat = notifier.state.materialFor(isWhite: true);
      final blackMat = notifier.state.materialFor(isWhite: false);

      expect(whiteMat.capturedPieces, ['bN', 'bP']);
      expect(whiteMat.capturedScore, 4);
      expect(whiteMat.netAdvantage, 3);

      expect(blackMat.capturedPieces, ['wP']);
      expect(blackMat.capturedScore, 1);
      expect(blackMat.netAdvantage, -3);
    });

    test(
      'detects stalemate, insufficient material, 50-move rule, threefold repetition, and checkmate',
      () {
        final engine = _FakeEngine(moveToReturn: 'e7e5');
        final notifier = _makeNotifier(engine);

        // 1. Stalemate (Black to move, not in check, no legal moves)
        notifier.loadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
        expect(notifier.state.isDraw, true);
        expect(notifier.state.isGameOver, true);
        expect(notifier.state.gameOverMessage, 'Draw by stalemate');
        expect(notifier.state.pgn, contains('[Result "1/2-1/2"]'));

        // 2. Insufficient material (King vs King, KB vs K, KB vs KB opposite color, K+2N vs K)
        notifier.loadFen('8/8/4k3/8/8/4K3/8/8 w - - 0 1');
        expect(notifier.state.isDraw, true);
        expect(notifier.state.gameOverMessage, 'Draw by insufficient material');

        notifier.loadFen(
          '8/8/4k3/8/3b4/4KB2/8/8 w - - 0 1',
        ); // KB vs KB opposite colors
        expect(notifier.state.isDraw, true);
        expect(notifier.state.isGameOver, true);
        expect(notifier.state.gameOverMessage, 'Draw by insufficient material');

        notifier.loadFen('8/8/4k3/8/8/3NKN2/8/8 w - - 0 1'); // K+2N vs K
        expect(notifier.state.isDraw, true);
        expect(notifier.state.gameOverMessage, 'Draw by insufficient material');

        // 3. 50-move rule (half_moves >= 100)
        notifier.loadFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 100 51',
        );
        expect(notifier.state.isDraw, true);
        expect(notifier.state.gameOverMessage, 'Draw by 50-move rule');

        // 4. Threefold repetition via PGN history
        notifier.loadPgn('1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8');
        expect(notifier.state.isDraw, true);
        expect(notifier.state.isGameOver, true);
        expect(notifier.state.gameOverMessage, 'Draw by threefold repetition');
        expect(notifier.state.pgn, contains('[Result "1/2-1/2"]'));

        // 5. Checkmate (Scholar's Mate: Black is checkmated)
        notifier.loadPgn('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#');
        expect(notifier.state.isCheckmate, true);
        expect(notifier.state.isGameOver, true);
        expect(notifier.state.gameOverMessage, 'Checkmate — You win!');
        expect(notifier.state.pgn, contains('[Result "1-0"]'));
        expect(notifier.state.gameReview, isNotNull);
        expect(
          notifier.state.gameReview!.white.estimatedElo,
          greaterThan(notifier.state.gameReview!.black.estimatedElo),
        );
        expect(
          notifier.state.gameReview!.white.accuracyPercent,
          greaterThan(notifier.state.gameReview!.black.accuracyPercent),
        );
      },
    );

    test(
      'loadFen with identical current FEN preserves existing PGN move history',
      () async {
        final engine = _FakeEngine(moveToReturn: 'e7e5');
        final notifier = _makeNotifier(engine);
        await notifier.setDifficulty(1200);

        await notifier.onUserMove(_afterE4Fen);
        expect(notifier.state.sanMoves, ['e4', 'e5']);
        expect(notifier.state.initialFen, _startFen);

        // Calling loadFen with the current board FEN should not wipe sanMoves
        // or set initialFen to the mid-game FEN.
        expect(notifier.loadFen(notifier.state.fen), true);
        expect(notifier.state.sanMoves, ['e4', 'e5']);
        expect(notifier.state.initialFen, _startFen);
        expect(notifier.state.pgn, contains('1. e4 e5 *'));
        expect(notifier.state.pgn, isNot(contains('[SetUp "1"]')));
      },
    );

    test(
      'stepBack and stepForward navigate history, and lockHistory controls whether past moves can be changed',
      () async {
        final engine = _FakeEngine(moveToReturn: 'e7e5');
        final notifier = _makeNotifier(engine);
        await notifier.setDifficulty(1200);

        await notifier.onUserMove(_afterE4Fen);
        expect(notifier.state.sanMoves, ['e4', 'e5']);
        expect(notifier.state.currentPly, 2);
        expect(notifier.state.isViewingHistory, false);

        // Step back 1 ply -> after 1. e4
        notifier.stepBack();
        expect(notifier.state.currentPly, 1);
        expect(notifier.state.isViewingHistory, true);
        expect(notifier.state.displayedFen, _afterE4Fen);

        // Step back 1 more ply -> start position (ply 0)
        notifier.stepBack();
        expect(notifier.state.currentPly, 0);
        expect(notifier.state.displayedFen, _startFen);

        // Step forward -> ply 1, then ply 2
        notifier.stepForward();
        expect(notifier.state.currentPly, 1);
        notifier.stepForward();
        expect(notifier.state.currentPly, 2);
        expect(notifier.state.isViewingHistory, false);

        // Step back to ply 0 with lockHistory == true (default): onUserMove is blocked
        notifier.stepBack();
        notifier.stepBack();
        expect(notifier.state.lockHistory, true);
        final afterD4Fen =
            'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1';
        await notifier.onUserMove(afterD4Fen);
        expect(notifier.state.sanMoves, ['e4', 'e5']);
        expect(notifier.state.currentPly, 0);

        // Turn lockHistory OFF: onUserMove from ply 0 replaces history with 1. d4 e5
        notifier.setLockHistory(false);
        await notifier.onUserMove(afterD4Fen);
        expect(notifier.state.isViewingHistory, false);
        expect(notifier.state.sanMoves, ['d4', 'e5']);
      },
    );

    test(
      'ChessBoardWidget.snapTo8Px rounds down to nearest multiple of 8px',
      () {
        expect(ChessBoardWidget.snapTo8Px(257.0), 256.0);
        expect(ChessBoardWidget.snapTo8Px(256.0), 256.0);
        expect(ChessBoardWidget.snapTo8Px(303.9), 296.0);
        expect(ChessBoardWidget.snapTo8Px(50.0, minSize: 96.0), 96.0);
      },
    );

    test(
      'TimeControl.parse and formatClockMs handle categories and tenths',
      () {
        final blitz = TimeControl.parse('180+2');
        expect(blitz.category, TimeCategory.blitz);
        expect(blitz.initialTimeMs, 180000);
        expect(blitz.incrementMs, 2000);

        final bullet = TimeControl.parse('60');
        expect(bullet.category, TimeCategory.bullet);

        final rapid = TimeControl.parse('600+5');
        expect(rapid.category, TimeCategory.rapid);

        // Standard M:SS above 20 seconds
        expect(TimeControl.formatClockMs(180000), '3:00');
        expect(TimeControl.formatClockMs(25000), '0:25');
        // Sub-20-second decisecond tenths (<= 200 deciseconds)
        expect(TimeControl.formatClockMs(19400), '0:19.4');
        expect(TimeControl.formatClockMs(5100), '0:05.1');
        expect(TimeControl.formatClockMs(0), '0:00');
        // Hours H:MM:SS
        expect(TimeControl.formatClockMs(3661000), '1:01:01');
      },
    );

    test('selectPly jumps directly to any ply in SAN move history', () async {
      final notifier = _makeNotifier(_FakeEngine());
      await notifier.onUserMove(_afterE4Fen);
      expect(notifier.state.sanMoves, ['e4', 'e5']);
      expect(notifier.state.currentPly, 2);

      notifier.selectPly(1);
      expect(notifier.state.currentPly, 1);
      expect(notifier.state.displayedFen, _afterE4Fen);

      notifier.selectPly(2);
      expect(notifier.state.currentPly, 2);
      expect(notifier.state.isViewingHistory, false);
    });

    test('timed clock countdown and timeout ends game', () async {
      final notifier = _makeNotifier(_FakeEngine());
      final tc = TimeControl.parse('60+1');
      notifier.setTimeControl(tc);
      expect(notifier.state.whiteTimeMs, 60000);
      expect(notifier.state.blackTimeMs, 60000);

      await notifier.onUserMove(_afterE4Fen);
      // White got +1000ms increment after moving
      expect(notifier.state.whiteTimeMs, 61000);

      // Tick 30 seconds off White's clock
      notifier.tickClock(30000);
      expect(notifier.state.whiteTimeMs, 31000);
      expect(notifier.state.isGameOver, false);

      // Tick remaining 31 seconds -> White flags
      notifier.tickClock(31000);
      expect(notifier.state.whiteTimeMs, 0);
      expect(notifier.state.timeoutWinner, 'black');
      expect(notifier.state.isGameOver, true);
      expect(notifier.state.gameOverMessage, contains('Time out'));
      notifier.dispose();
    });

    test(
      'setPlaySide configures orientation and human checkmate awards crowns',
      () async {
        final notifier = _makeNotifier(_FakeEngine());
        notifier.setPlaySide(PlaySide.black);
        expect(notifier.state.playSide, PlaySide.black);
        expect(notifier.state.boardFlipped, true);

        notifier.setPlaySide(PlaySide.white);
        expect(notifier.state.playSide, PlaySide.white);
        expect(notifier.state.boardFlipped, false);

        // Load a mate-in-1 position for White and play the winning move
        notifier.loadFen(
          'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
        );
        await notifier.onUserMove(
          'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4',
        );
        expect(notifier.state.isGameOver, true);
        // With antiBlunderEnabled=true (default), human earns 2 crowns
        expect(notifier.state.crownsForBot(notifier.state.personality.id), 2);
      },
    );

    group('opening book follower', () {
      // Italian Game: e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 (6 plies).
      final italian = kOpenings.firstWhere((o) => o.id == 'italian');

      String fenAfterUci(List<String> ucis) {
        final chess = chess_lib.Chess();
        for (final uci in ucis) {
          chess.move({
            'from': uci.substring(0, 2),
            'to': uci.substring(2, 4),
            if (uci.length > 4) 'promotion': uci[4],
          });
        }
        return chess.fen;
      }

      test(
        'setOpening starts a fresh game and the bot plays the book reply',
        () async {
          final engine = _FakeEngine(moveToReturn: 'a2a3'); // off-book move
          final notifier = _makeNotifier(engine);
          await notifier.setOpening(italian);
          expect(notifier.state.selectedOpening, italian);
          expect(notifier.state.fen, chess_lib.Chess().fen);

          // 1. e4 (user, human is White by default)
          await notifier.onUserMove(fenAfterUci(['e2e4']));
          expect(notifier.state.errorMessage, isNull);
          // Bot plays the book's 2nd ply (e7e5), not the engine's a2a3.
          expect(notifier.state.fen, fenAfterUci(['e2e4', 'e7e5']));
        },
      );

      test('onUserMove off-book is rejected and the board reverts', () async {
        final engine = _FakeEngine();
        final notifier = _makeNotifier(engine);
        await notifier.setOpening(italian);

        await notifier.onUserMove(fenAfterUci(['d2d4'])); // not e2e4
        expect(notifier.state.errorMessage, contains('Italian Game'));
        expect(notifier.state.fen, chess_lib.Chess().fen); // reverted
        expect(notifier.state.sanMoves, isEmpty);
      });

      test('enforcement stops once past the end of the stored line', () async {
        final engine = _FakeEngine(moveToReturn: 'g8f6'); // free-play move
        final notifier = _makeNotifier(engine);
        await notifier.setOpening(italian);

        // Play out the whole book as the user (White's plies: 0, 2, 4).
        // The bot auto-plays its own book replies in between via the
        // opening-book branch in _pickBotMove.
        for (var i = 0; i < italian.uciMoves.length; i += 2) {
          await notifier.onUserMove(
            fenAfterUci(italian.uciMoves.sublist(0, i + 1)),
          );
        }
        expect(notifier.state.errorMessage, isNull);
        expect(notifier.state.sanMoves.length, italian.uciMoves.length);

        // Past the book: free play resumes — any legal move is accepted
        // (d2d3, a quiet move not in the book) and the engine's move
        // (b1c3) is used for the bot's reply instead of book enforcement.
        final beforeFreePly = notifier.state.sanMoves.length;
        final freeFen = fenAfterUci([...italian.uciMoves, 'd2d3']);
        await notifier.onUserMove(freeFen);
        expect(notifier.state.errorMessage, isNull);
        expect(notifier.state.sanMoves.length, beforeFreePly + 2);
      });
    });

    group('plyWhiteCpHistory', () {
      test('starts with one entry (the seeded starting-position eval)', () {
        final notifier = _makeNotifier(_FakeEngine());
        expect(notifier.state.plyWhiteCpHistory, [20]);
      });

      test('grows by one White-perspective entry per ply played', () async {
        final engine = _OverrideEvalEngine(
          evals: [50, -30],
          moveToReturn: 'e7e5',
        );
        final notifier = _makeNotifier(engine);
        await notifier.onUserMove(_afterE4Fen);
        final history = notifier.state.plyWhiteCpHistory;
        expect(history.length, notifier.state.sanMoves.length + 1);
      });
    });
  });
}

class _OverrideEvalEngine extends ChessEngineRepository {
  final List<int> evals;
  final String moveToReturn;
  int _call = 0;

  _OverrideEvalEngine({required this.evals, required this.moveToReturn});

  @override
  Future<void> setBotElo(int elo) async {}

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async =>
      evals[(_call++).clamp(0, evals.length - 1)];

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async =>
      moveToReturn;

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async =>
      null;

  @override
  void dispose() {}
}
