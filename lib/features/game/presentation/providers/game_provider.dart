import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../../data/repositories/chess_engine_repository_impl.dart';
import '../../domain/entities/move_result.dart';
import '../../domain/repositories/chess_engine_repository.dart';
import '../../domain/usecases/attempt_move_usecase.dart';

// --- Dependency Injection ---
final engineRepositoryProvider = Provider<ChessEngineRepository>((ref) {
  final repo = ChessEngineRepositoryImpl();
  ref.onDispose(() => repo.dispose());
  return repo;
});

final attemptMoveUseCaseProvider = Provider<AttemptMoveUseCase>((ref) {
  return AttemptMoveUseCase(ref.watch(engineRepositoryProvider));
});

// --- State Management ---
class GameState {
  final String fen;
  final bool isEvaluating;
  final String? errorMessage;
  final String? botMoveUci;
  final int botElo; // Added ELO level tracking

  GameState({
    required this.fen, 
    this.isEvaluating = false, 
    this.errorMessage, 
    this.botMoveUci,
    this.botElo = 1200, // Default to 1200
  });

  GameState copyWith({
    String? fen, 
    bool? isEvaluating, 
    String? errorMessage, 
    String? botMoveUci,
    int? botElo,
    bool clearError = false,
    bool clearBotMove = false,
  }) {
    return GameState(
      fen: fen ?? this.fen,
      isEvaluating: isEvaluating ?? this.isEvaluating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      botMoveUci: clearBotMove ? null : (botMoveUci ?? this.botMoveUci),
      botElo: botElo ?? this.botElo,
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

  GameNotifier(this._engine, this._attemptMove) : super(GameState(fen: chess_lib.Chess().fen)) {
    _engine.setBotElo(1200);
  }

  // Difficulty scaling helper functions
  int getDepthFromElo(int elo) => (elo / 100).floor().clamp(8, 16);
  int getMoveTimeFromElo(int elo) => (elo / 1.5).floor().clamp(400, 2000);

  Future<void> setDifficulty(int elo) async {
    await _engine.setBotElo(elo);
    state = state.copyWith(botElo: elo);
  }

  Future<void> onUserMove(String newFen, VoidCallback undoBlunder) async {
    state = state.copyWith(isEvaluating: true, clearError: true, clearBotMove: true);

    try {
      final result = await _attemptMove.execute(
        currentFen: state.fen,
        newFen: newFen,
      );

      if (result == MoveResult.blunder) {
        undoBlunder();
        state = state.copyWith(
          isEvaluating: false,
          errorMessage: "Blunder detected! Try finding a better move.",
        );
        return;
      }

      if (result == MoveResult.accepted) {
        state = state.copyWith(fen: newFen);

        // Scale bot strength based on chosen ELO
        final botMoveUci = await _engine.getBestMove(
          newFen, 
          movetimeMs: getMoveTimeFromElo(state.botElo),
        );

        if (botMoveUci == '(none)' || botMoveUci.isEmpty) {
          state = state.copyWith(isEvaluating: false);
          return;
        }
        
        state = state.copyWith(
          isEvaluating: false,
          botMoveUci: botMoveUci,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isEvaluating: false,
        errorMessage: "Engine communication error. Try again.",
      );
    }
  }

  void syncFen(String fen) {
    state = state.copyWith(fen: fen, clearBotMove: true);
  }
}
