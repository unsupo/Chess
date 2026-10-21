// Isolated coverage for PgnCodec — see
// docs/features/done/refactor_05_game_notifier_facade.md. Previously this
// logic (toPgn's body, _findSanMove/_findUciMove, _applyUciWithSan,
// _parsePgn) was only reachable indirectly through GameNotifier/GameState;
// game_notifier_test.dart's existing pgn/loadPgn assertions cover the
// end-to-end wiring and are unchanged by this refactor, so these tests
// focus on PgnCodec's own branches directly instead of duplicating those.
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_teacher/features/game/domain/entities/chess_move_analysis.dart'
    show applyUciToFen;
import 'package:chess_teacher/features/game/domain/usecases/pgn_codec.dart';
import 'package:chess/chess.dart' as chess_lib;

const _startFen = chess_lib.Chess.DEFAULT_POSITION;

void main() {
  group('PgnCodec.toPgn', () {
    test('an ongoing game gets a "*" result and no SetUp/TimeControl '
        'headers', () {
      final pgn = PgnCodec.toPgn(
        initialFen: _startFen,
        fen: applyUciToFen(applyUciToFen(_startFen, 'e2e4'), 'e7e5'),
        sanMoves: const ['e4', 'e5'],
        timeoutWinner: null,
        isDraw: false,
        boardFlipped: false,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: false,
        timeControlKey: 'none',
      );
      expect(pgn, contains('[White "You"]'));
      expect(pgn, contains('[Black "Martin (900)"]'));
      expect(pgn, contains('[Result "*"]'));
      expect(pgn, contains('1. e4 e5 *'));
      expect(pgn, isNot(contains('[SetUp')));
      expect(pgn, isNot(contains('[TimeControl')));
    });

    test('boardFlipped swaps which side is "You" in the headers', () {
      final pgn = PgnCodec.toPgn(
        initialFen: _startFen,
        fen: _startFen,
        sanMoves: const [],
        timeoutWinner: null,
        isDraw: false,
        boardFlipped: true,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: false,
        timeControlKey: 'none',
      );
      expect(pgn, contains('[White "Martin (900)"]'));
      expect(pgn, contains('[Black "You"]'));
    });

    test('checkmate on the board overrides the result ("Fool\'s Mate")', () {
      const moves = ['f3', 'e5', 'g4', 'Qh4#'];
      final chess = chess_lib.Chess()..load(_startFen);
      for (final san in moves) {
        chess.move(san);
      }
      final pgn = PgnCodec.toPgn(
        initialFen: _startFen,
        fen: chess.fen, // must match the replay, same as GameState.fen would
        sanMoves: moves,
        timeoutWinner: null,
        isDraw: false,
        boardFlipped: false,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: false,
        timeControlKey: 'none',
      );
      expect(pgn, contains('[Result "0-1"]'));
      expect(pgn, contains('1. f3 e5 2. g4 Qh4# 0-1'));
    });

    test('a timeout result takes priority over isDraw', () {
      final pgn = PgnCodec.toPgn(
        initialFen: _startFen,
        fen: _startFen,
        sanMoves: const [],
        timeoutWinner: 'white',
        isDraw: true,
        boardFlipped: false,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: false,
        timeControlKey: 'none',
      );
      expect(pgn, contains('[Result "1-0"]'));
    });

    test('isDraw (with no timeout/checkmate) produces a draw result', () {
      final pgn = PgnCodec.toPgn(
        initialFen: _startFen,
        fen: _startFen,
        sanMoves: const [],
        timeoutWinner: null,
        isDraw: true,
        boardFlipped: false,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: false,
        timeControlKey: 'none',
      );
      expect(pgn, contains('[Result "1/2-1/2"]'));
    });

    test('a non-default initialFen adds SetUp/FEN headers', () {
      final customFen = applyUciToFen(_startFen, 'e2e4');
      final pgn = PgnCodec.toPgn(
        initialFen: customFen,
        fen: customFen,
        sanMoves: const [],
        timeoutWinner: null,
        isDraw: false,
        boardFlipped: false,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: false,
        timeControlKey: 'none',
      );
      expect(pgn, contains('[SetUp "1"]'));
      expect(pgn, contains('[FEN "$customFen"]'));
    });

    test('a timed game adds a TimeControl header', () {
      final pgn = PgnCodec.toPgn(
        initialFen: _startFen,
        fen: _startFen,
        sanMoves: const [],
        timeoutWinner: null,
        isDraw: false,
        boardFlipped: false,
        personalityName: 'Martin',
        botElo: 900,
        isTimedControl: true,
        timeControlKey: '180|2',
      );
      expect(pgn, contains('[TimeControl "180|2"]'));
    });
  });

  group('PgnCodec.findMove', () {
    test('an exact FEN match returns both san and uci', () {
      final toFen = applyUciToFen(_startFen, 'e2e4');
      final move = PgnCodec.findMove(_startFen, toFen);
      expect(move, isNotNull);
      expect(move!.san, 'e4');
      expect(move.uci, 'e2e4');
    });

    test('no legal move reaches the target position at all: null', () {
      const unreachableFen = '8/8/8/8/8/8/8/K6k w - - 0 1';
      expect(PgnCodec.findMove(_startFen, unreachableFen), isNull);
    });

    test('a board-only match (full FEN differs only outside the first 4 '
        'fields) returns san but leaves uci null', () {
      final exactFen = applyUciToFen(_startFen, 'e2e4');
      final fields = exactFen.split(' ');
      fields[4] = '99'; // halfmove clock, deliberately wrong
      final boardOnlyFen = fields.join(' ');

      final move = PgnCodec.findMove(_startFen, boardOnlyFen);
      expect(move, isNotNull);
      expect(move!.san, 'e4');
      expect(move.uci, isNull);
    });
  });

  group('PgnCodec.applyUciWithSan', () {
    test('a legal move returns the resulting FEN and its SAN', () {
      final (fen, san) = PgnCodec.applyUciWithSan(_startFen, 'e2e4');
      expect(san, 'e4');
      expect(fen, applyUciToFen(_startFen, 'e2e4'));
    });

    test('an illegal move leaves the FEN unchanged and returns a null SAN', () {
      final (fen, san) = PgnCodec.applyUciWithSan(_startFen, 'e2e5');
      expect(san, isNull);
      expect(fen, _startFen);
    });

    test('a promotion move produces a promoted piece on the board', () {
      const fen = '8/4P3/8/8/8/8/8/k6K w - - 0 1';
      final (resultFen, san) = PgnCodec.applyUciWithSan(fen, 'e7e8q');
      expect(san, isNotNull);
      expect(resultFen.split(' ').first, contains('Q'));
    });
  });

  group('PgnCodec.parse', () {
    test('a full PGN with headers and moves parses correctly', () {
      const pgn = '''
[Event "Anti-Blunder Chess"]
[Site "Local"]
[White "You"]
[Black "Martin (900)"]
[Result "*"]

1. e4 e5 2. Nf3 *
''';
      final parsed = PgnCodec.parse(pgn);
      expect(parsed, isNotNull);
      expect(parsed!.initialFen, _startFen);
      expect(parsed.sanMoves, ['e4', 'e5', 'Nf3']);
      expect(parsed.lastFrom, 'g1');
      expect(parsed.lastTo, 'f3');
    });

    test('a bare move list with no headers still parses', () {
      final parsed = PgnCodec.parse('1. e4 e5');
      expect(parsed, isNotNull);
      expect(parsed!.initialFen, _startFen);
      expect(parsed.sanMoves, ['e4', 'e5']);
    });

    test('a FEN header sets a custom initial position', () {
      final customFen = applyUciToFen(_startFen, 'e2e4');
      final pgn = '[FEN "$customFen"]\n\n1. e5 *';
      final parsed = PgnCodec.parse(pgn);
      expect(parsed, isNotNull);
      expect(parsed!.initialFen, customFen);
      expect(parsed.sanMoves, ['e5']);
    });

    test('empty input returns null', () {
      expect(PgnCodec.parse(''), isNull);
      expect(PgnCodec.parse('   '), isNull);
    });

    test('a token that matches no legal move returns null', () {
      expect(PgnCodec.parse('1. e4 Zz9'), isNull);
    });
  });
}
