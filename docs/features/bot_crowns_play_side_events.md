# Feature: Bot Categories, 3-Crown Progress, Play-Side Selector & Odds/Handicap Games

**Status:** Play-Side Selector, Bot Categories, and 3-Crown display are **Built**. Live Bot Events, Odds/Handicap FENs, and Ambient Bot Audio are **Extracted / Reference**.

## Overview

Reverse-engineered from Chess.com's `play-side-selector` (`hy`), `bot-group-accordion` (`DA`), `bot-component` (`$A`), engine rating mapper (`ab`), odds-game variation mapper (`HI`), and ambient audio controller (`rL`, `PI`).

## Key Files in Flutter App

- [`lib/features/game/domain/entities/bot_personality.dart`](../../lib/features/game/domain/entities/bot_personality.dart) — `BotCategory` and `defaultCroissantBots`
- [`lib/features/game/presentation/providers/game_provider.dart`](../../lib/features/game/presentation/providers/game_provider.dart) — `PlaySide` (`white`, `random`, `black`), `botCrowns`, and `selectPlaySide`
- [`lib/features/game/presentation/widgets/chess_feature_widgets.dart`](../../lib/features/game/presentation/widgets/chess_feature_widgets.dart) — `PlaySideSelectorWidget`, `BotCrownsWidget`

## Reverse-Engineered Mechanics

### 1. Play-Side Selector (`play-side-selector` / `RO()`)
- Allows the user to choose **White**, **Random (`?`)**, or **Black** before starting a game.
- When Random is selected, `RO()` (`Math.floor(Math.random() * 2 + 1)`) picks White or Black at game start, flips the board orientation accordingly, and if the user is Black, immediately triggers the bot's opening move (`_playBotReply()`).

### 2. Bot Crowns (`bot-crowns` / `ZA`) & Assistance Levels
- Each bot displays up to **3 crowns** (`BotCrownsWidget`) representing how little assistance was used when defeating the bot:
  - **3 Crowns:** Won with Anti-Blunder Shield OFF (no takebacks/assistance).
  - **2 Crowns:** Won with Anti-Blunder Shield ON (assisted play).
  - **0 Crowns:** Not yet defeated.

### 3. Engine Skill Tier Rating Mapper (`ab(e)`)
```js
function ab(e) {
  let t = e.filter((e) => e.classification === "engine");
  return [1, 6, 12, 16, 20, 25].reduce(
    (e, n) => ((e[n] = t[n - 1].rating), e),
    {}
  );
}
```
- Maps the 25 discrete engine slider levels into 6 major skill tier buckets (`1`, `6`, `12`, `16`, `20`, `25`) for the "Simple Skill Tier List" (`coach-simple-skill-tier-list-component`).

### 4. Bot Difficulty Variations & Odds/Handicap FENs (`HI(e)`, `tM(e)`)
```js
function HI(e) {
  if (e.botLabel === undefined) return;
  let t = { variationLabel: e.botLabel };
  if (e.fenPlayerIsWhite || e.fenPlayerIsBlack) {
    t[Fm.oddsGameVariation] = {
      playerWhiteFen: e.fenPlayerIsWhite,
      playerBlackFen: e.fenPlayerIsBlack,
    };
  }
  return t;
}
```
- Bots in special events can have a `difficultyVariationConfig` (`bot-difficulty-variation-label-easier` / `harder`) that overrides the starting FEN with an **odds/handicap position** (`playerWhiteFen` when the human plays White, `playerBlackFen` when the human plays Black).

### 5. Ambient Gameplay Audio & Visibility Auto-Pause (`rL()`, `PI()`, `Kj = 0.35`)
- Selected bots can define `sounds.gameplayAmbient.url` and `sounds.gameStart.url`.
- `ZI(url)` loops the ambient track and fades its volume to `Kj = 0.35` over `50ms`.
- `PI()` listens to `document.addEventListener("visibilitychange", ...)` so that switching browser tabs or minimizing the window automatically pauses the ambient loop (`wasPlayingBeforeHidden = true`) and fades it back in (`fadeTo(0.35, 50)`) when returning.
