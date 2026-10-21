import 'package:flutter/painting.dart';

class BoardTheme {
  final Color lightSquare;
  final Color darkSquare;
  final Color selectedSquare;
  final Color legalMoveHint;
  final Color lastMove;
  final Color check;

  const BoardTheme({
    required this.lightSquare,
    required this.darkSquare,
    required this.selectedSquare,
    required this.legalMoveHint,
    required this.lastMove,
    required this.check,
  });

  static const forest = BoardTheme(
    lightSquare: Color(0xFFB5D99C),
    darkSquare: Color(0xFF6A9E5A),
    selectedSquare: Color(0xFFDDDF6B),
    legalMoveHint: Color(0x551A1A1A),
    lastMove: Color(0x70F6F669),
    check: Color(0xBBFF4040),
  );

  static const classic = BoardTheme(
    lightSquare: Color(0xFFEEEED2),
    darkSquare: Color(0xFF769656),
    selectedSquare: Color(0xFFBBCC44),
    legalMoveHint: Color(0x551A1A1A),
    lastMove: Color(0x70F6F669),
    check: Color(0xBBFF4040),
  );

  static const dark = BoardTheme(
    lightSquare: Color(0xFF4E4E6E),
    darkSquare: Color(0xFF252545),
    selectedSquare: Color(0xFF5E7FD0),
    legalMoveHint: Color(0x55FFFFFF),
    lastMove: Color(0x55F6F669),
    check: Color(0xBBFF4040),
  );
}
