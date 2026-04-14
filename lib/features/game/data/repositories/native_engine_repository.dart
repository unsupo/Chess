import 'dart:async';
import 'dart:convert';
import 'package:stockfish/stockfish.dart';
import '../../domain/repositories/chess_engine_repository.dart';

class ChessEngineRepositoryImpl implements ChessEngineRepository {
  late final Stockfish _engine;
  StreamSubscription<void>? _stdoutSub;
  
  Completer<int>? _evalCompleter;
  Completer<String>? _moveCompleter;
  Completer<void>? _uciOkCompleter;
  Completer<void>? _readyOkCompleter;
  int? _latestScore; 

  ChessEngineRepositoryImpl() {
    _engine = Stockfish();
    _uciOkCompleter = Completer<void>();
    _readyOkCompleter = Completer<void>();
    
    _stdoutSub = _engine.stdout
        .transform(const LineSplitter())
        .listen(_handleUciOutput);
        
    _initEngine();
  }

  void _initEngine() {
    void checkState() {
      if (_engine.state.value == StockfishState.ready) {
        _engine.stdin = 'uci';
        _engine.stdin = 'isready';
      }
    }
    _engine.state.addListener(checkState);
    checkState();
  }

  void _handleUciOutput(String line) {
    line = line.trim();
    if (line.isEmpty) return;
    
    if (line == 'uciok') {
      if (_uciOkCompleter != null && !_uciOkCompleter!.isCompleted) _uciOkCompleter!.complete();
    } else if (line == 'readyok') {
      if (_readyOkCompleter != null && !_readyOkCompleter!.isCompleted) _readyOkCompleter!.complete();
    } else if (line.contains('score cp')) {
      final match = RegExp(r'score cp (-?\d+)').firstMatch(line);
      if (match != null) _latestScore = int.parse(match.group(1)!);
    } else if (line.contains('score mate')) {
      _latestScore = line.contains('-') ? -10000 : 10000;
    } else if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      final move = parts.length > 1 ? parts[1] : '';

      if (_evalCompleter != null && !_evalCompleter!.isCompleted) {
        _evalCompleter!.complete(_latestScore ?? 0);
        _evalCompleter = null;
      }
      if (_moveCompleter != null && !_moveCompleter!.isCompleted) {
        _moveCompleter!.complete(move);
        _moveCompleter = null;
      }
    }
  }

  Future<void> _waitForEngine() async {
    if (_engine.state.value != StockfishState.ready) {
      final completer = Completer<void>();
      void listener() {
        if (_engine.state.value == StockfishState.ready) {
          _engine.state.removeListener(listener);
          completer.complete();
        }
      }
      _engine.state.addListener(listener);
      await completer.future;
    }
    if (_uciOkCompleter != null && !_uciOkCompleter!.isCompleted) {
      await _uciOkCompleter!.future;
    }
  }

  Future<void> _syncEngine() async {
    _readyOkCompleter = Completer<void>();
    _engine.stdin = 'isready';
    await _readyOkCompleter!.future;
  }

  // Wipes the transposition tables so evaluations don't bleed into one another
  Future<void> _prepareSearch(String fen) async {
    _engine.stdin = 'ucinewgame';
    await _syncEngine();
    _engine.stdin = 'position fen $fen';
    await _syncEngine();
  }

  @override
  Future<void> setBotElo(int elo) async {
    await _waitForEngine();
    
    // Disable the buggy Elo parameter
    _engine.stdin = 'setoption name UCI_LimitStrength value false';
    await _syncEngine();
    
    // Map human Elo to Stockfish's universal Skill Level (0-20)
    int skillLevel = ((elo - 800) / 100).clamp(0, 20).toInt();
    _engine.stdin = 'setoption name Skill Level value $skillLevel';
    await _syncEngine();
  }

  @override
  Future<int> evaluateFen(String fen, {int depth = 12}) async {
    await _waitForEngine();
    _evalCompleter = Completer<int>();
    _latestScore = 0; 
    
    await _prepareSearch(fen); // Clear hash before eval
    _engine.stdin = 'go depth $depth';
    return _evalCompleter!.future;
  }

  @override
  Future<String> getBestMove(String fen, {int movetimeMs = 1000}) async {
    await _waitForEngine();
    _moveCompleter = Completer<String>();
    
    await _prepareSearch(fen); // Clear hash before picking a move
    _engine.stdin = 'go movetime $movetimeMs';
    return _moveCompleter!.future;
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    if (_engine.state.value != StockfishState.disposed && _engine.state.value != StockfishState.starting) {
       _engine.dispose();
    }
  }
}
