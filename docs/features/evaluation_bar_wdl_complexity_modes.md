# Evaluation Bar: Centipawn, WDL Probability & Complexity Modes

**Status:** Not built — this is Chess.com reference material only. The
real `EvalBar` (`lib/features/game/presentation/widgets/eval_bar_and_graph.dart`,
`docs/features/done/move_timeline_eval_bar.md`) uses a different formula than
§5's blueprint below: a win-probability sigmoid
(`GameReviewAnalyzer.winPercentFromWhiteCp`), not the `SCORE_CAP = 4` /
`50 ± 45%` linear mapping. There is no WDL bar, no complexity bar, and no
tap-to-toggle-mode — confirmed via `grep -rln "wdl\|complexity"
lib/features/game/presentation/` returning no matches. §5's "Flutter
Implementation Blueprint" was never acted on.

Extracted from Chess.com's `play-computer` (`evaluation-bar.b2490faa.Dr9JiXampD.chunk.js`) and `analysis` (`evaluation-bar.b2490faa.CQzut5s1Dc.chunk.js`, `shared.36dcc507.CzVEG7o6cj.chunk.js`, and `evaluation-bar.Dw4H_kZZAR.css`) bundles.

---

## 1. Architecture Overview (`EvaluationBarController`)

Chess.com's `EvaluationBarController` dynamically switches between **four** visual states depending on engine progress and user settings (`analysis_eval_bar_modes`):

1. **`EvaluationLoader`** (`loadProgress < 1`): Animated vertical progress bar shown while Game Review is evaluating the game.
2. **`wc-evaluation-bar`** (`Gn`): Standard centipawn / mate / tablebase evaluation bar.
3. **`wc-wdl-bar`** (`Yn`): 3-segment Win / Draw / Loss probability bar (`White %`, `Draw %`, `Black %`).
4. **`wc-complexity-bar`** (`Un`): Position sharpness/complexity bar (`0–100`) with a gradient fill.

Clicking any of the three active bars toggles between the standard Evaluation Bar and the alternate modes.

---

## 2. Standard Centipawn Evaluation Bar (`wc-evaluation-bar`)

### Constants (`shared.36dcc507.CzVEG7o6cj.chunk.js`)
```javascript
const EVAL_BAR_CONSTANTS = {
  BAR_MARGIN: 10,
  BAR_WIDTH: 20,
  DEFAULT_BAR_PERCENTAGE: 50,
  DEFAULT_LOADING_COLOR: '#769656',
  SCORE_CALC_COEFFICIENT: 45,
  SCORE_CAP: 4, // +/- 4.00 pawns caps the visual bar at 95% / 5%
};
```

### Bar Fill Percentage Formula (`v(evalLine)`)
Unlike a naive linear `0..10` pawn scale, Chess.com caps the visual bar at **$\pm 4.00$ pawns** (`SCORE_CAP = 4`) and maps that range to **$5\% \dots 95\%$** (`50 ± 45%`), reserving $0\%$ and $100\%$ strictly for forced **Mate** or **Tablebase Win/Loss**:

```javascript
function clampScore(score = 0) {
  if (score !== null) {
    if (score > 4) return 4;
    if (score < -4) return -4;
  }
  return score;
}

function getBarPercentage(line = {}) {
  const clamped = clampScore(line?.score ?? null);

  // 1. Forced Mate: 100% for White mate, 0% for Black mate
  if (typeof line.mateIn === 'number') {
    return clamped !== null && clamped > 0 ? 100 : 0;
  }

  // 2. Endgame Tablebase Outcome
  if (line.tablebaseOutcome) {
    if (line.tablebaseOutcome === '1-0') return 100;
    if (line.tablebaseOutcome === '0-1') return 0;
    return 50;
  }

  // 3. Centipawn Score (in pawns, e.g. +1.5)
  if (clamped !== null && clamped > 0) {
    return (clamped * 45) / 4 + 50; // Range: 50% .. 95%
  }
  if (clamped !== null && clamped < 0) {
    return 50 - (Math.abs(clamped) * 45) / 4; // Range: 5% .. 50%
  }

  return 50;
}
```

### Abbreviated vs. Hover Score Formatting
* **Abbreviated Label (`i(line)` — shown inside the narrow 20px bar):**
  * Checkmate on board (`mateIn === 0`): `'1-0'` or `'0-1'`
  * Stalemate (`line.stalemate`): `'½'`
  * Mate in $N$ (`typeof line.mateIn === 'number'`): `'M' + Math.abs(line.mateIn)` (e.g., `'M3'`)
  * Tablebase (`line.tablebaseOutcome`): `'TB'`
  * Centipawn score (`r(score)`):
    * Uses absolute value (no `+` or `-` sign; color/position indicates side).
    * If `|score| < 10`: 1 decimal place (e.g., `'0.0'`, `'1.4'`, `'9.8'`).
    * If `|score| >= 10`: integer floor (e.g., `'12'`).
* **Hover Tooltip Label (`y(line)` — shown on hover with engine name & depth):**
  * Includes explicit `+`/`-` sign and up to 2 decimal places (`+1.45`), plus `engineName` (e.g., `Stockfish 19 Lite`) and `Depth=18`.

### Critical Position Indicator (`!`)
When `isCriticalPosition` is true on the current evaluation node, the bar injects the **Great Find (`!`)** SVG icon (`size="14"`, `#5c8bb0`) at the boundary between the White and Black fills (`translate3d(0, ${100 - barPercentage}%, 0)`).

### Tablebase Draw Split Animation
When `tablebaseOutcome === '1/2-1/2'`, `showTablebaseDraw()` transitions both bars with `transition-duration: 0.5s`:
* White bar: `translate3d(0, 50%, 0)`
* Black bar: `translate3d(0, -50%, 0)`
This exposes the middle `.evaluation-bar-draw` (`#777574` medium grey) band.

---

## 3. WDL (Win / Draw / Loss) Probability Bar (`wc-wdl-bar`)

When `analysis_eval_bar_modes` and `isWdlBarEnabled()` are active, `wc-wdl-bar` renders three stacked probability segments from `{ win, draw, loss }` (each `0.0 .. 1.0`):

* **White Win Fill (`[data-win-bar]`):**
  `transform: translate3d(0, ${(1 - wdl.win) * 100}%, 0)`
* **Black Win Fill (`[data-loss-bar]`):**
  `transform: translate3d(0, ${(wdl.loss - 1) * 100}%, 0)`
* **Draw Fill:** Remains visible in the middle between the White and Black fills.
* **Label Visibility Threshold:**
  A segment's vertical percentage label (`"${pct}\n%"`) is only rendered if `pct > 8 && pct <= 100` so text never overflows tiny slices.
* **Hover Popover Table:**
  Displays a 4-row breakdown on hover:
  * `White: XX%`
  * `Draw: XX%`
  * `Black: XX%`
  * `Eval: +X.XX`

---

## 4. Position Complexity Bar (`wc-complexity-bar`)

Displays `positionComplexity` (`0..100`) using a vertical heat gradient (`.evaluation-bar-gradient`) masked by a top-down dark bar:
```javascript
this.barElement.style.transform = `translate3d(0, -${this.barPercentage}%, 0)`;
this.scoreElement.textContent = `${positionComplexity}`;
```

---

## 5. Flutter Implementation Blueprint

To upgrade our Flutter `EvalBarWidget` to match Chess.com's exact specification:
1. Replace linear clamping with the **4-pawn `SCORE_CAP` formula** (`50 + (score.clamp(-4.0, 4.0) * 45 / 4.0)`), reserving `0%` and `100%` for forced mate.
2. Format narrow bar labels without signs (`|score| < 10 ? score.abs().toStringAsFixed(1) : score.abs().floor().toString()`), placing White's label at the bottom in dark text (`#403d39`) when `score >= 0` and at the top in light text (`#ffffff`) when `score < 0`.
3. Support tapping the bar to toggle between **Centipawn Eval** and **WDL Win Probability** (using the standard Stockfish WDL model `1 / (1 + exp(-cp / 400))`).
