import 'dart:async';
import 'package:stockfish/stockfish.dart';
import '../../domain/repositories/chess_engine_repository.dart';

class ChessEngineRepositoryImpl implements ChessEngineRepository {
  late final Stockfish _engine;
  StreamSubscription<void>? _stdoutSub;

  Completer<int>? _evalCompleter;
  Completer<String>? _moveCompleter;
  Completer<void>? _syncCompleter;
  int? _latestScore;
  // Signed mate distance from the last `score mate N` line (positive =
  // side to move delivers mate in N; negative = side to move gets mated
  // in N), reset per search. Separate from `_latestScore`, which only
  // encodes mate as a large sign-only placeholder for the blunder check's
  // centipawn-delta threshold — this tracks the actual distance for
  // getMateDistance.
  int? _latestMateIn;
  final Map<int, EngineMoveCandidate> _multiPvCandidates = {};

  // Stockfish's `Skill Level` is a persistent engine option, not a
  // per-search parameter — it stays in effect for every subsequent `go`
  // until changed again. `evaluateFen` (the anti-blunder shield) and
  // `getBestMove` (the bot's own move) share this one engine instance, so
  // leaving Skill Level set to the bot's configured difficulty would make
  // the blunder check itself run on a deliberately weakened engine (e.g.
  // Skill Level 1 at the default 900 ELO), unreliably missing real
  // blunders. Only `getBestMove` weakens the engine for its own search,
  // immediately restoring full strength (20, Stockfish's own default)
  // afterward, so `evaluateFen` always evaluates at full strength.
  int _skillLevel = 20;

  // All public operations are serialized through this queue so they never
  // overlap. This prevents the shared-completer race that caused the spinner
  // to hang when setBotElo (unawaited in the constructor) ran concurrently
  // with evaluateFen.
  Future<void> _queue = Future.value();

  ChessEngineRepositoryImpl() {
    _engine = Stockfish();
    // `_engine.stdout` already emits complete, newline-stripped lines (the
    // stockfish package reassembles them internally from raw pipe reads),
    // so re-splitting with `LineSplitter` here was a no-op transformer that
    // buffers forever waiting for a `\n` it will never see — `_handleUciOutput`
    // never fired as a result, independent of platform.
    _stdoutSub = _engine.stdout.listen(_handleUciOutput);
    _initEngine();
  }

  void _initEngine() {
    void onReady() {
      if (_engine.state.value == StockfishState.ready) {
        _engine.state.removeListener(onReady);
        _engine.stdin = 'uci';
      }
    }

    _engine.state.addListener(onReady);
    onReady();
  }

  void _handleUciOutput(String line) {
    line = line.trim();
    if (line.isEmpty) return;

    if (line == 'readyok') {
      final c = _syncCompleter;
      _syncCompleter = null;
      c?.complete();
    } else if (line.contains('score cp')) {
      final m = RegExp(r'score cp (-?\d+)').firstMatch(line);
      if (m != null) _latestScore = int.parse(m.group(1)!);
      _parseMultiPvLine(line);
    } else if (line.contains('score mate')) {
      _latestScore = line.contains('-') ? -10000 : 10000;
      final m = RegExp(r'score mate (-?\d+)').firstMatch(line);
      if (m != null) _latestMateIn = int.parse(m.group(1)!);
      _parseMultiPvLine(line);
    } else if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      final move = parts.length > 1 ? parts[1] : '';

      final ec = _evalCompleter;
      if (ec != null && !ec.isCompleted) {
        _evalCompleter = null;
        ec.complete(_latestScore ?? 0);
      }
      final mc = _moveCompleter;
      if (mc != null && !mc.isCompleted) {
        _moveCompleter = null;
        mc.complete(move);
      }
    }
  }

  // Waits until the engine process is running (up to 15 s).
  Future<void> _waitReady() async {
    if (_engine.state.value == StockfishState.ready) return;
    final c = Completer<void>();
    void listener() {
      if (_engine.state.value == StockfishState.ready) {
        _engine.state.removeListener(listener);
        if (!c.isCompleted) c.complete();
      }
    }

    _engine.state.addListener(listener);
    await c.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => _engine.state.removeListener(listener),
    );
  }

  // Sends isready and waits for readyok (up to 8 s).
  Future<void> _sync() async {
    final c = Completer<void>();
    _syncCompleter = c;
    _engine.stdin = 'isready';
    await c.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _syncCompleter = null;
      },
    );
  }

  // Prepares the engine for a fresh search on [fen].
  //
  // Sends `stop` first so that any in-progress search terminates. The
  // resulting `bestmove` (if any) arrives before `readyok` and is safely
  // ignored because _evalCompleter / _moveCompleter are null at this point
  // (they are set only AFTER _prepareSearch returns).
  Future<void> _prepareSearch(String fen) async {
    try {
      _engine.stdin = 'stop';
    } catch (_) {}
    _engine.stdin = 'ucinewgame';
    _engine.stdin = 'position fen $fen';
    await _sync();
  }

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final Future<T> next = _queue.then<T>((_) => fn());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> setBotElo(int elo) => _serialized(() async {
    await _waitReady();
    _engine.stdin = 'setoption name UCI_LimitStrength value false';
    await _sync();
    _skillLevel = ((elo - 800) / 100).clamp(0, 20).toInt();
    // Not sent to the engine here — see _skillLevel's doc comment. Applied
    // only around getBestMove's own search.
  });

  @override
  Future<int> evaluateFen(String fen, {int depth = 5}) => _serialized(() async {
    await _waitReady();
    await _prepareSearch(fen);
    // Completers are set AFTER prepareSearch so that any stale bestmove from
    // the defensive `stop` (processed before readyok) does not complete them.
    _evalCompleter = Completer<int>();
    _latestScore = 0;
    _engine.stdin = 'go movetime 300';
    return _evalCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        try {
          _engine.stdin = 'stop';
        } catch (_) {}
        _evalCompleter = null;
        return _latestScore ?? 0;
      },
    );
  });

  @override
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500}) =>
      _serialized(() async {
        await _waitReady();
        await _prepareSearch(fen);
        // Reuses the eval completer/plumbing — this is just another
        // "search and read out the score" operation, not a move selection.
        _evalCompleter = Completer<int>();
        _latestScore = 0;
        _latestMateIn = null;
        _engine.stdin = 'go movetime $movetimeMs';
        await _evalCompleter!.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            try {
              _engine.stdin = 'stop';
            } catch (_) {}
            _evalCompleter = null;
            return 0;
          },
        );
        return _latestMateIn;
      });

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 1000}) =>
      _serialized(() async {
        await _waitReady();
        // Weaken for this search only — _prepareSearch's own isready/readyok
        // sync (called right after) covers acknowledging this setoption too,
        // so this adds no extra round trip.
        _engine.stdin = 'setoption name Skill Level value $_skillLevel';
        await _prepareSearch(fen);
        _moveCompleter = Completer<String>();
        _engine.stdin = 'go movetime $movetimeMs';
        final move = await _moveCompleter!.future.timeout(
          Duration(milliseconds: movetimeMs + 4000),
          onTimeout: () {
            try {
              _engine.stdin = 'stop';
            } catch (_) {}
            _moveCompleter = null;
            return '(none)';
          },
        );
        // Restore full strength immediately so evaluateFen (blunder check)
        // never runs on a weakened engine.
        try {
          _engine.stdin = 'setoption name Skill Level value 20';
        } catch (_) {}
        return move;
      });

  void _parseMultiPvLine(String line) {
    if (line.contains('lowerbound') || line.contains('upperbound')) return;
    final multiPvMatch = RegExp(
      r'multipv (\d+) score (?:cp (-?\d+)|mate (-?\d+)).*?\bpv ([a-h][1-8][a-h][1-8][qrbn]?(?:\s+[a-h][1-8][a-h][1-8][qrbn]?)*)',
    ).firstMatch(line);
    if (multiPvMatch == null) return;

    final pvIndex = int.parse(multiPvMatch.group(1)!);
    final cpStr = multiPvMatch.group(2);
    final mateStr = multiPvMatch.group(3);
    final pvMoves = multiPvMatch.group(4)!.trim().split(RegExp(r'\s+'));
    if (pvMoves.isEmpty) return;

    final int? mateIn = mateStr != null ? int.parse(mateStr) : null;
    final int scoreCp = cpStr != null
        ? int.parse(cpStr)
        : (mateIn != null && mateIn > 0
              ? 10000 - mateIn * 10
              : -10000 - (mateIn ?? 0) * 10);

    _multiPvCandidates[pvIndex] = EngineMoveCandidate(
      uci: pvMoves.first,
      scoreCp: scoreCp,
      mateIn: mateIn,
      pv: pvMoves,
    );
  }

  @override
  Future<List<EngineMoveCandidate>> getTopMoves(
    String fen, {
    int movetimeMs = 600,
    int multiPv = 6,
    int? mateLimit,
  }) => _serialized(() async {
    await _waitReady();
    _engine.stdin = 'setoption name Skill Level value 20';
    _engine.stdin = 'setoption name MultiPV value $multiPv';
    await _prepareSearch(fen);

    _multiPvCandidates.clear();
    _latestScore = 0;
    _latestMateIn = null;
    _moveCompleter = Completer<String>();

    final mateClause = mateLimit != null ? ' mate $mateLimit' : '';
    _engine.stdin = 'go movetime $movetimeMs$mateClause';

    final bestMove = await _moveCompleter!.future.timeout(
      Duration(milliseconds: movetimeMs + 4000),
      onTimeout: () {
        try {
          _engine.stdin = 'stop';
        } catch (_) {}
        _moveCompleter = null;
        return '(none)';
      },
    );

    // Always restore MultiPV = 1 so evaluateFen & getBestMove stay fast!
    try {
      _engine.stdin = 'setoption name MultiPV value 1';
    } catch (_) {}

    final sortedKeys = _multiPvCandidates.keys.toList()..sort();
    final results = [for (final k in sortedKeys) _multiPvCandidates[k]!];

    if (results.isEmpty && bestMove != '(none)' && bestMove.isNotEmpty) {
      return [
        EngineMoveCandidate(
          uci: bestMove,
          scoreCp: _latestScore ?? 0,
          mateIn: _latestMateIn,
        ),
      ];
    }
    return results;
  });

  @override
  void dispose() {
    _stdoutSub?.cancel();
    if (_engine.state.value == StockfishState.ready) {
      _engine.dispose();
    }
  }
}
