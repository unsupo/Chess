# Komodo TEP / Chess Explanation Engine (`CEE v1.130.53`) & Skills System

Extracted from `explanation-engine/1.130.53/default/explanation-engine.js` (`KOMODO_TEP`), `play-computer/2026.10.3/shared.eager.ZDyFHQYc7g.chunk.js`, and the embedded `chesscom.explanation_engine.v1` / `chesscom.skills.v1` Protobuf descriptors.

---

## 1. Dual-Engine WebAssembly Architecture (`KOMODO_TEP` + `CEE`)

`explanation-engine.js` (`v1.130.53`) is an Emscripten WebAssembly worker wrapper (`CREATE_KTEP_WORKER_API` / `KOMODO_TEP`) that combines **Komodo** (for human-like bot play, skill scaling, and chess variants) and the **Chess Explanation Engine (`CEE`)** (for natural-language move commentary, tactical motif classification, illegal-move explanations, and puzzle generation) in a single WASM binary (`explanation-engine.wasm`).

### WASM Loader Resilience & Telemetry
* **Retry Policy:** `WASM_FETCH_ATTEMPTS = 4`, `WASM_RETRY_BASE_MS = 500`, `WASM_STALL_TIMEOUT_MS = 30000` (30s per chunk), `WASM_STREAM_DEADLINE_MS = 60000` (60s total), verifying the magic header `WASM_MAGIC = [0, 97, 115, 109]` (`\0asm`).
* **Phase Timings (`reportWasmLoadTimings`):** Logs `CEE wasm load: source=... bytes=... attempts=... transfer=Xms compile=Yms engineInit=Zms total=Wms`.

### Exported Emscripten C-ABI Functions (`api_call_map` / `j3`)
```javascript
const CEE_COMMANDS = {
  ADD_ARTIFACT: 'CEE_AddArtifact',
  ADD_UCI_VARIATION: 'CEE_AddUciVariation',
  ADD_VARIATION: 'CEE_AddVariation',
  DISABLE_LOG: 'CEE_DisableLog',
  DISPOSE_FEATURE: 'CEE_DisposeFeature',
  DISPOSE_GAME: 'CEE_DisposeGame',
  ENABLE_LOG: 'CEE_EnableLog',
  GET_FEN: 'CEE_GetFen',
  GET_LAST_MOVE: 'CEE_GetLastMove',
  LOAD_CHARM_MODEL: 'CEE_LoadCharmModel',
  LOAD_APPLICABILITY_INDEX: 'CEE_LoadApplicabilityIndex',
  NEW_FEATURE: 'CEE_NewFeature',
  NEW_GAME: 'CEE_NewGame',
  PLAY: 'CEE_Play',
  RUN: 'CEE_Run',
};
```

### Protobuf Feature Handle Lifecycle (`P3` & `Cet`)
Every RPC method on `ExplanationEngineService` is mapped to a numeric `FeatureId` and a `gamePoint` node index:
1. **LRU Handle Eviction (`vet = 25`):** The worker client maintains an active queue `featureHandles[]` capped at `25`. When a 26th feature call arrives, it automatically calls `CEE_DisposeFeature` on the oldest handle (`featureHandles.shift()`).
2. **Execution:**
   * Marshals the request Protobuf into a `Uint8Array` (`TI(e.input, ...)`), copies it onto the WASM heap via `Module._malloc` + `Module.HEAPU8.set(...)`, and calls `CEE_NewFeature(game_point, feature_id, buf, size)` to obtain a `feature_handle`.
   * Calls `CEE_Run(feature_handle, 0)` (supporting both unary responses and `async*` server-streaming via `is_final: false/true` chunks!).

### Supported Engines Registry (`chesscom/engine/v1/engine.proto`)
* `ENGINE_SF12`, `ENGINE_SF15`, `ENGINE_SF15_NNUE`, `ENGINE_SF15_1`, `ENGINE_SF15_1_NNUE`, `ENGINE_SF16_NNUE`, `ENGINE_SF16_1_NNUE`, `ENGINE_SF18_NNUE`, **`ENGINE_SF19_NNUE`** (`Stockfish.js 19` with net `nn-61e7af4bb97d`)
* `ENGINE_DRAGON_3_3`, `ENGINE_KOMODO_3_3`
* `ENGINE_TORCH_3`, `ENGINE_TORCH_HUMAN`
* `ENGINE_SF9_FAIRPLAY_V1`
* Neural Human-Prediction Models (`ModelArch` in `bot_move_configuration.proto`): `MODEL_ARCH_CHARM`, `MODEL_ARCH_CHARM_SMALL`, `MODEL_ARCH_MAIA`, `MODEL_ARCH_MAIA3`.

---

## 2. Complete 72 Skills Taxonomy (`chesscom/explanation_engine/v1/skills.proto`)

When `enable_skills` is active in `GameSettings`, CEE detects when a player executes any of **72 specific chess skills** across **5 categories** (`FUNDAMENTALS`, `OPENINGS`, `TACTICS`, `STRATEGY`, `ENDGAME`) and awards skill points (`GainSkillPointsRequest`):

| Category | Skills (`chesscom.explanation_engine.v1.Skill`) |
| :--- | :--- |
| **1. Fundamentals** | `SKILL_CAPTURE`, `SKILL_CHECK`, `SKILL_CASTLE`, `SKILL_CHECKMATE`, `SKILL_FREE_PIECE`, `SKILL_DEFEND_PIECE`, `SKILL_RETREAT`, `SKILL_RECAPTURE`, `SKILL_WINNING_CAPTURE`, `SKILL_BLOCKS_ATTACK`, `SKILL_DEFEND_CHECKMATE`, `SKILL_EQUAL_TRADE`, `SKILL_EN_PASSANT`, `SKILL_PROMOTION`, `SKILL_LADDER_MATE`, `SKILL_BACKRANK_MATE`, `SKILL_QUEEN_CHECKMATE`, `SKILL_ROOK_CHECKMATE` |
| **2. Openings** | `SKILL_DEVELOPS_PIECE`, `SKILL_PAWNS_IN_CENTER`, `SKILL_STRIKES_AT_CENTER`, `SKILL_CONNECT_ROOKS`, `SKILL_COMPLETE_DEVELOPMENT`, `SKILL_ONE_BOOK_MOVE`, `SKILL_TWO_BOOK_MOVES`, `SKILL_THREE_BOOK_MOVES`, `SKILL_FOUR_BOOK_MOVES`, `SKILL_FIANCHETTO`, `SKILL_PREVENT_CASTLING`, `SKILL_WINS_TEMPO`, `SKILL_DEVELOP_WITH_TEMPO` |
| **3. Tactics** | `SKILL_FORK`, `SKILL_PIN`, `SKILL_ABSOLUTE_PIN`, `SKILL_DISCOVERED_ATTACK`, `SKILL_KNIGHT_FORK`, `SKILL_SKEWER`, `SKILL_ATTACKING_PINNED_PIECE`, `SKILL_TRAPPED_PIECE`, `SKILL_REMOVES_DEFENDER`, `SKILL_ROYAL_FORK`, `SKILL_DISCOVERED_CHECK`, `SKILL_COUNTER_THREAT`, `SKILL_DEFEND_TACTIC`, `SKILL_EXPLOITS_PIN`, `SKILL_DOUBLE_CHECK`, `SKILL_BRILLIANT_SACRIFICE`, `SKILL_QUEEN_SACRIFICE` |
| **4. Strategy** | `SKILL_POWERFUL_BISHOP`, `SKILL_ROOK_TO_OPEN_FILE`, `SKILL_KICK`, `SKILL_OUTPOST`, `SKILL_TRADING_TO_SIMPLIFY`, `SKILL_DOUBLE_ROOKS`, `SKILL_CREATES_BATTERY`, `SKILL_AVOIDS_TRADE`, `SKILL_DAMAGES_OPPONENT_PAWN_STRUCTURE`, `SKILL_IMPROVES_PAWN_STRUCTURE`, `SKILL_PAWN_STORM` |
| **5. Endgame** | `SKILL_PUSHES_PASSED_PAWN`, `SKILL_MAKES_PASSED_PAWN`, `SKILL_ACTIVATE_KING`, `SKILL_ROOK_TO_SEVENTH`, `SKILL_ROOK_BEHIND_OWN_PASSED_PAWN`, `SKILL_OPPOSITION`, `SKILL_DOUBLED_ROOKS_ON_THE_SEVENTH`, `SKILL_ROOK_BEHIND_OPPOSING_PASSED_PAWN`, `SKILL_MAKES_PROTECTED_PASSED_PAWN`, `SKILL_KING_AND_PAWN_ENDGAMES`, `SKILL_QUEEN_ENDGAMES`, `SKILL_ROOK_ENDGAMES`, `SKILL_KNIGHT_AND_BISHOP_ENDGAMES` |

---

## 3. Coach Interactive Interventions (`feature_get_coach_chat.proto`)

When playing against Coach (or in Coach mode), `GetCoachChatResponse` can return three interactive training exercises on top of normal commentary (`speech` + `coach_emotion`):

1. **`RetryMistake`:**
   * Triggered when the player makes a Mistake or Blunder.
   * Draws `arrows_and_squares` hinting at the danger, displays `speech`, and presents `retry_choice` vs. `keep_playing_choice` with a `ply_until_cooldown` counter so the Coach doesn't nag on every single ply.
2. **`RetryMiss`:**
   * Triggered when the player overlooks a tactical punish (`MOVE_CLASSIFICATION_MISSED`).
   * Offers an interactive mini-puzzle (`retry_misses_exercise`) tracking `wrongAttempts` (`found_correct_move`, `missed_correct_move`, `abandoned`).
3. **`FlipBoardMistake` ("Punish Your Own Blunder"):**
   * When the player blunders, Coach can offer to **flip the board** (`switch_sides_choice` vs. `decline_choice`) and challenge the player to find the `refutation_move` from the opponent's perspective!
   * Includes distinct speech lines for `offer_speech`, `success_speech`, `failure_speech`, and `failure_almost_speech`.

---

## 4. Beginner Illegal-Move Explanations (`feature_get_illegal_move_explanation.proto`)

When a user tries to make an illegal move on the board, `GetIllegalMoveExplanation` classifies the exact rule violation into one of **9 `IllegalMoveCase` enums** and returns both voice/text `speech` and visual `board_markings` (e.g., highlighting the checking piece or pin ray in red):

1. `ILLEGAL_MOVE_CASE_IN_CHECK` — King is currently in check and the move does not resolve it.
2. `ILLEGAL_MOVE_CASE_PIECE_PINNED_TO_KING` — Moving this piece would expose your own King to check (absolute pin).
3. `ILLEGAL_MOVE_CASE_PIECE_HAS_OTHER_LEGAL_MOVES` — Invalid movement pattern for this piece type.
4. `ILLEGAL_MOVE_CASE_PIECE_HAS_NO_LEGAL_MOVES` — Piece is completely blocked.
5. `ILLEGAL_MOVE_CASE_PAWN_CAN_ONLY_CAPTURE` — Trying to move a pawn diagonally onto an empty square, or straight into a blocked square when a diagonal capture exists.
6. `ILLEGAL_MOVE_CASE_PAWN_HAS_NO_LEGAL_MOVES` — Blocked pawn.
7. `ILLEGAL_MOVE_CASE_CASTLE_KING_MOVED` — Cannot castle because the King or Rook has already moved.
8. `ILLEGAL_MOVE_CASE_CASTLE_IN_CHECK` — Cannot castle while currently in check.
9. `ILLEGAL_MOVE_CASE_CASTLE_THROUGH_CHECK` — Cannot castle through an attacked square.

---

## 5. Tactical & Positional Motif Classifier (`analysis_type.proto` & `circumstance.proto`)

CEE combines a **19-value `Circumstance`** modifier (`BASE`, `THREATENS`, `PREVENTS`, `PERMITS`, `MISSES`, `MISSES_SAME`, `ENDGAME`, `GAME_STATUS`, `LEADS_TO`, `WINS_MATERIAL`, `GAME_OVER`, `MATE`, `BRILLIANT`, `GREAT_FIND`, `LONG_THINK`, `SHORT_THINK`, `TIME_TROUBLE`, `FORCES`) with **240+ `AnalysisType` motifs**, including:

* **Tactical Motifs:** `DIRECT_SACRIFICE_CAPTURE`, `DIRECT_SACRIFICE_ENPRISE`, `INDIRECT_SACRIFICE`, `FREE_PIECE`, `QUASI_FREE_PIECE`, `DISCOVERED_ATTACK_CHECK`, `FORK_WITH_MATE`, `FORK`, `ROYAL_FORK`, `PSEUDO_FORK`, `MULTI_ATTACK`, `SKEWER`, `DOUBLE_CHECK`, `PIN`, `RELATIVE_PIN`, `UNPINS_DEFENDER`, `PINS_ATTACKER`, `EXPLOITS_PINNED_DEFENDER`, `EXPLOITS_OVERLOADED_DEFENDER`, `REMOVES_DEFENDER`, `CHECKS_AWAY_DEFENDER`, `ATTRACTION`, `DECOY`, `DESPERADO`, `ZWISCHENZUG_BEFORE_RECAPTURE`, `ZWISCHENZUG_BEFORE_THREAT_RESOLUTION`, `TRAPPED_PIECE`, `BACK_RANK_MATE`, `LADDER_MATE`.
* **Positional & Structural Motifs:** `CREATES_LUFT`, `GAMBITS_PAWN`, `STRIKES_AT_CENTER`, `CENTRAL_BREAK`, `MAKES_PASSED_PAWN`, `CREATES_PROTECTED_PASSED_PAWN`, `TAKES_OUTPOST`, `TAKES_OUTPOST_WITH_TEMPO`, `ROOK_TAKES_OUTPOST`, `CHALLENGES_OPEN_FILE`, `TAKES_OPEN_FILE`, `ROOK_ON_SEVENTH`, `CONNECTS_ROOKS_7TH`, `ROOK_BEHIND_OWN_PAWN`, `ROOK_BEHIND_OPP_PAWN`, `ROOK_LIFT`, `CREATES_BATTERY`, `FIANCHETTO`, `PAWN_STORM`, `LAUNCHES_MINORITY_ATTACK`, `CARLSBAD_KNIGHT`, `PILLSBURY_KNIGHT`, `BLOCKADE`, `ISOLATES_PAWN_ON_SEMI_OPEN_FILE`, `BACKWARD_PAWN_ON_SEMI_OPEN_FILE`, `DOUBLED_ISOLATED_PAWN`, `CURES_BACKWARD_PAWN`, `CURES_ISOLATED_PAWN`, `KING_REACHES_SQUARE_OF_PAWN`, `GAINS_DIRECT_OPPOSITION_TO_WIN`, `GAINS_DIRECT_OPPOSITION_TO_DRAW`.
* **Classic Mistakes & Fun Easter Eggs:** `TOO_EARLY_QUEEN_DEVELOPMENT`, `MOVES_SAME_PIECE_IN_OPENING`, `MIDDLEGAME_START_NO_CASTLE`, `CASTLES_INTO_ATTACK`, **`ANALYSIS_TYPE_NEVER_PLAY_F3`** (a Ben Finegold tribute!), `MOUSE_SLIP`, `STALEMATE_WHEN_WINNING_BLUNDERED`, `THREEFOLD_REPETITION_WHEN_WINNING`.
