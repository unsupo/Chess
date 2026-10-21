// Tests for the Chain of Responsibility (opening book -> weak play ->
// personality strategy) and the mate-safety Decorator that wraps it — see
// docs/features/done/refactor_04_bot_move_pipeline.md. These were previously
// only reachable indirectly through GameNotifier, with no isolated
// coverage of the ordering or of the weak-play branches specifically
// (GameNotifier's own Random field couldn't be seeded from outside it).
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/bot_move_pipeline.dart';
import 'package:chess_teacher/features/game/domain/entities/bot_move_strategy.dart';
import 'package:chess_teacher/features/game/domain/entities/chess_move_analysis.dart'
    show applyUciToFen;
import 'package:chess_teacher/features/game/domain/entities/chess_opening.dart';
import 'package:chess_teacher/features/game/domain/repositories/chess_engine_repository.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
// Classic Scholar's Mate position: Qh5xf7# is mate.
const _mateIn1Fen =
    'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';

/// A `Random` whose `nextDouble`/`nextInt`/`nextBool` are fixed, so a test
/// can force a specific branch of a chance roll deterministically instead
/// of depending on a seeded PRNG's implementation-specific sequence.
class _FixedRandom implements Random {
  final double doubleValue;
  final int intValue;
  const _FixedRandom({this.doubleValue = 0.0, this.intValue = 0});

  @override
  int nextInt(int max) => intValue.clamp(0, max - 1);
  @override
  double nextDouble() => doubleValue;
  @override
  bool nextBool() => false;
}

class _FakeEngine extends ChessEngineRepository {
  int Function(String fen)? evalFn;
  Map<String, int>? mateDistanceByFen;
  String bestMoveToReturn = '(none)';
  bool failIfGetMateDistanceCalled = false;

  @override
  Future<void> setBotElo(int elo) async {}

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) async =>
      evalFn?.call(fen) ?? 0;

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 500}) async =>
      bestMoveToReturn;

  @override
  Future<List<EngineMoveCandidate>> getTopMoves(
    String fen, {
    int movetimeMs = 600,
    int multiPv = 6,
    int? mateLimit,
  }) async => const [];

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) async {
    if (failIfGetMateDistanceCalled) {
      fail('getMateDistance should not have been called');
    }
    return mateDistanceByFen?[fen];
  }

  @override
  void dispose() {}
}

BotMoveContext _ctx({
  String fen = _startFen,
  int elo = 1400,
  ChessEngineRepository? engine,
  Map<String, int> positionCounts = const {},
  String personalityId = '',
  int ply = 0,
  ChessOpening? selectedOpening,
  bool mateSafetyEnabled = false,
  int mateSafetyN = 3,
}) => BotMoveContext(
  fen: fen,
  elo: elo,
  engine: engine ?? _FakeEngine(),
  positionCounts: positionCounts,
  personalityId: personalityId,
  ply: ply,
  selectedOpening: selectedOpening,
  mateSafetyEnabled: mateSafetyEnabled,
  mateSafetyN: mateSafetyN,
);

void main() {
  group('OpeningBookStep', () {
    const opening = ChessOpening(
      id: 'test',
      name: 'Test Opening',
      uciMoves: ['e2e4', 'e7e5'],
    );

    test(
      'plays the scripted move while still inside the stored line',
      () async {
        final ctx = _ctx(selectedOpening: opening, ply: 0);
        expect(await OpeningBookStep().tryHandle(ctx), 'e2e4');
      },
    );

    test('returns null once past the end of the stored line', () async {
      final ctx = _ctx(selectedOpening: opening, ply: 2);
      expect(await OpeningBookStep().tryHandle(ctx), isNull);
    });

    test('returns null when no opening is selected', () async {
      final ctx = _ctx(selectedOpening: null);
      expect(await OpeningBookStep().tryHandle(ctx), isNull);
    });
  });

  group('WeakPlayStep', () {
    test('defers to the next step at full engine strength', () async {
      final ctx = _ctx(elo: 1400);
      final move = await WeakPlayStep(
        const _FixedRandom(doubleValue: 0.0),
      ).tryHandle(ctx);
      expect(move, isNull);
    });

    test('worst-move band: picks whichever sampled move leaves the bot '
        'worst off', () async {
      // Lone kings: a1's only legal moves are a2, b1, b2. Rig the fake
      // engine so b2 is clearly the worst continuation (highest eval for
      // the opponent to move next).
      const fen = 'k7/8/8/8/8/8/8/K7 w - - 0 1';
      final worstFen = applyUciToFen(fen, 'a1b2');
      final engine = _FakeEngine()..evalFn = (f) => f == worstFen ? 500 : 0;
      final ctx = _ctx(fen: fen, elo: 0, engine: engine);
      final move = await WeakPlayStep(
        const _FixedRandom(doubleValue: 0.0),
      ).tryHandle(ctx);
      expect(move, 'a1b2');
    });

    test(
      'blunder band: picks a uniformly-random legal, non-drawing move',
      () async {
        final ctx = _ctx(elo: 250, positionCounts: const {});
        final move = await WeakPlayStep(
          const _FixedRandom(doubleValue: 0.0, intValue: 0),
        ).tryHandle(ctx);
        expect(move, isNotNull);
        expect(move, isNot('(none)'));
      },
    );

    test('blunder band: Pawn Pusher still prefers a pawn move even while '
        'blundering', () async {
      final ctx = _ctx(
        elo: 250,
        personalityId: 'pawn_pusher',
        positionCounts: const {},
      );
      final move = await WeakPlayStep(
        const _FixedRandom(doubleValue: 0.0, intValue: 0),
      ).tryHandle(ctx);
      // Every legal move from the start position starting with a pawn's
      // own square (a2-h2) or a knight/pawn double push — assert it's one
      // of White's twenty legal first moves AND specifically a pawn push
      // (uci 'from' rank 2, since all starting pawns sit on rank 2).
      expect(move, isNotNull);
      expect(move![1], '2');
    });
  });

  group('PersonalityStrategyStep', () {
    test('resolves a registered personality without touching the default '
        'strategy', () async {
      final ctx = _ctx(fen: _mateIn1Fen, personalityId: 'aggressor');
      final move = await PersonalityStrategyStep().tryHandle(ctx);
      expect(move, isNotNull);
    });

    test('falls back to DefaultBotMoveStrategy for an unregistered '
        'personality', () async {
      final engine = _FakeEngine()..bestMoveToReturn = 'g1f3';
      final ctx = _ctx(personalityId: 'martin', engine: engine);
      final move = await PersonalityStrategyStep().tryHandle(ctx);
      expect(move, 'g1f3');
    });
  });

  group('BotMovePipeline', () {
    test('returns the first step\'s non-null move without running later '
        'steps', () async {
      final pipeline = BotMovePipeline([
        _StubStep(null),
        _StubStep('e2e4'),
        _StubStep('should not be reached'),
      ]);
      final move = await pipeline.selectMove(_ctx());
      expect(move, 'e2e4');
    });

    test('kDefaultBotMovePipeline: opening book beats weak play even at '
        'the difficulty floor', () async {
      const opening = ChessOpening(
        id: 'test',
        name: 'Test Opening',
        uciMoves: ['e2e4'],
      );
      // elo 0 would make WeakPlayStep pick the worst sampled move 100% of
      // the time if it ran — the opening book must win first.
      final ctx = _ctx(selectedOpening: opening, ply: 0, elo: 0);
      final move = await kDefaultBotMovePipeline.selectMove(ctx);
      expect(move, 'e2e4');
    });
  });

  group('MateSafetyDecorator', () {
    test('mate safety off: returns the inner move without consulting the '
        'engine at all', () async {
      final engine = _FakeEngine()..failIfGetMateDistanceCalled = true;
      final ctx = _ctx(engine: engine, mateSafetyEnabled: false);
      final decorator = MateSafetyDecorator(
        BotMovePipeline([_StubStep('e2e4')]),
      );
      final move = await decorator.selectMove(ctx);
      expect(move, 'e2e4');
    });

    test('skips the mate-distance check for a "(none)" move', () async {
      final engine = _FakeEngine()..failIfGetMateDistanceCalled = true;
      final ctx = _ctx(engine: engine, mateSafetyEnabled: true);
      final decorator = MateSafetyDecorator(
        BotMovePipeline([_StubStep('(none)')]),
      );
      final move = await decorator.selectMove(ctx);
      expect(move, '(none)');
    });

    test('mate safety on, chosen move is safe: returns it unchanged', () async {
      final afterE4 = applyUciToFen(_startFen, 'e2e4');
      final engine = _FakeEngine()
        ..mateDistanceByFen =
            {afterE4: 10} // well outside mateSafetyN
        ..bestMoveToReturn = 'g1f3';
      final ctx = _ctx(engine: engine, mateSafetyEnabled: true, mateSafetyN: 3);
      final decorator = MateSafetyDecorator(
        BotMovePipeline([_StubStep('e2e4')]),
      );
      final move = await decorator.selectMove(ctx);
      expect(move, 'e2e4');
    });

    test('mate safety on, chosen move hands over a forced mate: substitutes '
        "the engine's own best move", () async {
      final afterE4 = applyUciToFen(_startFen, 'e2e4');
      final engine = _FakeEngine()
        ..mateDistanceByFen =
            {afterE4: 2} // within mateSafetyN
        ..bestMoveToReturn = 'g1f3';
      final ctx = _ctx(engine: engine, mateSafetyEnabled: true, mateSafetyN: 3);
      final decorator = MateSafetyDecorator(
        BotMovePipeline([_StubStep('e2e4')]),
      );
      final move = await decorator.selectMove(ctx);
      expect(move, 'g1f3');
    });
  });
}

class _StubStep implements BotMoveStep {
  final String? move;
  const _StubStep(this.move);
  @override
  Future<String?> tryHandle(BotMoveContext ctx) async => move;
}
