// Pure domain-logic tests for the per-personality move-picking policies
// that aren't already covered by a dedicated policy (Aggressor ->
// ScholarsMateHunterPolicy, Pawn Pusher -> PawnPusherPolicy). No Flutter,
// no engine — candidates are hand-fabricated EngineMoveCandidate lists
// standing in for what a MultiPV search would return. See
// docs/features/done/bot_play_styles.md for the scoring formulas under test.
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/bot_move_strategy.dart';
import 'package:chess_teacher/features/game/domain/entities/bot_style_policy.dart';
import 'package:chess_teacher/features/game/domain/entities/engine_move_candidate.dart';

void main() {
  group('TricksterStylePolicy', () {
    final policy = TricksterStylePolicy();

    test('prefers a forking move over a quiet move', () {
      // White knight a3 -> c4 forks the rook on b6 and queen on d6.
      const fen = '4k3/8/1r1q4/8/8/N7/8/4K3 w - - 0 1';
      final candidates = [
        const EngineMoveCandidate(uci: 'e1d1', scoreCp: 0), // quiet
        const EngineMoveCandidate(uci: 'a3c4', scoreCp: 0), // fork
      ];
      expect(policy.pickMove(fen, candidates), 'a3c4');
    });

    test('prefers a forking sacrifice over the engine\'s top pawn-grab', () {
      // White: king e1, knight a3, rook h1. Black: king e8, rook b6,
      // queen d6, pawn h6. h1xh6 is the engine's top (plain) choice; a3-c4
      // forks the rook and queen instead, giving up that free pawn.
      const fen = '4k3/8/1r1q3p/8/8/N7/8/4K2R w - - 0 1';
      final candidates = [
        const EngineMoveCandidate(uci: 'h1h6', scoreCp: 0), // top: grab pawn
        const EngineMoveCandidate(uci: 'a3c4', scoreCp: 0), // fork + sacrifice
      ];
      expect(policy.pickMove(fen, candidates), 'a3c4');
    });

    test('a check-giving move scores above a quiet, non-forking move', () {
      const fen = '4k3/8/8/8/8/8/8/Q3K3 w - - 0 1';
      final candidates = [
        const EngineMoveCandidate(uci: 'e1d1', scoreCp: 0), // quiet
        const EngineMoveCandidate(uci: 'a1a8', scoreCp: 0), // check
      ];
      expect(policy.pickMove(fen, candidates), 'a1a8');
    });

    test('returns null when given no candidates', () {
      const fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
      expect(policy.pickMove(fen, const []), isNull);
    });
  });

  group('DefenderStylePolicy', () {
    final policy = DefenderStylePolicy();

    test(
      'avoids hanging the queen even though the hanging square is otherwise unremarkable',
      () {
        // White queen h1 vs black queen e5 on the same rank: h1-h5 hangs the
        // queen for nothing; h1-h4 is safe. King on b1 (not e1) so it isn't
        // sitting on the e5 queen's file.
        const fen = '4k3/8/8/4q3/8/8/8/1K5Q w - - 0 1';
        final candidates = [
          const EngineMoveCandidate(uci: 'h1h5', scoreCp: 0), // hangs the queen
          const EngineMoveCandidate(uci: 'h1h4', scoreCp: 0), // safe
        ];
        expect(policy.pickMove(fen, candidates), 'h1h4');
      },
    );

    test('prefers trading down a capture while material is even-or-ahead', () {
      // White queen d1 vs a lone black pawn on d4; white (9) is already
      // ahead of black (1), so capturing it is a trade-down, not a risk.
      const fen = '4k3/8/8/8/3p4/8/8/3QK3 w - - 0 1';
      final candidates = [
        const EngineMoveCandidate(uci: 'd1d4', scoreCp: 0), // captures pawn
        const EngineMoveCandidate(uci: 'd1a4', scoreCp: 0), // quiet
      ];
      expect(policy.pickMove(fen, candidates), 'd1d4');
    });

    test('prefers castling over an equivalent quiet king move', () {
      const fen = '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1';
      final candidates = [
        const EngineMoveCandidate(uci: 'e1g1', scoreCp: 0), // castle
        const EngineMoveCandidate(uci: 'e1d1', scoreCp: 0), // quiet
      ];
      expect(policy.pickMove(fen, candidates), 'e1g1');
    });

    test('stays inside the tight 50cp tolerance band even when the only '
        'in-band candidate hangs a piece', () {
      // h1h5 (hangs the queen) is the best-eval candidate; h1h4 (safe) is
      // 200cp worse — well outside Defender's 50cp band — so it's never
      // considered at all, and the policy is forced to pick the only
      // in-band move despite its terrible style score.
      const fen = '4k3/8/8/4q3/8/8/8/1K5Q w - - 0 1';
      final candidates = [
        const EngineMoveCandidate(uci: 'h1h5', scoreCp: 0), // best, hangs
        const EngineMoveCandidate(uci: 'h1h4', scoreCp: -200), // safe, far off
      ];
      expect(policy.pickMove(fen, candidates), 'h1h5');
    });

    test('returns null when given no candidates', () {
      const fen = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
      expect(policy.pickMove(fen, const []), isNull);
    });
  });

  // Registry lookup moved to bot_move_strategy.dart as part of unifying
  // every personality's move selection under one BotMoveStrategy interface
  // — see docs/features/done/refactor_03_bot_strategy_pattern.md. Kept here
  // since it's still exercising these two classes' identity.
  group('strategyForPersonalityId', () {
    test(
      'returns the right strategy type for every registered personality',
      () {
        expect(strategyForPersonalityId('aggressor'), isA<AggressorStrategy>());
        expect(
          strategyForPersonalityId('pawn_pusher'),
          isA<PawnPusherStrategy>(),
        );
        expect(
          strategyForPersonalityId('trickster'),
          isA<TricksterStylePolicy>(),
        );
        expect(
          strategyForPersonalityId('defender'),
          isA<DefenderStylePolicy>(),
        );
      },
    );

    test('falls back to DefaultBotMoveStrategy for personalities with no '
        'dedicated strategy', () {
      expect(strategyForPersonalityId('martin'), isA<DefaultBotMoveStrategy>());
      expect(
        strategyForPersonalityId('strategist'),
        isA<DefaultBotMoveStrategy>(),
      );
      expect(
        strategyForPersonalityId('crusher'),
        isA<DefaultBotMoveStrategy>(),
      );
    });
  });
}
