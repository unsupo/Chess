class EngineMoveCandidate {
  /// Move in UCI notation (e.g. 'd1h5', 'f1c4', 'h5f7').
  final String uci;

  /// Centipawn evaluation from the side-to-move's perspective.
  /// When [mateIn] is non-null, this is +/-10000.
  final int scoreCp;

  /// Signed forced-mate distance in full moves from side-to-move's perspective:
  /// - `mateIn > 0`: side to move forces mate in `mateIn` moves.
  /// - `mateIn < 0`: side to move is forcibly mated in `|mateIn|` moves.
  /// - `null`: no forced mate found in this PV line.
  final int? mateIn;

  /// Full principal variation move list in UCI format.
  final List<String> pv;

  const EngineMoveCandidate({
    required this.uci,
    required this.scoreCp,
    this.mateIn,
    this.pv = const [],
  });
}
