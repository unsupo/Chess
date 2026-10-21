# Feature Design & Implementation Guide: Scholar's Mate / Fast-Mate Hunter Bot

**Status:** Design & Reference Implementation Guide  
**Target Architecture:** Clean Architecture (`domain` / `data` / `presentation`) in `lib/features/game/`

---

## 1. What the Bundled Stockfish C++ Engine Actually Supports

By inspecting the vendored Stockfish C++ source in `third_party/stockfish/{ios,macos}/Stockfish/src/` (`engine.cpp`, `uci.cpp`, `search.cpp`, `ucioption.cpp`), here is the exact set of capabilities and constraints of the bundled engine:

### 1.1 Registered UCI Options (`engine.cpp` lines 73–149)
| Option Name | Type | Default | Range | Relevance to Mate-Hunter Bot |
|---|---|---|---|---|
| `MultiPV` | `spin` | `1` | `1..MAX_MOVES` | **Supported.** Causes `Search::Worker::iterative_deepening()` (`search.cpp:302–438`) to run a full root search for the top $K$ legal moves and emit `info ... multipv 1..K score cp|mate V pv <moves>` lines via `SearchManager::pv()` (`search.cpp:2122–2181`). |
| `Skill Level` | `spin` | `20` | `0..20` | **Supported.** When `< 20`, internally forces `multiPV = std::max(multiPV, 4)` (`search.cpp:307–308`) and at search completion swaps `rootMoves[0]` with `Skill::pick_best(rootMoves, multiPV)` (`search.cpp:540–543`, `1912–1939`), which adds a randomized weakness push across the top 4 root moves. **Crucial caveat:** `SearchManager::pv()` only emits `info ... multipv i` up to `options["MultiPV"]` (`search.cpp:2122`), NOT the internal `std::max(multiPV, 4)`. You must explicitly set `setoption name MultiPV value K` to receive $K$ PV info lines on `stdout`! |
| `UCI_LimitStrength` / `UCI_Elo` | `check` / `spin` | `false` / `1320` | `1320..3190` | **Present in C++, disabled by project rule.** Always kept `false` in `native_engine_repository.dart`. |
| `Contempt` | — | — | — | **NOT SUPPORTED.** Modern NNUE Stockfish (including this bundled version) completely removed the `Contempt` UCI option. Do not send `setoption name Contempt ...` (`ucioption.cpp:58` will reply `No such option: Contempt`). Instead, internal optimism is computed dynamically from `rootMoves[pvIdx].averageScore` (`search.cpp:361`). |
| `Threads` / `Hash` / `Clear Hash` | `spin` / `button` | `1` / `16` | — | Standard engine resource management. |

### 1.2 Supported `go` Limits (`uci.cpp` lines 181–218)
`UCIEngine::parse_limits` supports:
- `go movetime <ms>`: Hard time budget checked in `SearchManager::check_time()` (`search.cpp:1970`).
- `go mate <N>`: Sets `limits.mate = N`. In `Search::Worker::iterative_deepening()` (`search.cpp:465–471`), the search stops early (`threads.stop = true`) as soon as `rootMoves[0]` proves a forced mate in $\le N$ moves (`VALUE_MATE - rootMoves[0].score <= 2 * limits.mate`).
  - **Caveat with `go mate N` alone:** Just like `go depth N` (see `docs/GOTCHAS.md` #4), `go mate N` **without `movetime`** has no time ceiling if no mate in $\le N$ exists! However, `parse_limits` parses multiple tokens in the same `go` command, so **`go movetime 400 mate 5`** works and combines both: it stops *immediately* if a mate in $\le 5$ is found, and otherwise terminates cleanly at `400 ms`!
- `go searchmoves <m1> <m2> ...` (must be the last token on the `go` line, `uci.cpp:188`): Restricts root search (`rootMoves`) to the specified subset of legal UCI moves.

### 1.3 Important Interaction Between `MultiPV` and `bestThread` / `Skill Level` (`search.cpp:235–254`, `540–543`)
1. When `MultiPV > 1`, `bestThread` selection across multiple threads is bypassed (`int(options["MultiPV"]) == 1` check at `search.cpp:235`), and `SearchManager::pv()` emits `info depth D seldepth S multipv I score <cp X | mate M> ... pv <m1> <m2> ...` for each $I \in \{1 \dots \text{MultiPV}\}$ at the end of each root depth iteration.
2. Just like `Skill Level` (see `docs/GOTCHAS.md` #14), **`MultiPV` is a persistent UCI option**. If a method sets `MultiPV` to `6` for candidate generation, it **must** reset `setoption name MultiPV value 1` immediately after the search finishes so `evaluateFen` (the Anti-Blunder Shield) doesn't suffer a $6\times$ search slowdown!
3. When searching for candidate moves with `getTopMoves`, `Skill Level` should be kept at `20` (full strength) during the MultiPV search so the candidate evaluations (`scoreCp` / `mateIn`) are accurate and uncorrupted, while bot strength/style selection happens in Dart over the returned candidates.

---

## 2. Clean Architecture Design: The 3-Phase "Scholar's Mate / Fast-Mate Hunter"

Because Stockfish's NNUE evaluation is objectively trained to maximize win probability against a perfect opponent, Stockfish on its own will **never** play 2. `Qh5` (which drops evaluation by ~50–80 cp against best play) and in overwhelmingly winning positions (+9.00) it may prefer a quiet positional squeeze (`h3`, `Rd1`) over an objectively slightly less accurate but viciously direct mating threat unless guided.

To build a bot that:
1. Relentlessly tries to mate as fast as possible,
2. Attempts Scholar's Mate (`1. e4 e5 2. Qh5` / `Bc4` / `Qxf7#`, or the Black mirror `1... e5 2... Qh4` / `Bc5` / `Qxf2#`) in the opening, and
3. Keeps pressing aggressively for a fast mate when Scholar's Mate is defended,

we combine a **Domain Policy (`FastMateHunterPolicy`)** with **MultiPV Engine Candidate Search (`getTopMoves`)** across three deterministic priority phases on every bot turn:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Bot Move Selection Pipeline                          │
├─────────────────────────────────────────────────────────────────────────┤
│ Phase 0: Immediate Mate-in-1 Check (Pure Dart `chess` package, 0 ms)    │
│   └─ Does any legal move deliver `in_checkmate` right now (e.g. Qxf7#)? │
│      YES ──► Play it immediately!                                       │
├─────────────────────────────────────────────────────────────────────────┤
│ Phase 1: Scholar's Mate Opening Trap Book (Plys 0–7)                    │
│   └─ Are we still in the opening phase with Queen + Bishop alive, and   │
│      does a scripted Scholar's Mate setup move exist that:              │
│        (a) is legal in the current FEN, AND                             │
│        (b) does not walk into an immediate capture / >150cp blunder?    │
│      YES ──► Play the Scholar's Mate trap move (`e4`, `Qh5`, `Bc4`,     │
│              or Secondary Mate-Threat Pivot like `Nf3`/`Ng5` or `Qb3`)! │
├─────────────────────────────────────────────────────────────────────────┤
│ Phase 2: Forced-Mate Hunter (Full-Strength MultiPV / Mate Search)       │
│   └─ Query engine `getTopMoves(fen, multiPv: 6, movetimeMs: ...)`       │
│   └─ Does ANY candidate have `mateIn != null && mateIn > 0`?            │
│      YES ──► Pick the candidate with the MINIMUM positive `mateIn`      │
│              (shortest forced mate, regardless of ELO)!                 │
├─────────────────────────────────────────────────────────────────────────┤
│ Phase 3: "Keep Pressing" Aggressive King-Hunt Scorer                    │
│   └─ Filter candidates within `toleranceCp` (e.g. 150–200 cp of best,   │
│      widened to 300 cp when bot is already winning by >= +300 cp so it  │
│      sacrifices extra material or plays sharp lines to force mate).     │
│   └─ Score each candidate by tactical / king-hunt heuristics:           │
│        + Mate Threat Next Turn (after our move, does a null-move /      │
│          direct threat on f7/f2/king-zone create mate-in-1?)            │
│        + Direct Check (`+`) & Double/Discovered Check                   │
│        + Attacks / Captures into the Enemy King Zone (Chebyshev dist ≤2)│
│        + Battery / Pressure on f7/f2, g7/g2, h7/h2                      │
│        + High-value Captures (weighted by victim value)                 │
│        + Forward Piece Advancement toward Enemy King                    │
│        - Heavy Penalty for Trading Queens (keeps mating power on board) │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer-by-Layer Implementation Specification

### 3.1 Domain Layer: `EngineMoveCandidate` & `ChessEngineRepository`

Update `lib/features/game/domain/repositories/chess_engine_repository.dart` to expose `EngineMoveCandidate` and `getTopMoves`:

```dart
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

abstract class ChessEngineRepository {
  Future<void> setBotElo(int elo);
  Future<int> evaluateFen(String fen, {int depth = 5});
  Future<String> getBestMove(String fen, {int movetimeMs = 500});
  Future<int?> getMateDistance(String fen, {int movetimeMs = 500});

  /// Returns up to [multiPv] ranked root move candidates from Stockfish.
  /// Runs at full tactical vision (`Skill Level 20`) unless [useSkillLevel]
  /// is true, so mate distances and centipawn evaluations are exact.
  Future<List<EngineMoveCandidate>> getTopMoves(
    String fen, {
    int movetimeMs = 600,
    int multiPv = 6,
    int? mateLimit,
  });

  void dispose();
}
```

### 3.2 Data Layer: MultiPV Parsing in `native_engine_repository.dart`

In `lib/features/game/data/repositories/native_engine_repository.dart`:
1. Add a `final Map<int, EngineMoveCandidate> _multiPvCandidates = {};` map to `ChessEngineRepositoryImpl`.
2. In `_handleUciOutput(String line)`:
   Stockfish's `UCIEngine::on_update_full` (`uci.cpp:618–641`) always formats full info lines in this exact order:
   ```
   info depth <D> seldepth <S> multipv <K> score <cp X | mate M> [lowerbound|upperbound] [wdl ...] nodes <N> nps <NPS> hashfull <H> tbhits <T> time <MS> pv <m1> <m2> ...
   ```
   Notice that only exact/completed PV lines or standard iteration updates include `multipv <K>` and `pv <moves>`. Ignore lines with `lowerbound` or `upperbound` when updating `_multiPvCandidates` (or let the final exact line for that depth overwrite it):
   ```dart
   final multiPvMatch = RegExp(
     r'multipv (\d+) score (cp (-?\d+)|mate (-?\d+)).*?\bpv ([a-h][1-8][a-h][1-8][qrbn]?(?:\s+[a-h][1-8][a-h][1-8][qrbn]?)*)',
   ).firstMatch(line);
   if (multiPvMatch != null) {
     final pvIndex = int.parse(multiPvMatch.group(1)!);
     final cpStr = multiPvMatch.group(3);
     final mateStr = multiPvMatch.group(4);
     final pvMoves = multiPvMatch.group(5)!.trim().split(RegExp(r'\s+'));
     if (pvMoves.isNotEmpty) {
       final int? mateIn = mateStr != null ? int.parse(mateStr) : null;
       final int scoreCp = cpStr != null
           ? int.parse(cpStr)
           : (mateIn != null && mateIn > 0 ? 10000 - mateIn * 10 : -10000 - (mateIn ?? 0) * 10);
       _multiPvCandidates[pvIndex] = EngineMoveCandidate(
         uci: pvMoves.first,
         scoreCp: scoreCp,
         mateIn: mateIn,
         pv: pvMoves,
       );
     }
   }
   ```
3. Implement `getTopMoves`:
   ```dart
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
   ```

4. In `lib/features/game/data/repositories/web_engine_repository.dart`, add a pure-Dart fallback implementation of `getTopMoves` that enumerates legal moves (prioritizing checks and captures so the Mate-Hunter bot still plays Scholar's Mate and hunts the king on Web too!).

---

### 3.3 Domain Layer: `ScholarsMateHunterPolicy` (The 3 Phases in Detail)

Create `lib/features/game/domain/usecases/scholars_mate_hunter_policy.dart` (pure Dart, `package:chess/chess.dart` only — zero Flutter imports, 100% unit-testable).

#### Phase 0: Immediate Mate-in-1 Check (0 ms, Pure Dart)
Before touching the book or even if the engine time budget is tight, scan all legal moves in `fen` using `chess_lib.Chess`:
```dart
for (final move in chess.generate_moves()) {
  chess.make_move(move);
  final isMate = chess.in_checkmate;
  chess.undo_move();
  if (isMate) return _toUci(move); // e.g., Qxf7# or Qxf2#
}
```
This guarantees that if `f7` (or `f2`) is ever left undefended and aligned with the Queen + Bishop battery, the bot executes `Qxf7#` / `Qxf2#` with 100% certainty and zero latency.

#### Phase 1: Dynamic State-Based Scholar's Mate Trap Book (White & Black)
Why a **board-state / goal-driven** Scholar's Mate sequence is vastly superior to a fragile fixed ply list (`['e2e4', 'e7e5', 'd1h5', ...]`) alone:
- A human beginner rarely plays the exact textbook `1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6?? 4. Qxf7#`. They might play `1. e4 d6`, `1. e4 c5`, `1. e4 e6`, or `1. e4 e5 2. Qh5 g6 3. Qxe5+!`.
- Or if the human plays `1. e4 e5 2. Bc4` (Bishop first) or `2. Qh5 Nf6` (attacking the Queen and defending `e5`? No, after `1. e4 e5 2. Qh5 Nf6??`, `3. Qxe5+` wins the pawn with check or `3. Bc4` walks into `3... Nxh5` hanging the Queen!).

Therefore, **Phase 1 uses a Position-Aware Scholar's Mate State Machine** during the first 6 full moves (`fullMoves <= 6`), verified for safety by the engine's candidate evaluations (`candidates`):

1. **White Scholar's Mate Progression (Targeting `f7`):**
   - **Step 1 (Open the Queen & Bishop diagonals):** If White's `e2` pawn hasn't moved and `e2e4` is legal, play **`e2e4`**.
   - **Step 2 (Deploy the Battery — `f1c4` and `d1h5` / `d1f3`):**
     - Check whether `f7` is still on its starting square (`bP` on `f7`) and Black's King is still on `e8` or `g8`.
     - **If `d1h5` is legal and safe** (i.e. `h5` is not attacked by a Black piece such as a Knight on `f6` or Pawn on `g6`, AND after `d1h5` Black does not capture our Queen or win material):
       - Prefer `d1h5` on Move 2 if Black played `1... e5` (immediately threatening `Qxe5+` AND setting up `Bc4` → `Qxf7#`), or if `f1c4` is already on `c4`.
     - **If `1... e5 2. Qh5 g6??` happened:** Black blundered the `e5` pawn and `h8` rook fork! Phase 3 / Stockfish immediately plays **`h5e5` (`Qxe5+`)** winning the `h8` Rook!
     - **If `f1c4` is legal and safe** (not capturable for free on `c4`, and our Queen on `h5`/`f3` isn't currently attacked and needing to retreat!):
       - Play **`f1c4`** to complete the battery on `f7`!
     - **If our Queen on `h5` is attacked (e.g. `2... Nf6` or `3... g6` after `Bc4`):**
       - Do **NOT** blindly play another piece and hang the Queen! Pivot the Queen to **`h5f3`** (`Qf3`, keeping the battery Mate-in-1 threat on `f7` alive against `3... g6` -> `4. Qf3` threatening `Qxf7#` again!) or `h5e2` if `f3` is attacked.
     - **Step 3 (Reinforce the `f7` attack if defended once):**
       - If Queen is on `f3`/`h5` and Bishop is on `c4`, and Black defended `f7` (e.g., `Qe7` or `Nh6`), check if **`g1f3` → `f3g5`** (`Ng5`, adding a third attacker to `f7`) or **`d2d3` → `c1h6`** (removing the `g7`/`f8` defender) or **`b1c3` → `c3d5`** is within the candidate safety window!

2. **Black Mirror Scholar's Mate Progression (Targeting `f2`):**
   - When the bot plays Black (`boardFlipped == true`), it mirrors the exact same logic against `f2`:
     - **Move 1:** Play **`e7e5`** against `1. e4` (or `1. d4` / `1. c4` / `1. g3` if safe; if `1. d4 e5` is a gambit (Englund Gambit `1. d4 e5 2. dxe5 Nc6 / Qh4 / Bc5`), only play if within tolerance, otherwise play `1... e5` against `1. e4`, `1. f4`, `1. Nc3`, `1. b3`, `1. g3`).
     - **Battery Setup:** Deploy **`f8c5`** (`Bc5` eyeing `f2`) and **`d8h4`** (`Qh4` eyeing `f2` and `e4`), provided `h4` is not guarded by `Nf3` or `g3`!
     - **Queen Pivot:** If White plays `g3` while Black's Queen is on `h4` and Bishop is on `c5`, pivot **`h4f6`** (`Qf6`, renewing the Mate-in-1 threat `Qxf2#`!).

3. **Safety Guard on Every Scripted Move:**
   Before Phase 1 returns any scripted move `scriptedUci`:
   - Verify `scriptedUci` is legal in `fen`.
   - Verify `scriptedUci` does **not** leave the bot's Queen hanging (check opponent responses in `chess_lib`) AND, once engine candidates are fetched, verify `scriptedUci` is within a reasonable opening trap tolerance (`<= 180 cp` worse than Stockfish's best move, since `2. Qh5` itself is ~70 cp worse than `2. Nf3`). If the opponent plays a refutation where the scripted move loses a piece (> 200 cp drop), Phase 1 cleanly aborts the script and falls through to Phase 2 / Phase 3!

---

#### Phase 2: Forced-Mate Hunting (Shortest Mate Path Always Wins)
Once `getTopMoves(fen, movetimeMs: ..., multiPv: 6, mateLimit: 8)` returns `List<EngineMoveCandidate> candidates`:
1. Filter all candidates with `c.mateIn != null && c.mateIn! > 0`.
2. If non-empty:
   - Sort by `c.mateIn!` ascending (so `mateIn == 1` beats `mateIn == 2`, which beats `mateIn == 4`).
   - Return `fastestMate.uci` immediately!
   - **Note:** Because `getTopMoves` runs with `Skill Level 20` and `mateLimit: 8`, the bot has **grandmaster-level mate vision** up to 8 moves deep even if its ELO slider is set to 1400, fulfilling Requirement #1 (*"Relentlessly tries to mate as fast as possible"*).

---

#### Phase 3: "Keep Pressing" Aggressive King-Hunt Mode
When no forced mate (`mateIn > 0`) is on the board yet, the bot must keep pressing relentlessly to crack open the enemy king and create a mating net as fast as possible.

1. **Dynamic Evaluation Tolerance Band (`toleranceCp`):**
   Let `bestCp = candidates.first.scoreCp` (Stockfish's top choice).
   - If the bot is **ahead by $\ge 300\text{ cp}$** (`bestCp >= 300`): set `toleranceCp = 280`. Why? When a computer is up a piece or rook (+500 cp), Stockfish normally plays slow, ultra-safe prophylaxis (`a4`, `h6`) or trades queens because +480 cp and +500 cp are both winning. Widening the tolerance band when winning lets the bot **sacrifice an exchange or pawn to rip open the king's pawn shield, refuse queen trades, and launch direct checks** as long as it remains clearly winning ($\ge +220\text{ cp}$)!
   - In normal/equal positions (`-150 <= bestCp < 300`): set `toleranceCp = 140` (allows sharp gambits, king-zone sacrifices, and aggressive piece storms without blundering a full piece).
   - When defending a worse position (`bestCp < -150`): set `toleranceCp = 90` (looks for swindle counter-attacks and checks on the enemy king without collapsing immediately).
   - Also reject any candidate with `c.mateIn != null && c.mateIn! < 0` (unless *all* candidates get mated, in which case pick the one that delays mate the longest: minimum `|c.mateIn!|`).

2. **Tactical & King-Hunt Heuristic Scoring Formula:**
   For each candidate move `c` inside the tolerance band, evaluate the board state before (`chessBefore`) and after (`chessAfter`) applying `c.uci` in pure Dart:

   $$\text{TotalScore}(c) = c.\text{scoreCp} + \text{AttackBonus}(c)$$

   where $\text{AttackBonus}(c)$ sums the following tactical terms:

   | Heuristic Feature | Bonus / Penalty (in cp-equivalent units) | How It Is Computed in Pure Dart (`chess` package) |
   |---|---|---|
   | **Creates Immediate Mate-in-1 Threat** | **`+450`** | Flip the turn (`w` ↔ `b`) in `afterFen` (passing the turn / null-move check) and test if the bot now has a legal move delivering `in_checkmate` (e.g., `Qf3` threatening `Qxf7#`, or `Qh6` threatening `Qg7#`). Even stronger (`+600`) if the opponent isn't already in check and must find a defense! |
   | **Gives Direct Check (`+`)** | **`+120`** | `chessAfter.in_check == true`. Forces the enemy King to react immediately. |
   | **Check Restriction (King Mobility Squeeze)** | **`+25 × (6 - oppResponses)`** | When `chessAfter.in_check` is true, fewer legal replies for the opponent (`chessAfter.generate_moves().length`) means the enemy King is closer to a mating net! |
   | **Targets `f7` / `f2` or Enemy King Zone** | **`+90` (Queen/Bishop/Knight attacks King Zone)** | Locate enemy King square $(f_K, r_K)$. Define **King Zone** as all squares with Chebyshev distance $\max(|f - f_K|, |r - r_K|) \le 2$. Count how many King-Zone squares the moved piece now attacks (or if the move lands in the King Zone). |
   | **Captures Near Enemy King / Pawn Shield Rip** | **`+110` (King-Zone capture) + `25 × victimValue`** | Capturing a pawn or defender right in front of the enemy King (distance $\le 2$ from enemy King, e.g. `Bxf7+`, `Nxg7`, `Qxh7+`) gets a massive bonus on top of the captured piece value (`P=1, N=3, B=3, R=5, Q=9`). |
   | **Piece Advancement Toward Enemy King** | **`+15 × distReduction`** | Compare Manhattan/Chebyshev distance of the moving piece from `fromSq` to the enemy King vs. `toSq` to the enemy King (for `Q`, `N`, `B`, `R`). Rewards marching pieces toward the enemy monarch. |
   | **Enemy King Exposure / Castling Denial** | **`+80`** | If the opponent had castling rights before the move and loses them in `afterFen` (e.g., `Bxf7+` forcing `Kxf7`), reward stripping castling rights. |
   | **Queen Trade Avoidance** | **`-550`** | If our Queen is on the board before the move and either (a) our move captures the enemy Queen with our Queen, or (b) our move places our Queen on a square where the opponent's Queen can legally capture it on the next ply. Keeping Queens on the board is critical for fast mates! |
   | **Leaves Moved Piece Hanging for Free** | **`-80 × movedPieceValue`** | Check if any opponent legal capture on `toSq` uses a strictly lower-value attacker (e.g., pawn takes Knight/Bishop/Queen) or if `toSq` is undefended, unless the move is inside Stockfish's top 50 cp (which means Stockfish verified it's a sound sacrifice!). |

---

## 4. Concrete Walkthrough: How the Bot Plays in Practice

### Scenario A: Classic Scholar's Mate (Human Falls for the Trap)
1. **Move 1 (Bot = White):** Phase 1 plays `e2e4`.
2. **Human:** `1... e7e5`.
3. **Move 2 (Bot):** Phase 1 sees `e7e5`, checks `d1h5` is legal & safe (`scoreCp` ~ `-55`, well inside the 180 cp opening trap window). Plays **`d1h5` (`Qh5`)** — attacking `e5` and `f7`.
4. **Human:** `2... b8c6` (defending `e5`).
5. **Move 3 (Bot):** Phase 1 sees `Qh5` on `h5`, `f7` unguarded except by King, plays **`f1c4` (`Bc4`)** — creating the Mate-in-1 battery on `f7`!
6. **Human:** `3... g8f6??` (developing the Knight, overlooking `f7`).
7. **Move 4 (Bot):** Phase 0 scans legal moves, sees **`h5f7` (`Qxf7#`)** produces `chess.in_checkmate == true`, and plays it instantaneously!

### Scenario B: Human Defends with `3... g6`, Then Blunders
1. `1. e4 e5 2. Qh5 Nc6 3. Bc4 g6` (Human blocks the `h5-f7` diagonal and attacks the Queen).
2. **Move 4 (Bot):**
   - Phase 0: No mate in 1.
   - Phase 1: Detects `Queen` on `h5` is under attack by `g6` pawn and `f7` is still the target. Evaluates **`h5f3` (`Qf3`)** — saving the Queen while re-aiming the battery vertically at `f7`! Also Phase 3 gives `h5f3` a **`+450` Immediate Mate-in-1 Threat bonus** because passing the turn after `Qf3` gives `Qxf7#`!
   - Bot plays **`4. Qf3`**.
3. If Human plays `4... Nf6`, Phase 1 ends and Phase 3 takes over:
   - Bot looks at `getTopMoves(multiPv: 6)` and boosts moves like `g1e2`, `d2d3` (opening the dark-squared bishop `Bc1-h6` / `Bg5` to pin and eliminate the `f6` knight defending `f7`!), or `b1c3` → `Nd5` piling onto `f6` and `c7`.

### Scenario C: Middlegame King Hunt (No Forced Mate Yet, Bot Presses Relentlessly)
- Suppose the opponent survived the opening and castled kingside (`O-O`).
- Stockfish's top 6 moves (`getTopMoves`) are:
  1. `a2a3` (`+45 cp`) — quiet prophylactic pawn move
  2. `f1e1` (`+40 cp`) — centralizing rook
  3. `d1g4` (`+15 cp`) — bringing Queen to `g4` eyeing `g7` (King Zone!)
  4. `c1h6` (`+10 cp`) — attacking the `g7` kingside shield
  5. `f3g5` (`-10 cp`) — jumping Knight into `g5`, creating a Mate-in-1 threat on `h7`!
- Standard Stockfish plays `a2a3`.
- **Scholar's Mate / Fast-Mate Hunter Phase 3:**
  - `f3g5` gets `+450` (creates mate-in-1 threat `Qxh7#`) + `+90` (attacks King Zone `h7`/`f7`) + `+30` (advances toward enemy King) = **`+560` style score**, easily beating `a2a3` (`+45`) while remaining inside the 140 cp tolerance band!

---

## 5. Clean Integration with `BotPersonality` & `GameNotifier`

### 5.1 `lib/features/game/domain/entities/bot_personality.dart`
Can either upgrade the existing **`aggressor`** (`The Aggressor`) personality or add a dedicated **`mate_hunter`** (`The Scholar` / `Mate Hunter`) personality:

```dart
  BotPersonality(
    id: 'mate_hunter', // or apply directly to 'aggressor'
    name: 'The Scholar',
    emoji: '⚡',
    tagline: 'Fast-Mate Hunter',
    greeting:
        "Checkmate is the only goal. Watch your f7 square—I won't give you a second chance!",
    defaultElo: 1500,
  ),
```

### 5.2 `lib/features/game/presentation/providers/game_provider.dart`
In `GameNotifier._pickBotMove(String fen, int elo)`:
```dart
  Future<String> _pickBotMove(String fen, int elo) async {
    if (state.personality.id == 'aggressor' ||
        state.personality.id == 'mate_hunter') {
      // 1. Fast check for immediate Mate-in-1 (0 ms, no engine wait needed)
      final mateIn1 = ScholarsMateHunterPolicy.findImmediateMateIn1(fen);
      if (mateIn1 != null) return mateIn1;

      // 2. Fetch MultiPV candidates from Stockfish (with `mate 8` early-exit if forced mate <= 8 exists)
      final candidates = await _engine.getTopMoves(
        fen,
        movetimeMs: _moveTimeMs(elo),
        multiPv: 6,
        mateLimit: 8,
      );

      // 3. Run the 3-Phase Scholar's Mate + Fast-Mate Hunter Policy
      final chosen = ScholarsMateHunterPolicy.selectMove(
        fen: fen,
        candidates: candidates,
      );
      if (chosen != null && chosen.isNotEmpty) {
        return chosen;
      }
    }
    // Existing fallback for other personalities...
```

---

## 6. Reference Implementation: `ScholarsMateHunterPolicy`

Below is the complete, drop-in pure-Dart domain implementation for `lib/features/game/domain/usecases/scholars_mate_hunter_policy.dart`:

```dart
import 'dart:math' as math;
import 'package:chess/chess.dart' as chess_lib;
import '../repositories/chess_engine_repository.dart';

/// Pure-Dart domain policy that implements the 3-Phase Fast-Mate Hunter:
///   - Phase 0: Immediate Mate-in-1 execution (`Qxf7#`, `Qxf2#`, etc.)
///   - Phase 1: Position-aware Scholar's Mate / Wayward Queen trap sequence
///              (for both White targeting f7 and Black targeting f2, with
///              automatic `Qf3`/`Qf6` battery continuation if poked by `g6`/`g3`,
///              and safety validation so it never hangs the Queen).
///   - Phase 2: Shortest Forced-Mate selection (`mateIn > 0`).
///   - Phase 3: "Keep Pressing" King-Hunt candidate scorer (mate-in-1 threats,
///              direct checks, enemy king-zone attacks/captures, piece
///              advancement toward the enemy king, and queen-trade avoidance).
class ScholarsMateHunterPolicy {
  /// Opening trap tolerance in centipawns (2. Qh5 is ~70cp below 2. Nf3, so
  /// 180cp allows the Wayward Queen setup while rejecting moves that lose a piece).
  static const int openingTrapToleranceCp = 180;

  /// Standard middlegame tolerance band in centipawns.
  static const int baseToleranceCp = 150;

  /// Widened tolerance band when the bot is already winning (>= +300cp),
  /// allowing aggressive sacrifices and direct mating attacks over slow play.
  static const int winningToleranceCp = 280;

  /// Phase 0: Returns a UCI move if any legal move delivers checkmate immediately.
  static String? findImmediateMateIn1(String fen) {
    final chess = chess_lib.Chess()..load(fen);
    final moves = chess.generate_moves();
    for (final move in moves) {
      chess.make_move(move);
      final isMate = chess.in_checkmate;
      chess.undo_move();
      if (isMate) {
        return _moveToUci(move);
      }
    }
    return null;
  }

  /// Runs Phases 0 -> 1 -> 2 -> 3 to select the most aggressive mate-seeking move.
  static String? selectMove({
    required String fen,
    required List<EngineMoveCandidate> candidates,
  }) {
    // Phase 0: Immediate Mate-in-1
    final mateIn1 = findImmediateMateIn1(fen);
    if (mateIn1 != null) return mateIn1;

    // Phase 2 (Checked before Phase 1 so if the opponent blundered a forced
    // mate in 2 or 3 during the opening, we take the guaranteed forced mate!):
    final forcedMateMove = _findShortestForcedMate(candidates);
    if (forcedMateMove != null) return forcedMateMove;

    // Phase 1: Position-Aware Scholar's Mate Opening Trap (first 6 full moves)
    final openingMove = _pickScholarsMateOpeningMove(fen, candidates);
    if (openingMove != null) return openingMove;

    // Phase 3: "Keep Pressing" King-Hunt Scorer over MultiPV candidates
    if (candidates.isNotEmpty) {
      return _pickAggressiveMove(fen, candidates);
    }

    return null;
  }

  /// Phase 2: Picks the candidate with the smallest positive `mateIn`.
  static String? _findShortestForcedMate(
    List<EngineMoveCandidate> candidates,
  ) {
    EngineMoveCandidate? bestMate;
    for (final c in candidates) {
      if (c.mateIn != null && c.mateIn! > 0) {
        if (bestMate == null || c.mateIn! < bestMate.mateIn!) {
          bestMate = c;
        }
      }
    }
    return bestMate?.uci;
  }

  /// Phase 1: Position-aware Scholar's Mate sequence for White (targeting f7)
  /// and Black (targeting f2).
  static String? _pickScholarsMateOpeningMove(
    String fen,
    List<EngineMoveCandidate> candidates,
  ) {
    final chess = chess_lib.Chess()..load(fen);
    if (chess.in_check) return null; // Defend check tactically via Phase 3

    final fenTokens = fen.split(RegExp(r'\s+'));
    final fullMoveNumber =
        (fenTokens.length > 5 ? int.tryParse(fenTokens[5]) : null) ?? 1;
    if (fullMoveNumber > 6) return null;

    final isWhite = chess.turn == chess_lib.Color.WHITE;
    final legalUcis = {
      for (final m in chess.generate_moves()) _moveToUci(m),
    };

    // Build ordered list of desired Scholar's Mate setup moves based on board state
    final desiredTrapMoves = <String>[];

    if (isWhite) {
      final e2Piece = chess.get('e2');
      final d1Piece = chess.get('d1');
      final f1Piece = chess.get('f1');
      final h5Piece = chess.get('h5');
      final c4Piece = chess.get('c4');
      final f3Piece = chess.get('f3');

      // 1. Open e2-e4
      if (fullMoveNumber == 1 &&
          e2Piece?.type == chess_lib.PieceType.PAWN &&
          e2Piece?.color == chess_lib.Color.WHITE) {
        desiredTrapMoves.add('e2e4');
      }

      // 2. If Queen is on h5 and under attack (e.g. after ...g6 or ...Nf6),
      //    pivot Queen to f3 (`h5f3`) to maintain the Mate-in-1 battery on f7!
      if (h5Piece?.type == chess_lib.PieceType.QUEEN &&
          h5Piece?.color == chess_lib.Color.WHITE &&
          _isSquareAttackedByOpponent(chess, 'h5')) {
        // But first: if e5 is free to capture with check (`Qxe5+`), Phase 3 / candidates will love `h5e5`!
        desiredTrapMoves.addAll(['h5e5', 'h5f3']);
      }

      // 3. Bring out Qh5 and Bc4 to form the Scholar's Mate battery on f7
      final queenOnBattery = (h5Piece?.type == chess_lib.PieceType.QUEEN &&
              h5Piece?.color == chess_lib.Color.WHITE) ||
          (f3Piece?.type == chess_lib.PieceType.QUEEN &&
              f3Piece?.color == chess_lib.Color.WHITE);
      final bishopOnBattery = c4Piece?.type == chess_lib.PieceType.BISHOP &&
          c4Piece?.color == chess_lib.Color.WHITE;

      if (d1Piece?.type == chess_lib.PieceType.QUEEN &&
          d1Piece?.color == chess_lib.Color.WHITE) {
        desiredTrapMoves.add('d1h5');
      }
      if (f1Piece?.type == chess_lib.PieceType.BISHOP &&
          f1Piece?.color == chess_lib.Color.WHITE) {
        desiredTrapMoves.add('f1c4');
      }
      if (d1Piece?.type == chess_lib.PieceType.QUEEN &&
          d1Piece?.color == chess_lib.Color.WHITE &&
          bishopOnBattery) {
        desiredTrapMoves.add('d1f3');
      }

      // 4. If both Queen and Bishop are aimed at f7, pile on with Nf3 -> Ng5 or Nc3 -> Nd5
      if (queenOnBattery && bishopOnBattery) {
        desiredTrapMoves.addAll(['f3g5', 'g1f3', 'b1c3', 'c3d5']);
      }
    } else {
      // Black Mirror Scholar's Mate targeting f2
      final e7Piece = chess.get('e7');
      final d8Piece = chess.get('d8');
      final f8Piece = chess.get('f8');
      final h4Piece = chess.get('h4');
      final c5Piece = chess.get('c5');
      final f6Piece = chess.get('f6');

      if (fullMoveNumber == 1 &&
          e7Piece?.type == chess_lib.PieceType.PAWN &&
          e7Piece?.color == chess_lib.Color.BLACK) {
        desiredTrapMoves.add('e7e5');
      }

      if (h4Piece?.type == chess_lib.PieceType.QUEEN &&
          h4Piece?.color == chess_lib.Color.BLACK &&
          _isSquareAttackedByOpponent(chess, 'h4')) {
        desiredTrapMoves.addAll(['h4e4', 'h4f6']);
      }

      final queenOnBattery = (h4Piece?.type == chess_lib.PieceType.QUEEN &&
              h4Piece?.color == chess_lib.Color.BLACK) ||
          (f6Piece?.type == chess_lib.PieceType.QUEEN &&
              f6Piece?.color == chess_lib.Color.BLACK);
      final bishopOnBattery = c5Piece?.type == chess_lib.PieceType.BISHOP &&
          c5Piece?.color == chess_lib.Color.BLACK;

      if (d8Piece?.type == chess_lib.PieceType.QUEEN &&
          d8Piece?.color == chess_lib.Color.BLACK) {
        desiredTrapMoves.add('d8h4');
      }
      if (f8Piece?.type == chess_lib.PieceType.BISHOP &&
          f8Piece?.color == chess_lib.Color.BLACK) {
        desiredTrapMoves.add('f8c5');
      }
      if (d8Piece?.type == chess_lib.PieceType.QUEEN &&
          d8Piece?.color == chess_lib.Color.BLACK &&
          bishopOnBattery) {
        desiredTrapMoves.add('d8f6');
      }

      if (queenOnBattery && bishopOnBattery) {
        desiredTrapMoves.addAll(['f6g4', 'g8f6', 'b8c6', 'c6d4']);
      }
    }

    final bestEngineScore =
        candidates.isNotEmpty ? candidates.first.scoreCp : 0;

    for (final trapUci in desiredTrapMoves) {
      if (!legalUcis.contains(trapUci)) continue;

      // Safety Check 1: Does this move hang our Queen or allow an immediate mate?
      if (_hangsQueenOrAllowsMate(fen, trapUci)) continue;

      // Safety Check 2: If engine candidates include this move, verify it's within
      // openingTrapToleranceCp of the best move.
      final matchingCandidate =
          candidates.where((c) => c.uci == trapUci).firstOrNull;
      if (matchingCandidate != null) {
        if (matchingCandidate.mateIn != null && matchingCandidate.mateIn! < 0) {
          continue;
        }
        if (bestEngineScore - matchingCandidate.scoreCp >
            openingTrapToleranceCp) {
          continue;
        }
      }

      return trapUci;
    }

    return null;
  }

  /// Phase 3: Scores candidate moves to relentlessly press against the enemy King.
  static String _pickAggressiveMove(
    String fen,
    List<EngineMoveCandidate> candidates,
  ) {
    final bestCp = candidates.first.scoreCp;
    final tolerance = bestCp >= 300
        ? winningToleranceCp
        : (bestCp < -150 ? 90 : baseToleranceCp);

    // Filter out candidates that get us mated or drop too much evaluation
    final viable = candidates.where((c) {
      if (c.mateIn != null && c.mateIn! < 0) return false;
      return (bestCp - c.scoreCp) <= tolerance;
    }).toList();

    final pool = viable.isNotEmpty ? viable : [candidates.first];

    String bestUci = pool.first.uci;
    double bestTotalScore = double.negativeInfinity;

    for (final c in pool) {
      final styleBonus = scoreAggressiveCandidate(fen, c.uci);
      final totalScore = c.scoreCp.toDouble() + styleBonus;
      if (totalScore > bestTotalScore) {
        bestTotalScore = totalScore;
        bestUci = c.uci;
      }
    }

    return bestUci;
  }

  /// Computes the tactical & king-hunt bonus (in cp-equivalent units) for playing [uci] from [fen].
  static double scoreAggressiveCandidate(String fen, String uci) {
    final before = chess_lib.Chess()..load(fen);
    final us = before.turn;
    final them =
        us == chess_lib.Color.WHITE ? chess_lib.Color.BLACK : chess_lib.Color.WHITE;

    final fromSq = uci.substring(0, 2);
    final toSq = uci.substring(2, 4);
    final movingPiece = before.get(fromSq);
    final capturedPiece = before.get(toSq);
    if (movingPiece == null) return 0;

    final enemyKingSq = _findKingSquare(before, them);

    final after = chess_lib.Chess()..load(fen);
    final moved = after.move({
      'from': fromSq,
      'to': toSq,
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return -10000;

    double bonus = 0;

    // 1. Immediate Mate-in-1 Threat on the next turn (+450)
    if (_createsMateIn1Threat(after.fen, us)) {
      bonus += 450;
    }

    // 2. Direct Check (+120) & Opponent King Mobility Squeeze
    if (after.in_check) {
      bonus += 120;
      final oppReplies = after.generate_moves().length;
      bonus += math.max(0, 6 - oppReplies) * 25;
    }

    // 3. Captures (weighted higher if near the enemy King!)
    if (capturedPiece != null) {
      final victimVal = _pieceValue(capturedPiece.type);
      bonus += victimVal * 22;
      if (enemyKingSq != null && _chebyshevDist(toSq, enemyKingSq) <= 2) {
        bonus += 110; // Ripping open the enemy King's shield!
      }
    }

    // 4. Pressure on f7/f2 and Enemy King Zone (Chebyshev distance <= 2)
    if (enemyKingSq != null) {
      final distBefore = _chebyshevDist(fromSq, enemyKingSq);
      final distAfter = _chebyshevDist(toSq, enemyKingSq);
      if (distAfter < distBefore) {
        bonus += (distBefore - distAfter) * 18;
      }
      if (distAfter <= 2) {
        bonus += movingPiece.type == chess_lib.PieceType.QUEEN ? 95 : 65;
      }
    }

    // 5. Heavy Penalty for Trading Queens (-550)
    final isQueenTrade = movingPiece.type == chess_lib.PieceType.QUEEN &&
        capturedPiece?.type == chess_lib.PieceType.QUEEN;
    if (isQueenTrade) {
      bonus -= 550;
    } else if (_allowsOpponentQueenTrade(after, us)) {
      bonus -= 350;
    }

    return bonus;
  }

  // ── Internal Board Helpers ──────────────────────────────────────────────

  static String _moveToUci(chess_lib.Move m) {
    final from = chess_lib.Chess.algebraic(m.from);
    final to = chess_lib.Chess.algebraic(m.to);
    final promo = m.promotion != null ? m.promotion!.name : '';
    return '$from$to$promo';
  }

  static int _pieceValue(chess_lib.PieceType type) {
    switch (type) {
      case chess_lib.PieceType.PAWN:
        return 1;
      case chess_lib.PieceType.KNIGHT:
      case chess_lib.PieceType.BISHOP:
        return 3;
      case chess_lib.PieceType.ROOK:
        return 5;
      case chess_lib.PieceType.QUEEN:
        return 9;
      case chess_lib.PieceType.KING:
        return 0;
      default:
        return 0;
    }
  }

  static String? _findKingSquare(chess_lib.Chess chess, chess_lib.Color color) {
    const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    for (final f in files) {
      for (var r = 1; r <= 8; r++) {
        final sq = '$f$r';
        final p = chess.get(sq);
        if (p != null &&
            p.color == color &&
            p.type == chess_lib.PieceType.KING) {
          return sq;
        }
      }
    }
    return null;
  }

  static int _chebyshevDist(String sq1, String sq2) {
    final f1 = sq1.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final r1 = sq1.codeUnitAt(1) - '1'.codeUnitAt(0);
    final f2 = sq2.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final r2 = sq2.codeUnitAt(1) - '1'.codeUnitAt(0);
    return math.max((f1 - f2).abs(), (r1 - r2).abs());
  }

  /// Checks if `square` can be captured by the opponent on the next ply if
  /// we pass the turn (or in the current position if it's opponent's turn).
  static bool _isSquareAttackedByOpponent(
    chess_lib.Chess currentChess,
    String square,
  ) {
    final tokens = currentChess.fen.split(' ');
    if (tokens.length < 6) return false;
    tokens[1] = tokens[1] == 'w' ? 'b' : 'w';
    tokens[3] = '-'; // clear ep square to avoid invalid FEN when flipping turn
    final flippedChess = chess_lib.Chess();
    if (!flippedChess.load(tokens.join(' '))) return false;
    for (final m in flippedChess.generate_moves()) {
      if (chess_lib.Chess.algebraic(m.to) == square) return true;
    }
    return false;
  }

  /// Checks if playing `uci` from `fen` allows the opponent to capture our Queen
  /// or deliver mate-in-1 on the very next ply.
  static bool _hangsQueenOrAllowsMate(String fen, String uci) {
    final chess = chess_lib.Chess()..load(fen);
    final us = chess.turn;
    final moved = chess.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci[4],
    });
    if (!moved) return true;

    for (final oppMove in chess.generate_moves()) {
      final targetSq = chess_lib.Chess.algebraic(oppMove.to);
      final targetPiece = chess.get(targetSq);
      if (targetPiece != null &&
          targetPiece.color == us &&
          targetPiece.type == chess_lib.PieceType.QUEEN) {
        return true; // Opponent can capture our Queen!
      }
      chess.make_move(oppMove);
      final isMate = chess.in_checkmate;
      chess.undo_move();
      if (isMate) return true; // Opponent has mate in 1!
    }
    return false;
  }

  /// Returns true if, after our move (resulting in [afterFen]), we would have
  /// a legal Mate-in-1 if it were our turn again (a direct mate threat!).
  static bool _createsMateIn1Threat(String afterFen, chess_lib.Color us) {
    final tokens = afterFen.split(' ');
    if (tokens.length < 6) return false;
    tokens[1] = us == chess_lib.Color.WHITE ? 'w' : 'b';
    tokens[3] = '-';
    final nullMoveChess = chess_lib.Chess();
    if (!nullMoveChess.load(tokens.join(' '))) return false;
    if (nullMoveChess.in_check) return false;

    for (final m in nullMoveChess.generate_moves()) {
      nullMoveChess.make_move(m);
      final isMate = nullMoveChess.in_checkmate;
      nullMoveChess.undo_move();
      if (isMate) return true;
    }
    return false;
  }

  static bool _allowsOpponentQueenTrade(
    chess_lib.Chess after,
    chess_lib.Color us,
  ) {
    for (final m in after.generate_moves()) {
      final fromSq = chess_lib.Chess.algebraic(m.from);
      final toSq = chess_lib.Chess.algebraic(m.to);
      final attacker = after.get(fromSq);
      final victim = after.get(toSq);
      if (attacker?.type == chess_lib.PieceType.QUEEN &&
          victim?.type == chess_lib.PieceType.QUEEN &&
          victim?.color == us) {
        return true;
      }
    }
    return false;
  }
}
```
