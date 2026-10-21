/// A named opening line the player can choose to practice — see
/// docs/features/done/opening_book_follower.md. `uciMoves` is the scripted
/// book sequence (standard textbook theory, ~6-8 plies) in UCI notation,
/// starting from the standard starting position.
class ChessOpening {
  final String id;
  final String name;
  final List<String> uciMoves;

  const ChessOpening({
    required this.id,
    required this.name,
    required this.uciMoves,
  });
}

const kOpenings = [
  ChessOpening(
    id: 'italian',
    name: 'Italian Game',
    uciMoves: ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'],
  ),
  ChessOpening(
    id: 'ruy_lopez',
    name: 'Ruy Lopez (Spanish Game)',
    uciMoves: ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6', 'b5a4', 'g8f6'],
  ),
  ChessOpening(
    id: 'sicilian',
    name: 'Sicilian Defense',
    uciMoves: ['e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', 'f3d4', 'g8f6'],
  ),
  ChessOpening(
    id: 'french',
    name: 'French Defense',
    uciMoves: ['e2e4', 'e7e6', 'd2d4', 'd7d5', 'b1c3', 'g8f6'],
  ),
  ChessOpening(
    id: 'caro_kann',
    name: 'Caro-Kann Defense',
    uciMoves: ['e2e4', 'c7c6', 'd2d4', 'd7d5', 'b1c3', 'd5e4', 'c3e4', 'c8f5'],
  ),
  ChessOpening(
    id: 'queens_gambit',
    name: "Queen's Gambit",
    uciMoves: ['d2d4', 'd7d5', 'c2c4', 'e7e6', 'b1c3', 'g8f6'],
  ),
  ChessOpening(
    id: 'kings_indian',
    name: "King's Indian Defense",
    uciMoves: ['d2d4', 'g8f6', 'c2c4', 'g7g6', 'b1c3', 'f8g7', 'e2e4', 'd7d6'],
  ),
  ChessOpening(
    id: 'english',
    name: 'English Opening',
    uciMoves: ['c2c4', 'e7e5', 'g1f3', 'b8c6', 'b1c3', 'g8f6'],
  ),
  ChessOpening(
    id: 'london',
    name: 'London System',
    uciMoves: ['d2d4', 'd7d5', 'g1f3', 'g8f6', 'c1f4'],
  ),
  ChessOpening(
    id: 'scandinavian',
    name: 'Scandinavian Defense',
    uciMoves: ['e2e4', 'd7d5', 'e4d5', 'd8d5', 'b1c3', 'd5a5'],
  ),
];
