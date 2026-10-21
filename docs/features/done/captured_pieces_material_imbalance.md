# Feature: Captured Pieces & Material Imbalance Row

**Status:** Built — this doc's own "Extracted / Planned" was stale.
`SideMaterial`/`GameState.materialFor` (`lib/features/game/presentation/providers/game_provider.dart`)
implement exactly the captured-pieces + imbalance-badge math described
below, and are rendered inline inside
`lib/features/game/presentation/widgets/player_bar.dart` (`material.capturedPieces`) —
there's no dedicated `CapturedPiecesRow` widget as §"Proposed Flutter
Implementation" suggested; the rendering was folded directly into the
existing player-bar widget instead of being factored out separately.

## Overview

In Chess.com's `play-computer` bundle, each player bar (`player-row-component`) renders a `captured-pieces` (`OR`) component next to the player's name/avatar. It displays compact icons for all opponent pieces captured by that player, sorted by piece value, with pawns grouped into pairs in vertical mode, followed by a `+N` material advantage score badge on whichever side is ahead in material.

## Reverse-Engineered Logic (`ER` & `OR`)

### 1. Piece Value Sort Order (`Xk`, `Zk`)
```js
Xk = {
  p: "pawn",
  n: "knight",
  b: "bishop",
  r: "rook",
  q: "queen",
};
Zk = {
  p: 1,
  b: 2,
  n: 3,
  r: 4,
  q: 5,
};
```
- Note that while Bishops and Knights are both worth 3 points in material calculation, Chess.com sorts captured piece sprites in the order: **Pawn (`1`) → Bishop (`2`) → Knight (`3`) → Rook (`4`) → Queen (`5`)**.
- **Our actual Flutter order is the reverse of this**: `materialFor`'s
  capture loop iterates `['q', 'r', 'b', 'n', 'p']` — Queen, Rook, Bishop,
  Knight, Pawn — and `player_bar.dart` renders `capturedPieces` in
  whatever order the list was built, so highest-value-first, not
  lowest-value-first like Chess.com. Nobody has asked for this to match
  Chess.com's order; flagging it here only so this doc doesn't mislead
  about which order to expect on screen.
- **Pawn-pair grouping is not implemented.** Every captured piece —
  pawns included — renders as its own individual icon in a plain `Wrap`;
  there's no `CR`-style splitting of pawns into groups of 2.

### 2. Sprite Class Generation (`TR`, `wR`, `CR`, `SR`)
```js
yR = (color) => `cpiece ${color}-`;
bR = (piece) => Xk[piece];
xR = (count, piece) => `${count}-${Xk[piece]}s`;
SR = (piece, color, count) =>
  yR(color) + (count === 1 ? bR(piece) : xR(count, piece));
```
- For horizontal player bars (`verticalLayout == false`), multiple captured pieces of the same type are rendered as a single overlapping combined sprite class (e.g., `captured-pieces-w-3-pawns`, `captured-pieces-b-2-rooks`).
- For vertical layouts (`verticalLayout == true`), `CR` splits captured pawns into groups of 2 plus a remainder of 1 (`Math.floor(count / 2)` pairs + `count % 2` single pawn).

### 3. Material Advantage Badge (`a`)
```js
a = computed(() => {
  if (
    props.material.imbalance &&
    !(
      (props.color === "w" && props.material.imbalance <= 0) ||
      (props.color === "b" && props.material.imbalance >= 0)
    )
  ) {
    return `+${Math.abs(props.material.imbalance)}`;
  }
});
```
- `imbalance` is calculated as `whiteMaterial - blackMaterial` (using standard values `P=1, B=3, N=3, R=5, Q=9`).
- If `imbalance > 0`, White's row displays `+{imbalance}` and Black's row displays nothing.
- If `imbalance < 0`, Black's row displays `+{abs(imbalance)}` and White's row displays nothing.
- If `imbalance == 0`, neither row shows a numeric badge.

## Proposed Flutter Implementation

1. Add a pure helper `MaterialSummary.fromFen(String fen)` in `lib/features/game/domain/entities/` that counts remaining pieces on the board, subtracts from the standard starting counts (`8P, 2B, 2N, 2R, 1Q`), and computes:
   - `capturedByWhite`: `Map<String, int>` (black pieces missing from the board)
   - `capturedByBlack`: `Map<String, int>` (white pieces missing from the board)
   - `imbalance`: `int` (White total piece value minus Black total piece value)
2. Add a `CapturedPiecesRow` widget in `lib/features/game/presentation/widgets/chess_feature_widgets.dart` and embed it inside `_BotPanel` and `_PlayerBar` in `lib/features/game/presentation/pages/game_page.dart`.
