# Feature: Chess.com Board & Piece Theme Registry (`@chesscom/chessboard v1.189.0`)

**Status:** Extracted Reference — ready to plug into [`lib/core/widgets/chess_board/board_theme.dart`](../../lib/core/widgets/chess_board/board_theme.dart).

## Overview

Extracted from `@chesscom/chessboard` (`Un = "1.189.0"`). Contains Chess.com's complete dictionary of **43 board color/texture themes (`ta`)**, **40 piece sets (`na`)**, coordinate label ordering (`pne`), and board layout mode classes (`Ut`).

---

## 1. All 43 Board Themes (`ta` / `fre(themeName)`)

Each entry in `ta` is a 5-tuple:
`[darkSquareColor, lightSquareColor, textureName, fileExtension, highlightColor]`

| Theme Key | Dark Square | Light Square | Highlight Color | Texture Asset |
| :--- | :--- | :--- | :--- | :--- |
| `default` / `green` | `#779952` | `#edeed1` | `#ffff00` | `green.png` |
| `brown` | `#B58863` | `#F0D9B5` | `#ffff00` | `brown.png` |
| `blue` | `#4D6D92` | `#ECECD7` | `#00a5ff` | `blue.png` |
| `8_bit` | `#6a9b41` | `#f3f3f4` | `#ffff00` | `8_bit.png` |
| `bases` | `#c26b38` | `#efcca1` | `#f5cc2a` | `bases.jpg` |
| `blackwhite` / `translucent` | `#667188` | `#282f3f` | `#5b91b3` | `translucent.png` |
| `bubblegum` / `pink` | `#f9cdd3` | `#fff3f3` | `#de5d6f` | `bubblegum.png` |
| `burled_wood` / `wooddark` | `#895132` | `#d9b088` | `#ee9016` | `burled_wood.jpg` |
| `checkers` | `#e3a6a9` | `#999999` | `#fae18a` | `checkers.jpg` |
| `dark_wood` / `wood` / `woodmid` | `#8d675e` | `#e7cdb2` | `#cc9122` | `dark_wood.jpg` |
| `dash` | `#6b3a27` | `#bd9257` | `#eca722` | `dash.jpg` |
| `glass` | `#282f3f` | `#667188` | `#5b91b3` | `glass.png` |
| `graffiti` / `marblebrown` | `#b96f18` | `#aeaeae` | `#f39011` | `graffiti.jpg` |
| `grey` / `light` | `#aaaaaa` | `#dcdcdc` | `#a4b8c4` | `light.png` |
| `icy_sea` | `#7a9db2` | `#c5d5dc` | `#5ed7f1` | `icy_sea.jpg` |
| `lolz` | `#909898` | `#e0e9e9` | `#a3becd` | `lolz.jpg` |
| `marble` | `#706b66` | `#c7bdaa` | `#f0db86` | `marble.jpg` |
| `metal` | `#6e6e6e` | `#c9c9c9` | `#a3becd` | `metal.jpg` |
| `natural` | `#D08B18` | `#FCE4B2` | `#f0e464` | `tan.png` |
| `nature` | `#8c976e` | `#c3d1a4` | `#eef396` | `translucent.png` |
| `neon` | `#636363` | `#b9b9b9` | `#6d90a6` | `neon.png` |
| `newspaper` | `#5a5956` | `#5a5956` | `#99976e` | `newspaper.jpg` |
| `orange` | `#D08B18` | `#FCE4B2` | `#ffff00` | `orange.png` |
| `overlay` | `#789ebd` | `#4878a0` | `#0d9acf` | `overlay.png` |
| `parchment` / `woodlight` | `#B58863` | `#F0D9B5` | `#d8cc66` | `parchment.jpg` |
| `purple` | `#8877B7` | `#EFEFEF` | `#7dacc9` | `purple.png` |
| `red` | `#BA5546` | `#F0D8BF` | `#f8f893` | `red.png` |
| `sand` | `#b8a590` | `#e5d3c4` | `#e2bc87` | `sand.jpg` |
| `sky` | `#c2d7e2` | `#efefef` | `#65daf7` | `sky.png` |
| `stone` | `#666463` | `#c8c3bd` | `#36525f` | `stone.jpg` |
| `tan` | `#D08B18` | `#FCE4B2` | `#f7d84a` | `tan.png` |
| `tournament` / `winboard` | `#316549` | `#ebece8` | `#a4c25b` | `tournament.jpg` |
| `walnut` | `#835f42` | `#c0a684` | `#d1a52d` | `walnut.jpg` |

---

## 2. All 40 Piece Sets (`na`)

- **Pseudo-3D Piece Sets (`isPseudo3d: true`):**
  - `3d_staunton` (`path: "3d_staunton"`)
  - `3dchesskid` (`path: "3d_chesskid"`)
  - `3dplastic` (`path: "3d_plastic"`)
  - `3dwood` (`path: "3d_wood"`)
- **2D / Standard Piece Sets (`format: "png"`):**
  - `neo` (also used as fallback for `real3d`), `neo_wood`, `wood`, `glass`, `gothic`, `classic`, `metal`, `bases`, `club`, `ocean`, `newspaper`, `space`, `cases`, `condal`, `3d_chesskid`, `8_bit`, `marble`, `book`, `alpha`, `luca`, `maya`, `modern2` (`path: "modern"`), `nature`, `neon`, `sky`, `graffiti`, `icy_sea`, `light`, `lolz`, `tigers`, `tournament`, `vintage`, `bubblegum`, `dash`, `game_room`, `blindfold`.

---

## 3. Coordinate Labels & Square Color Parity (`pne`, `Zne`, `Gn`, `Wr`)

- **Coordinate Array (`pne(isFlipped)`):**
  ```js
  function pne(isFlipped) {
    let coords = ["8","7","6","5","4","3","2","1","a","b","c","d","e","f","g","h"];
    return isFlipped
      ? [...coords.slice(0, 8).reverse(), ...coords.slice(-8).reverse()]
      : coords;
  }
  ```
- **Algebraic Square <-> File/Rank Conversion (`Gn`, `Wr`):**
  - `Gn("e4")` → `{ file: "e".charCodeAt(0) - 96, rank: 4 }` (`1..8`).
  - `Wr({ file, rank })` → `${String.fromCharCode(96 + file)}${rank}` (returns `null` if out of `1..8`).
- **Light/Dark Square Check (`Zne(file, rank)`):**
  - `(file + rank) % 2 !== 1` (even sum = dark square, odd sum = light square in 1-indexed coordinates).

---

## 4. Board Layout Mode Classes (`Ut`)

Used on the root layout container to toggle board presentation modes:
- `cls-board` (legacy JS-snapped 8px board width)
- `double-board` (side-by-side boards, e.g. Bughouse / analysis comparison)
- `outside-coords` (coordinates rendered outside the 8×8 grid)
- `pseudo-3d` / `real-3d` (WebGL or isometric piece rendering)
- `theatre-mode`
- `with-analysis` / `with-analysis-collapsed`
- `with-evaluation` / `with-visible-evaluation`
