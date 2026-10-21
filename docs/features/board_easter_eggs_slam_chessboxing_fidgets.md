# Interactive Board Easter Eggs: Fist Slam, Chessboxing & Piece Fidgets

Extracted from `add-chessboard-slam-animation.b44146bc.B9yh_UUK5u.chunk.js` and `play-computer/2026.10.3/shared.eager.ZDyFHQYc7g.chunk.js` (`zke`, `Hke`, `Wke`, `Kke`, `Xke`, `ZOe`, and `VSe`).

---

## 1. Fist Smash / Board Slam (`board-slam-animation`)

Pressing the **`f`** key during a game triggers a Rive fist-smash animation that slams the chessboard and scatters every piece in the air.

### Trigger & Throttling (`j` / `P` / `L`)
* **Hotkey Condition:** `e.key === 'f' && !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey`
* **Throttle:** `F = 1200ms` with `{ edges: ['leading'] }` so spamming `f` cannot overlap Rive canvases.
* **Impact Delay:** `I = 133ms` after the Rive animation `'Fist_smash'` begins (`fist_smash_opt.CrmVH5PFz4.riv`), the board shake/scatter fires.

### Sequence of Events (`E(api)` & `zke`)
1. Creates a full-board overlay `<canvas class="board-slam-animation">` (`position: absolute; inset: 0; pointer-events: none; z-index: 1000;`) inside `#board-layout-chessboard`.
2. Plays the `'Fist_smash'` Rive animation and `/bundles/web/sounds/slam-animation.mp3` (auto-unloaded after `1200ms`).
3. At `t = 133ms`, calls `api.boardSlam.triggerSlam()`:
   * Adds `.hide-pieces` to the chessboard DOM element so the normal static pieces are hidden.
   * Iterates over every piece on the board (`Object.entries(renderer.getPieces())`) and spawns a `piece-jump` VFX element on its square:
     ```javascript
     api.vfx.add({
       type: 'piece-jump',
       square,
       data: { piece: `${colorChar}${pieceType}` },
     });
     ```
   * If `triggerSlam()` is called again while pieces are already displaced (`t.length > 0`), it calls `api.vfx.update(vfxKey)` on each existing VFX element so the pieces bounce again.
4. Any subsequent mouse click or pointer down (`MousedownLeft`, `MousedownRight`, `PointerdownLeft`, `PointerdownRight`) calls `resetBoard()`, removing `.hide-pieces` and clearing all `piece-jump` VFX elements.

---

## 2. Chessboxing Mode (`ZOe` — `chessboxing_hotkey`)

When the `chessboxing_hotkey` feature is enabled, holding down the **`b`** key turns the cursor into a physics-driven **Boxing Glove** that punches chess pieces across the board!

### Configuration Constants (`nk`)
```javascript
const CHESSBOXING_DEFAULTS = {
  keyToActivate: 'b',
  minPunchVelocity: 0.12,        // px/ms threshold to register a punch
  minPunchDistanceSquares: 1,    // minimum knockback distance (in squares)
  maxPunchDistanceSquares: 9,    // maximum knockback distance (in squares)
  gloveScale: 1.3,               // 1.3x square size
  distanceMultiplier: 100,
  imageRotationDeg: 90,          // sprite orientation offset
  disablePieceReset: false,
  opponentOnly: false,
  punchSoundUrls: [],
};
const PUNCH_RECOIL_MS = 180;     // rk = 180
const HIT_STARS_DURATION_MS = 320; // ik = 320
const ANGLE_SMOOTHING_ALPHA = 0.2; // ak = 0.2
```

### Velocity & Angular Smoothing Math (`ee` / `ike` / `ake`)
On every `pointermove` while `b` is held:
1. **Velocity Vector:**
   $$\Delta t = \max(1, t - t_{\text{prev}}), \quad v_x = \frac{x - x_{\text{prev}}}{\Delta t}, \quad v_y = \frac{y - y_{\text{prev}}}{\Delta t}, \quad \text{speed} = \sqrt{v_x^2 + v_y^2}$$
2. **Shortest-Arc Rotation Interpolation:**
   $$\theta_{\text{target}} = \text{atan2}(v_y, v_x) \cdot \frac{180}{\pi} + 90^\circ$$
   $$\theta_{\text{next}} = \theta + \left(\left((\theta_{\text{target}} - \theta) \bmod 360 + 540\right) \bmod 360 - 180\right) \cdot 0.2$$
3. **Collision & Knockback (`D`):**
   If `speed >= 0.12` and `document.elementFromPoint(clientX, clientY)` hits a `.piece`:
   * Normalizes direction: $\hat{u}_x = v_x / \text{speed}, \quad \hat{u}_y = v_y / \text{speed}$
   * Computes knockback distance in squares:
     $$d_{\text{squares}} = \text{clamp}\left(\text{round}\left(\frac{\text{speed}}{\text{squareSize}} \cdot 100\right), 1, 9\right)$$
   * Spawns `PieceThrow` VFX (`throwX = ux * d_squares * 100`, `throwY = uy * d_squares * 100`, `throwDuration: 600ms`).
4. **3 Radial Hit Stars (`nke`):**
   Spawns `<div class="boxing-glove-stars">` with 3 `<span class="boxing-glove-star">` elements fanning out in a $60^\circ$ ($\pi/3$) cone (`offsets = [-0.5, 0, 0.5]` with $\pm 8\%$ random jitter) at radial distances of **`36px`**, **`63px`**, and **`90px`** (`36 + (i / 2) * 54`) for `320ms`.

---

## 3. Piece Fidget Animations (`chessboard_enable_piece_fidget`)

To keep players entertained while waiting or thinking, two piece-fidget plugins are attached in `Playing` mode:

### A. Own-Piece Kickflip (`Wke` — `own-piece-fidget`)
* **When active:** Only while waiting for the opponent's turn (`playingAs !== getTurn()`).
* **Trigger:** Triple-clicking (`n === 3`) one of your **own** pieces on the same square with less than `500ms` (`xk = 500`) between clicks.
* **Effect:** Spawns `ib.VFXType.PieceFlip` (`piece-flip-scale` CSS animation), temporarily hiding the static piece and flipping a clone in 3D/scale space before restoring it on `animationend`.

### B. Opponent-Piece Charge Jump (`Kke` — `opponent-piece-fidget`)
* **When active:** During your own turn (`playingAs === getTurn()`), when clicking and holding an **opponent's** piece.
* **Trigger & Physics (`RSe` / `zSe` / `LSe`):**
  1. Holding pointer down for `500ms` (`Sk = 500`) without dragging off the square starts `ib.VFXType.ChargeJump`, which squishes the piece vertically via CSS animation `charge-jump-scale` down toward `Ew = 0.6` (`60%` height).
  2. When the user releases the mouse button (`Pointerup`), `zSe` reads the current vertical `scale` factor `r` (`0.6 .. 1.0`) from `getComputedStyle(el).scale` and maps it linearly to a jump height between **`20%` (`Dw`)** and **`150%` (`Ow`)** of a square:
     $$t = \min\left(\frac{1 - r}{1 - 0.6}, 1\right), \quad \text{jumpHeightPercent} = 20 + t \cdot (150 - 20)$$
  3. Sets `--start-compression: ${r}` and `--jump-height: -${jumpHeightPercent}%` and adds `.jumping`.

---

## 4. Hand Piece Yeet (`Xke` — `piece-throw`)

* **Trigger:** Pressing the **`t`** key while hovering the cursor over any `.piece:hover` on the board.
* **Effect:**
  1. Spawns `HandThrow` VFX (`/bundles/web/images/hand-strokeless.svg`):
     * `appearDurationMs: 500`
     * `throwDurationMs: 200`
     * `fadeDurationMs: 800`
     * `throwScaleX: 2, throwScaleY: 2, throwDyPercent: -100`
  2. Spawns `PieceThrow` VFX on the hovered piece (`delay: 500ms`, `throwDuration: 1500ms`) so the piece flies off the board right as the hand flicks upward.

---

## 5. Complete 13-Type VFX Layer Registry (`VSe`)

Chess.com's board DOM separates visual effects into two z-index planes relative to the `.pieces` layer (`Zb.VFXBelow` vs. `Zb.VFXAbove`):

| VFX Type (`ib.VFXType`) | Builder | Update Hook | Z-Plane (`jw`) | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `piece-capture` | `Gre` | — | `VFXBelow` | Captured piece fade-out (`capture-fade`) |
| `piece-jump` | `hSe` | `gSe` | `VFXAbove` | Board slam scatter / jump physics |
| `piece-throw` | `bSe` | — | `VFXAbove` | Flying piece trajectory (`t` key or Chessboxing punch) |
| `hand-throw` | `ite` | — | `VFXAbove` | Giant hand swooping in (`hand-strokeless.svg`) |
| `king-check-square` | `wSe` | — | `VFXBelow` | Red square pulse under checked King |
| `king-check` | `ESe` | — | `VFXAbove` | Checked King shake/alert overlay |
| `piece-trail` | `kSe` | — | `VFXBelow` | Motion trail behind dynamic piece movement |
| `illegal-move-tap` | `vte` | — | `VFXBelow` | Red flash when tapping an illegal destination |
| `growing-circle` | `Dne` | — | `VFXBelow` | Expanding ripple ring on square selection |
| `piece-flip` | `PSe` | — | `VFXAbove` | Triple-click piece kickflip (`piece-flip-scale`) |
| `piece-promote` | `mSe` | — | `VFXAbove` | Pawn promotion celebratory pop |
| `promote-ripple` | `Qie` | — | `VFXBelow` | Shockwave beneath promoted piece |
| `charge-jump` | `RSe` | `zSe` | `VFXAbove` | Hold-and-release squish jump (`20%..150%` height) |
