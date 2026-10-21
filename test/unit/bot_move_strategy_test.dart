// Tests for the engine-call wiring each BotMoveStrategy does — the actual
// move-picking logic (ScholarsMateHunterPolicy, PawnPusherPolicy) already
// has its own dedicated test coverage; these tests check that each
// strategy asks the engine the right question (right multiPv/mateLimit),
// short-circuits correctly on immediate/forced mate, records eval for the
// game-review cache, and falls back correctly. Previously only reachable
// indirectly through GameNotifier — net-new isolated coverage added as
// part of docs/features/done/refactor_03_bot_strategy_pattern.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/bot_move_strategy.dart';
import 'package:chess_teacher/features/game/domain/repositories/chess_engine_repository.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Records every getTopMoves call's params and returns configurable
/// candidates/bestMove. Throws if a strategy calls the engine when it
/// shouldn't have (e.g. after already finding a mate-in-1 in pure Dart).
class _RecordingEngine extends ChessEngineRepository {
  List<EngineMoveCandidate> candidatesToReturn = const [];
  String bestMoveToReturn = '(none)';
  bool failIfCalled = false;

  int? lastMultiPv;
  int? lastMateLimit;
  int getTopMovesCallCount = 0;
  int getBestMoveCallCount = 0;

  @override
  Future<void> setBotElo(int elo) async {}

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async => 0;

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async {
    if (failIfCalled) fail('getBestMove should not have been called');
    getBestMoveCallCount++;
    return bestMoveToReturn;
  }

  @override
  Future<List<EngineMoveCandidate>> getTopMoves(
    String fen, {
    int movetimeMs = 600,
    int multiPv = 6,
    int? mateLimit,
  }) async {
    if (failIfCalled) fail('getTopMoves should not have been called');
    getTopMovesCallCount++;
    lastMultiPv = multiPv;
    lastMateLimit = mateLimit;
    return candidatesToReturn;
  }

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async =>
      null;

  @override
  void dispose() {}
}

void main() {
  group('AggressorStrategy', () {
    test('plays an immediate mate-in-1 without touching the engine', () async {
      // Classic Scholar's Mate position: Qh5xf7# is mate.
      const fen =
          'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';
      final engine = _RecordingEngine()..failIfCalled = true;
      final ctx = BotMoveContext(
        fen: fen,
        elo: 1400,
        engine: engine,
        positionCounts: const {},
      );
      final move = await AggressorStrategy().selectMove(ctx);
      expect(move, isNotNull);
      expect(engine.getTopMovesCallCount, 0);
    });

    test('queries the engine with multiPv 10 and mateLimit 8, and records '
        "the top candidate's eval", () async {
      final engine = _RecordingEngine()
        ..candidatesToReturn = const [
          EngineMoveCandidate(uci: 'e2e4', scoreCp: 35),
        ];
      String? recordedFen;
      int? recordedCp;
      final ctx = BotMoveContext(
        fen: _startFen,
        elo: 1400,
        engine: engine,
        positionCounts: const {},
        recordEval: (f, cp) {
          recordedFen = f;
          recordedCp = cp;
        },
      );
      final move = await AggressorStrategy().selectMove(ctx);
      expect(engine.getTopMovesCallCount, 1);
      expect(engine.lastMultiPv, 10);
      expect(engine.lastMateLimit, 8);
      expect(recordedFen, _startFen);
      expect(recordedCp, 35);
      expect(move, isNotNull);
    });

    test('returns null when the engine gives no usable candidates', () async {
      // Past move 6, so the Scholar's Mate opening book (which doesn't
      // need engine candidates for its scripted first moves) no longer
      // applies — a quiet king-only endgame with no mate available.
      const fen = '8/8/4k3/8/8/4K3/8/8 w - - 0 20';
      final engine = _RecordingEngine()..candidatesToReturn = const [];
      final ctx = BotMoveContext(
        fen: fen,
        elo: 1400,
        engine: engine,
        positionCounts: const {},
      );
      final move = await AggressorStrategy().selectMove(ctx);
      expect(move, isNull);
    });
  });

  group('PawnPusherStrategy', () {
    test('queries the engine with multiPv 10 and no mateLimit', () async {
      final engine = _RecordingEngine()
        ..candidatesToReturn = const [
          EngineMoveCandidate(uci: 'e2e4', scoreCp: 20),
        ];
      final ctx = BotMoveContext(
        fen: _startFen,
        elo: 1300,
        engine: engine,
        positionCounts: const {},
      );
      await PawnPusherStrategy().selectMove(ctx);
      expect(engine.getTopMovesCallCount, 1);
      expect(engine.lastMultiPv, 10);
      expect(engine.lastMateLimit, isNull);
    });

    test('plays an immediate mate-in-1 without touching the engine', () async {
      // Classic Scholar's Mate position: Qh5xf7# is mate.
      const fen =
          'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';
      final engine = _RecordingEngine()..failIfCalled = true;
      final ctx = BotMoveContext(
        fen: fen,
        elo: 1300,
        engine: engine,
        positionCounts: const {},
      );
      final move = await PawnPusherStrategy().selectMove(ctx);
      expect(move, isNotNull);
      expect(engine.getTopMovesCallCount, 0);
    });
  });

  group('DefaultBotMoveStrategy', () {
    test(
      "returns the engine's best move directly when it doesn't cause a draw",
      () async {
        final engine = _RecordingEngine()..bestMoveToReturn = 'e2e4';
        final ctx = BotMoveContext(
          fen: _startFen,
          elo: 1200,
          engine: engine,
          positionCounts: const {},
        );
        final move = await DefaultBotMoveStrategy().selectMove(ctx);
        expect(move, 'e2e4');
        expect(engine.getTopMovesCallCount, 0);
      },
    );

    test('falls back to a wider candidate search when the best move would '
        'repeat a position 3 times', () async {
      // positionCounts already shows the position *after* e2e4 occurring
      // twice; a 3rd occurrence (what playing e2e4 again would cause)
      // triggers wouldRepeatPosition.
      final afterE4 =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'
              .split(RegExp(r'\s+'))
              .take(4)
              .join(' ');
      final engine = _RecordingEngine()
        ..bestMoveToReturn = 'e2e4'
        ..candidatesToReturn = const [
          EngineMoveCandidate(uci: 'd2d4', scoreCp: 25),
        ];
      final ctx = BotMoveContext(
        fen: _startFen,
        elo: 1200,
        engine: engine,
        positionCounts: {afterE4: 2},
      );
      final move = await DefaultBotMoveStrategy().selectMove(ctx);
      expect(engine.getTopMovesCallCount, 1);
      expect(move, 'd2d4');
    });
  });

  group('strategyForPersonalityId integration', () {
    test('an unregistered personality id resolves to a working '
        'DefaultBotMoveStrategy', () async {
      final engine = _RecordingEngine()..bestMoveToReturn = 'g1f3';
      final ctx = BotMoveContext(
        fen: _startFen,
        elo: 1200,
        engine: engine,
        positionCounts: const {},
      );
      final strategy = strategyForPersonalityId('martin');
      final move = await strategy.selectMove(ctx);
      expect(move, 'g1f3');
    });
  });
}
