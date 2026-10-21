# Feature: Live Evaluation Pill, Move Classification Feedback, ECO Openings & SAN Move List

**Status:** Something in this functional area is Built, but **none of the
symbol names below ever existed in this codebase** — `MoveFeedbackType`,
`MoveRecord`, `_classifyCpLoss`, `_detectOpening`, `EvalScorePillWidget`,
`OpeningHeaderWidget`, `MoveFeedbackBanner`, and `SanMoveListStrip` all
return zero matches in `lib/`. The real, working equivalent was built
under completely different names — see "Actual Flutter Implementation"
below. Keeping the Chess.com reverse-engineering sections (1-4) as
reference material; just correcting what to actually go read in this repo.

## Overview

Reverse-engineered from Chess.com's `evaluation-lines` (`Q`), `move-feedback-row` (`Bx`), `quick-analysis-tallies` (`XE`), `eco-opening-panel` (`Jk`), and `move-san` (`eS`) components. Surfaces real-time engine evaluation scores, move quality badges (from Brilliant to Blunder), live opening recognition, and interactive SAN move history chips.

## Actual Flutter Implementation

- [`lib/features/game/domain/usecases/game_review_analyzer.dart`](../../lib/features/game/domain/usecases/game_review_analyzer.dart):
  - `MoveClassification` enum — 8 tiers (`brilliant !!`, `great !`, `best ★`, `book 📖`, `good ✓`, `inaccuracy ?!`, `mistake ?`, `blunder ??`), each carrying its own `symbol`/`label`. `GameReviewAnalyzer.classifyMove` assigns one per ply from `cpl`/`cpGain`/`winLoss`/mate/check — different thresholds than Chess.com's `XE` tiers below (no `greatfind`/`excellent`/`forced`/`missedwin` distinction; "Great" also covers Chess.com's `greatfind`).
  - `GameReviewAnalyzer.analyze` — the actual post-game accuracy/ACPL/estimated-ELO computation (not an eval *pill*; feeds `GameReviewSummary`, `docs/features/chesscom_reference/game_over_modal_and_game_review_narratives.md`-adjacent but likewise not built against that doc).
  - `OpeningBookClassifier.detectOpeningName`/`isBookPly` — a ~40-entry hardcoded opening table (not ECO-coded), matched against the game's own SAN move list prefix. This is the real "opening recognition"; there's no `eco-opening-panel` equivalent fetching ECO codes from a database.
- [`lib/features/game/presentation/widgets/move_history_feedback_bar.dart`](../../lib/features/game/presentation/widgets/move_history_feedback_bar.dart) — `MoveHistoryAndFeedbackBar` (the SAN move-chip strip + classification badges), `classificationColor(MoveClassification)`. Moved here from the old monolithic `chess_feature_widgets.dart` by the Phase 1 widget-file-split refactor (`docs/features/done/refactor_01_widget_file_split.md`).
- [`lib/features/game/presentation/widgets/eval_bar_and_graph.dart`](../../lib/features/game/presentation/widgets/eval_bar_and_graph.dart) — `EvalBar`/`EvalGraph` are the live-eval display; see `docs/features/done/move_timeline_eval_bar.md` for that feature's own doc (it's the one actually built against this file).

## Reverse-Engineered Mechanics

### 1. Move Classification Tiers & Brand Colors (`XE`, `Bx`, `cy`)
From `quick-analysis-tallies` (`XE`) and color tokens (`cy` / `Wb` / `Bx`):
- **11 Tallied Categories in JS (`XE`):**
  - `brilliant` (`#1baca6` — teal)
  - `greatfind` (`#5c8bb0` — steel blue)
  - `best` (green)
  - `excellent` (light green)
  - `good` (muted green-grey)
  - `book` (`#a88865` — warm brown)
  - `forced`
  - `inaccuracy` (`#f7c045` — yellow)
  - `mistake` (`#e58f2a` — orange)
  - `missedwin`
  - `blunder` (`#ca3431` — red)
- **Centipawn Loss Mapping in Flutter (`_classifyCpLoss`):**
  - Book moves during opening plies → `MoveFeedbackType.book`
  - `cpLoss <= -120` → `MoveFeedbackType.brilliant` (`!!`)
  - `cpLoss <= -50` → `MoveFeedbackType.greatFind` (`!`)
  - `cpLoss <= 15` → `MoveFeedbackType.best` (`★`)
  - `cpLoss <= 40` → `MoveFeedbackType.excellent` (`👍`)
  - `cpLoss <= 90` → `MoveFeedbackType.good` (`✓`)
  - `cpLoss <= 180` → `MoveFeedbackType.inaccuracy` (`?!`)
  - `cpLoss <= 300` → `MoveFeedbackType.mistake` (`?`)
  - `cpLoss > 300` → `MoveFeedbackType.blunder` (`??` — intercepted by Anti-Blunder Shield when enabled)

### 2. Evaluation Score Formatting & Perspective (`Kb(e, t)`, `score-text`)
```js
function Kb(e, t = false) {
  return t || e.charAt(0) === "-" || e === "0-1";
}
```
- Determines whether the evaluation pill should render with dark/negative styling (`#403d39` `blackWinning` background with light text vs. `#FFF` background with dark text) when Black is ahead (`evalCp < 0` or `0-1`) or when inverted.
- Analysis constants (`uw` / `dw`):
  - `CLASSIFICATION_ICON_SIZE: 12`
  - `DEFAULT_ARROW_COLOR: "rgba(150, 190, 70, 0.95)"` (`#96be46`)
  - `SQUARE_OPACITY_COLORED: 0.8`, `SQUARE_OPACITY_DEFAULT: 0.5`
  - `DEEP_ANALYSIS_DEPTH: 22`

### 3. Figurine & SAN Move Parsing (`tA(e)`, `rA(e)`, `move-san`)
```js
function tA(e) {
  return e.san.search(/[BKNRQ]/);
}
function rA(e) {
  return {
    from: e.substring(0, 2),
    to: e.substring(2, 4),
  };
}
```
- `tA(e)` locates the piece letter (`B`, `K`, `N`, `R`, `Q`) in a Standard Algebraic Notation string so the UI can replace or prefix it with a figurine icon (`move-san-figurine`).
- `rA(e)` splits a 4-character LAN/UCI move string (e.g., `"e2e4"`) into `{ from: "e2", to: "e4" }`.

### 4. ECO Opening Recognition (`eco-opening-panel` / `Jk`)
- Displays the recognized opening name (`eco-opening-name`) and variation (`eco-opening-variant`) in a compact header bar above the move list as moves are played.
