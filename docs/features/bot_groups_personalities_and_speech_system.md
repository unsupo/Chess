# Bot Groups Catalog (217 Bots), Move Sampling & Typewriter Speech System

Extracted from `api.chess.com/rpc/chesscom.bots.v1.BotGroupService/ListBotGroups.json`, `GetCurrentCoach.json`, `speech-assets.chess.com/encrypted/<BotName>/en_US.json`, `analysis/2026.10.3-hotfix.20ef972/shared.a89285a2.5w6cOnAP5E.chunk.js`, and the `chesscom.bots.v1` / `chesscom.explanation_engine.v1` Protobuf schemas.

---

## 1. Complete Bot Groups Catalog (`ListBotGroups.json`)

Chess.com organizes **217 distinct bot personalities** across **14 groups**:

| Group Name | Bot Count | Sample Bots (`username`, Rating, `komodoSkillLevel`, `personality`, `book`) |
| :--- | :---: | :--- |
| **1. The Cryptids** (`2026-10-Cryptids-Bot-Challenge`) | 5 | **Martinfoot** (`250`, Skill `1`, `BEGINNER`, book: `anthony_levin`), **Loch Chess Monster** (`575`, Skill `4`, `POSITIONAL`, book: `fabiano_caruana`), **Mothman** (`900`, Skill `7`, `HUMAN`, book: `winger`) |
| **2. New to Chess** | 5 | **Zach** (`1`, Skill `1`, `NEW_TO_CHESS`, book: `beginner`), **June** (`50`, Skill `1`, `NEW_TO_CHESS`, book: `offbeat`), **Pepe** (`100`, Skill `1`, `NEW_TO_CHESS`, book: `quick_queen`), **Robin**, **Elsa** |
| **3. Beginner** | 15 | **Martin** (`250`, Skill `1`, `DEFENSIVE`, book: `beginner`), **Wayne** (`250`, Skill `1`, `AGGRESSIVE`, book: `quick_queen`), **Fabian** (`250`, Skill `1`, `BEGINNER`, book: `winger`) |
| **4. Intermediate** | 15 | **Maria** (`1000`, Skill `6`, `ACTIVE`, book: `gambit`), **Maxim** (`1000`, Skill `6`, `ACTIVE`, book: `kenneth_wilber`), **Hans** (`1000`, Skill `6`, `POSITIONAL`, book: `michael_greene`) |
| **5. Advanced** | 20 | **Wendy** (`1500`, Skill `11`, `AGGRESSIVE`, book: `lasker`), **Antonio** (`1500`, Skill `11`, `DEFAULT`, book: `classical`), **Pierre** (`1500`, Skill `11`, `DEFENSIVE`, book: `f-pawner`) |
| **6. Master** | 10 | **Nora** (`2200`, Skill `18`, `AGGRESSIVE`, book: `quick_queen`), **Noam** (`2200`, Skill `18`, `POSITIONAL`, book: `steinitz`), **Ahmed** (`2200`, Skill `18`, `ACTIVE`, book: `f-pawner`) |
| **7. Adaptive** | 5 | **Jimmy** (`600`, Skill `3`), **Nisha** (`900`, Skill `5`), **Tomas** (`1200`, Skill `8`) — `adapt: true` |
| **8. Athletes** | 14 | **Aerial Powers** (`1100`, Skill `7`), **Dejan Joveljic** (`2217`, Skill `19`, `HIKARU`, book: `nakamura_classic`), **Justin Reid** (`1300`, Skill `12`) |
| **9. Musicians** | 6 | **Faye Webster** (`850`, Skill `10`, `HUMAN`), **Yoko Ono** (`1200`, Skill `9`, `POSITIONAL`, book: `spassky`), **Thomas Mars** (`1500`, Skill `11`, `AGGRESSIVE`) |
| **10. Creators** | 36 | **xQc** (`1200`, Skill `8`), **Mark Rober** (`1200`, Skill `9`, book: `tal`), **MrBeast** (`1100`, Skill `7`) |
| **11. Top Players** | 22 | **Hikaru** (`2820`, Skill `23`, `HIKARU`, book: `nakamura`), **Anna Muzychuk** (`2606`, Skill `21`), **Vishy** (`2820`, Skill `23`, book: `vishy_anand`) |
| **12. Personalities** | 14 | **Danny** (`2500`, Skill `20`, `DANNY`, book: `ulf_andersson`), **Agadmator** (`2000`, Skill `17`), **Robert Hess** (`2600`, Skill `22`) |
| **13. Visualization** | 25 | **Level 1–25** (`visualization-1` .. `visualization-25`) |
| **14. Engine** | 25 | **Komodo 1–25** (`Komodo1` rating `250` Skill `1` $\rightarrow$ `Komodo25` rating `3200+` Skill `25`) |

---

## 2. Bot Personality & Neural Move Sampling (`bot.proto` & `bot_move_configuration.proto`)

### 15 Engine Personality Styles (`BotPersonality` Enum)
1. `BOT_PERSONALITY_DEFAULT`
2. `BOT_PERSONALITY_ACTIVE`
3. `BOT_PERSONALITY_AGRESSIVE`
4. `BOT_PERSONALITY_BEGINNER`
5. `BOT_PERSONALITY_DEFENSIVE`
6. `BOT_PERSONALITY_ENDGAME`
7. `BOT_PERSONALITY_HUMAN`
8. `BOT_PERSONALITY_POSITIONAL`
9. `BOT_PERSONALITY_CARLSEN`
10. `BOT_PERSONALITY_FISCHER`
11. `BOT_PERSONALITY_HIKARU`
12. `BOT_PERSONALITY_KASPAROV`
13. `BOT_PERSONALITY_NEW_TO_CHESS`
14. `BOT_PERSONALITY_DANNY`
15. `BOT_PERSONALITY_UNLEASHED`

### V2 Bot Move Configuration (`BotMoveConfiguration`)
Modern v2 bots use a declarative Protobuf config combining engine search, opening books, and human-like neural networks (`CHARM` and `MAIA3`):
* **`BotMoveSettings`:** `depth`, `nodes`, `BookMovesSettings` (`name`, `move_count`), and `SamplingSettings` (`probability_threshold`).
* **`AdditiveConfig`:** Evaluates `n_top_moves` and `n_bad_moves`, applying `AdditiveBehavior` rules (`MatcherRule` matching `Circumstance`, `AnalysisType` tags, and `MoveClassification`), `PieceBonus` (biasing a bot toward moving specific piece types like Queen in `quick_queen`), `max_eval_drop`, `max_advantage`, and `CoherenceConfig` (`n_back` move consistency!).
* **`NnMultConfig`:** Scores top candidate moves using `MODEL_ARCH_CHARM`, `MODEL_ARCH_CHARM_SMALL`, `MODEL_ARCH_MAIA`, or `MODEL_ARCH_MAIA3` (`charm_input_search_depth`, `temperature`, `rating_scale`, `time_taken_multiplier`) gated by `PositionShape` (`PASSIVE`, `ACTIVE`, `CLOSED`, `OPEN`, `SEMI_OPEN`, `THREATENED`, `THREATENING`, `CALM`, `SHARP`).
* **Courtesy Pacing (`$v`):**
  * `computerMoveCourtesyDelay: 1500ms` (minimum delay or `suggested_delay_seconds` so bots don't snap-move instantly).
  * `botChat.nodeChangeDelay: 600ms`.

---

## 3. All 38 Contextual Bot Chat Triggers (`chesscom/bots/v1/phrase_list.proto`)

Every bot's dialogue (`PhraseList` / `speech-assets.chess.com/encrypted/<BotName>/<locale>.json`) is organized into **38 specific game-state triggers**:

### Lifecycle & Outcome Triggers
* `greeting`
* `rematch_if_user_has_played_before`
* `won`, `lost`, `draw`
* `winning`, `losing`

### Tactical & Material Triggers
* `first_capture`
* `giving_check`, `being_checked`
* `capturing_queen`, `queen_captured`
* `promoting_pawn`, `player_pawn_promote`
* `threatening`, `threatened`
* `computer_has_mate_in_x`, `player_has_mate_in_x`
* `random`

### Opening Triggers
* `opening_e4`, `opening_d4`, `opening_c4_english`, `opening_nf3`
* `opening_e4_e5_kings_pawn`
* `opening_e4_c5_sicilian`
* `opening_e4_c6_carokann`
* `opening_e4_e6_french`
* `opening_d4_nf6_indian`
* `opening_d4_d5_queens_gambit`
* `opening_other`

### Time-Spent & Endgame Phase Triggers
* `user_spends_more_than_15_seconds_on_a_move`
* `user_spends_more_than_1_minute_on_a_move`
* `user_spends_more_than_3_minutes_on_move`
* `r_p_endgame_reached` (Rook + Pawn endgame)
* `k_p_endgame_reached` (King + Pawn endgame)
* `heavy_piece_endgame_reached`
* `minor_piece_endgame_reached`
* `game_reached_move_40`, `game_reached_move_100`

---

## 4. Coach Emotion & Typewriter Keyword Synchronization (`shared.a89285a2`)

### 9 Coach Emotions (`coach_emotion.proto`)
Coach avatars (`coach_david.riv` with `hasVisemes: true` lip-sync) transition between 9 emotional states:
`IDLE`, `SURPRISED`, `HAPPY`, `IMPRESSED`, `SHOCKED`, `THINKING`, `CONCERNED`, `SAD` (`UNSPECIFIED` defaults to `'idle'`).

### Word-Preserving Typewriter + Interactive Board Markings (`MoveFeedbackSpeechText` / `fs`)
When Coach or a Bot explains a move (`Speech` containing `Sentence[]` where each `SentenceFragment` can carry `ArrowsAndSquares`), Chess.com avoids layout reflow jitter during the typewriter animation using a 3-part DOM split (`d` in `shared.a89285a2`):

1. **Pre-allocated Hidden Characters:**
   Every word (`<span class="typewriter-text-word">`) is rendered at full width from frame 0, split into:
   * `wordVisible`: characters revealed so far (`u.value - e.start`)
   * `wordHidden`: remaining characters in the word with `visibility: hidden` (`.typewriter-text-hidden`)
   Because the full word is already in the DOM, words **never jump to the next line** mid-typing!
2. **Interactive Keyword Spans (`[data-keyword-index]`):**
   Fragments that have `arrows.length > 0 || squares.length > 0` are rendered as highlighted keyword pills (`data-keyword-index`, `data-keyword-type`).
   * Hovering (`mouseEnter`), leaving (`mouseLeave`), or clicking (`click`) a keyword emits `analysis-keyword-interaction` with `{ interactionType, keywordType, markings: { arrows, squares } }`, immediately drawing the tactical arrows and square highlights on the chessboard!
