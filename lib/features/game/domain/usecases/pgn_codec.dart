// PGN serialization/parsing and FEN-diff-to-move lookup — see
// docs/features/refactor_05_game_notifier_facade.md. Previously split
// across `GameState.pgn` (presentation) and several private statics on
// `GameNotifier` (presentation): `_parsePgn`, `_findSanMove`,
// `_findUciMove`, `_applyUciWithSan`.
//
// `toPgn` takes primitive fields rather than the whole `GameState` the
// original refactor sketch proposed — `GameState` is a presentation class
// (see architecture_backend_frontend_boundary.md's MVC mapping), and a
// domain class depending on one would be a backward dependency. Passing
// only the strings/bools/ints this needs keeps `PgnCodec` as pure domain
// logic, consistent with `ScholarsMateHunterPolicy`/`PawnPusherPolicy` in
// this same layer.
import 'package:chess/chess.dart' as chess_lib;

class PgnCodec {
  const PgnCodec._();

  /// Full PGN string including standard tag headers and move list.
  /// [isDraw] and [isCheckmate]-equivalent detection are recomputed here
  /// (via a private replay, mirroring the chess-state-already-replayed
  /// check every other `GameState` getter does independently) rather than
  /// taking `GameState.isDraw` directly, so this stays a pure function of
  /// primitives.
  static String toPgn({
    required String initialFen,
    required String fen,
    required List<String> sanMoves,
    required String? timeoutWinner,
    required bool isDraw,
    required bool boardFlipped,
    required String personalityName,
    required int botElo,
    required bool isTimedControl,
    required String timeControlKey,
  }) {
    final chess = _replayChess(initialFen, sanMoves, fen);
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

    final whiteName = boardFlipped ? '$personalityName ($botElo)' : 'You';
    final blackName = boardFlipped ? 'You' : '$personalityName ($botElo)';

    final headers = <String>[
      '[Event "Anti-Blunder Chess"]',
      '[Site "Local"]',
      '[White "$whiteName"]',
      '[Black "$blackName"]',
      '[Result "$result"]',
      if (isTimedControl) '[TimeControl "$timeControlKey"]',
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

  /// Replays [sanMoves] from [initialFen], falling back to [fallbackFen] if
  /// the replay can't proceed (invalid `initialFen`, or a move in
  /// `sanMoves` no longer applies) or ends up somewhere other than
  /// [fallbackFen] — same fallback shape as every other independent replay
  /// in `GameState` (`positionCounts`, `plyWhiteCpHistory`, ...).
  static chess_lib.Chess _replayChess(
    String initialFen,
    List<String> sanMoves,
    String fallbackFen,
  ) {
    final chess = chess_lib.Chess();
    if (chess_lib.Chess.validate_fen(initialFen)['valid'] != true ||
        !chess.load(initialFen)) {
      if (chess_lib.Chess.validate_fen(fallbackFen)['valid'] == true) {
        chess.load(fallbackFen);
      }
      return chess;
    }
    for (final san in sanMoves) {
      if (!chess.move(san)) {
        if (chess_lib.Chess.validate_fen(fallbackFen)['valid'] == true) {
          chess.load(fallbackFen);
        }
        return chess;
      }
    }
    if (chess.fen != fallbackFen &&
        chess_lib.Chess.validate_fen(fallbackFen)['valid'] == true) {
      chess.load(fallbackFen);
    }
    return chess;
  }

  /// Finds the legal move from [fromFen] to [toFen], returning both its SAN
  /// and UCI form from one shared board traversal — replaces the separate
  /// `_findSanMove`/`_findUciMove`, which independently replayed the same
  /// legal-move loop (see refactor_02_shared_chess_helpers.md).
  ///
  /// `uci` is only ever non-null on an *exact* full-FEN match (mirroring
  /// `_findUciMove`'s old strictness, used for opening-book UCI
  /// comparison); `san` additionally falls back to a board-only match
  /// (ignoring halfmove clock / en-passant-file differences, mirroring
  /// `_findSanMove`'s old leniency, used for recording SAN history). A
  /// single merged fallback would have silently loosened the opening-book
  /// check, so the two keep their original strictness even though they now
  /// share one traversal.
  static ({String san, String? uci})? findMove(String fromFen, String toFen) {
    final chess = chess_lib.Chess()..load(fromFen);
    final moves = chess.generate_moves();
    String? boardMatchSan;
    final toBoardPart = toFen.split(RegExp(r'\s+')).take(4).join(' ');
    for (final move in moves) {
      final san = chess.move_to_san(move);
      final from = chess_lib.Chess.algebraic(move.from);
      final to = chess_lib.Chess.algebraic(move.to);
      final promo = move.promotion != null ? move.promotion!.name : '';
      final uci = '$from$to$promo';
      chess.make_move(move);
      final resultingFen = chess.fen;
      chess.undo_move();
      if (resultingFen == toFen) {
        return (san: san, uci: uci);
      }
      if (boardMatchSan == null &&
          resultingFen.split(RegExp(r'\s+')).take(4).join(' ') == toBoardPart) {
        boardMatchSan = san;
      }
    }
    if (boardMatchSan != null) return (san: boardMatchSan, uci: null);
    return null;
  }

  /// Applies a UCI move string to a FEN and returns the resulting FEN and SAN.
  static (String, String?) applyUciWithSan(String fen, String uci) {
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

  /// Parses a PGN string (with or without headers) and returns the parsed
  /// game, or `null` if the PGN cannot be parsed or contains illegal moves.
  static ({
    String initialFen,
    String finalFen,
    List<String> sanMoves,
    String? lastFrom,
    String? lastTo,
  })?
  parse(String pgn) {
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

    return (
      initialFen: initialFen,
      finalFen: chess.fen,
      sanMoves: sanMoves,
      lastFrom: lastFrom,
      lastTo: lastTo,
    );
  }
}
