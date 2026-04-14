import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import '../providers/game_provider.dart';

class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  late ChessBoardController _boardController;

  @override
  void initState() {
    super.initState();
    _boardController = ChessBoardController();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider);
    final boardSize = MediaQuery.of(context).size.width;

    // Listen for state changes (errors and bot moves)
    ref.listen<GameState>(gameProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (next.botMoveUci != null && next.botMoveUci != previous?.botMoveUci) {
        final uci = next.botMoveUci!;
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);

        if (uci.length > 4) {
          _boardController.makeMoveWithPromotion(
            from: from,
            to: to,
            pieceToPromoteTo: uci[4].toUpperCase(),
          );
        } else {
          _boardController.makeMove(from: from, to: to);
        }

        Future.delayed(Duration.zero, () {
          ref.read(gameProvider.notifier).syncFen(_boardController.getFen());
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anti-Blunder Chess'),
        actions: [
          // Difficulty Selector in AppBar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<int>(
              value: gameState.botElo,
              dropdownColor: Colors.grey[900],
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: 800, child: Text("800")),
                DropdownMenuItem(value: 1200, child: Text("1200")),
                DropdownMenuItem(value: 1600, child: Text("1600")),
                DropdownMenuItem(value: 2000, child: Text("2000")),
              ],
              onChanged: (elo) {
                if (elo != null) {
                  ref.read(gameProvider.notifier).setDifficulty(elo);
                }
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 40,
              child: gameState.isEvaluating
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Center(
                child: ChessBoard(
                  controller: _boardController,
                  size: boardSize,
                  boardColor: BoardColor.brown,
                  enableUserMoves: !gameState.isEvaluating,
                  boardOrientation: PlayerColor.white,
                  onMove: () {
                    final newFen = _boardController.getFen();
                    ref.read(gameProvider.notifier).onUserMove(newFen, () {
                      _boardController.undoMove();
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
