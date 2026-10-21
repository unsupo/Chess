# Game Over Modal, Animated Tallies, 7 `GameArc` Narratives & 45 Loading Trivia

Extracted from `play-computer/2026.10.3/game-over-modal.036cfe54.BAld2d4IjE.chunk.js` and `analysis/2026.10.3-hotfix.20ef972/shared.39e302ce.BtipyrXOdp.chunk.js`.

---

## 1. Quick-Analysis Animated Move Tally (`quick-analysis-animated-tally`)

When a game finishes, the Game Over Modal runs a fast local engine pass (`quickAnalysisProgress` `0.0 .. 1.0`) and displays the top **3 highlight move classifications** (`v` via `Au` in `game-over-modal.js`).

### 1. Slot-Machine Icon Loader (`s.value` at `200ms`)
While `quickAnalysisProgress < 1` (or during the minimum `2000ms` loader hold), 3 placeholder slots cycle through the 11 classification icons (`Brilliant`, `GreatFind`, `Tricky`, `BestMove`, `Excellent`, `Miss`, `Blunder`, `Mistake`, `Good`, `Book`, `Inaccuracy`) every **`200ms`**:
```javascript
useIntervalFn(() => {
  slotIndices.value = slotIndices.value.map((idx) => (idx + 1) % allClassifications.length);
}, 200);
```

### 2. Staggered Reveal, Rive Sparkles & 600ms Count-Up (`ce`)
Once analysis completes:
* **Staggered Reveal (`200ms` per column):** Reveals slot `0`, `1`, `2` at `200ms` intervals.
* **Circle Pop (`250ms` delay):** Triggers `.quick-analysis-animated-tally-tallyCircleVisible` scale/fade animation.
* **Rive Sparkles (`350ms` delay):** If the revealed slot is **`brilliant`**, **`greatFind`**, or **`tricky`**, mounts a `<canvas>` inside `.quick-analysis-animated-tally-sparkles` and plays `ui-sparkles.BIn0OQeD8I.riv`.
* **600ms Count-Up (`ce(slotIndex, targetCount)`):**
  ```javascript
  function animateTallyCount(slotIndex, targetCount) {
    displayedCounts.value[slotIndex] = 0;
    const startTime = Date.now();
    const tick = () => {
      const elapsed = Date.now() - startTime;
      if (elapsed < 600) {
        displayedCounts.value[slotIndex] = Math.round((elapsed / 600) * targetCount);
        requestAnimationFrame(tick);
      } else {
        displayedCounts.value[slotIndex] = targetCount;
      }
    };
    requestAnimationFrame(tick);
  }
  ```

### 3. Asynchronous Brilliant Move Verification (`VerifyBrilliantsService`)
Because shallow quick-analysis can occasionally false-positive a sacrifice as `Brilliant`, Chess.com sends candidate move indices to `/service/ceac` (`chesscom.ceac.v1alpha.BrilliantVerificationService/VerifyBrilliants`).
* While `isBrilliantVerificationPending` is true, the Brilliant slot continues spinning its icon loader (`ee.value === true`), and once verified, displays a tooltip: `"May change during Game Review."`

---

## 2. Bezier Number Counter & Flying Bonus Chip (`animated-number-bezier` & `event-bonus-chip`)

* **`animated-number-bezier` (`pd`):**
  Animates score deltas over `duration = 300ms` using `cubic-bezier(0, 0, 0.4, 1)` (`Va(0, 0, 0.4, 1)`):
  ```javascript
  currentValue.value = Math.round(from + (to - from) * bezierEase(progress));
  ```
* **`event-bonus-chip` (`sd`):**
  For `DAILY_BONUS` and `BOT_BUFF` ("Harder") bonus points:
  1. Plays `bonusCoin` audio and transitions `entering -> held`.
  2. If `hasFlip` (`BOT_BUFF`), plays `bonusCoinFlip` audio and transitions `flipping -> flipped`.
  3. Measures `deltaEl.getBoundingClientRect()` and the target progress bar's `getBoundingClientRect()`, sets CSS custom properties `--exit-x` and `--exit-y` to the exact pixel vector between them, and flies the chip directly into the progress bar (`exiting -> landed`), playing `coinHit` and `progressBarGlow` on impact!

---

## 3. Complete 7 `GameArc` Narrative Classifications & 49 Scenarios (`vr` in `shared.39e302ce`)

When CEE's `GameAnalysis` finishes, it assigns one of **7 `GameArc` enums** (`BALANCED`, `ROUGH`, `SHARP`, `SMOOTH`, `THROWAWAY`, `SUDDEN`, `WILD`) and selects a tailored narrative summary based on the player's outcome scenario (`drawEven`, `drawLosing`, `drawWinning`, `lossLosing`, `lossWinningFlag`, `winLosingFlag`, `winWinning`):

| `GameArc` Key | UI Label | Default Description (`desc`) | Outcome Scenario Phrases |
| :--- | :--- | :--- | :--- |
| **`balanced`** | **Balanced** | *"Neither player ever had an advantage."* | • `drawEven`: *"That was a very even game."*<br>• `lossLosing`: *"That was quite a close game."*<br>• `winWinning`: *"You won a close game - well done!"* |
| **`rough`** | **Intense** | *"That was a serious game!"* | • `drawEven`: *"You had winning chances but in the end it was even."*<br>• `drawLosing`: *"You escaped with the draw!"*<br>• `drawWinning`: *"Unfortunate draw - you were winning!"*<br>• `lossLosing`: *"Tough game. Your opponent played well."*<br>• `lossWinningFlag`: *"You were winning - but you ran out of time!"*<br>• `winLosingFlag`: *"Saved by the clock!"*<br>• `winWinning`: *"Nice win. You were never in trouble."* |
| **`sharp`** | **Sharp** | *"A back and forth game where both players had chances."* | • `drawEven`: *"When the dust settled, it was even."*<br>• `drawLosing`: *"You had your chances, but the draw was still a good outcome."*<br>• `drawWinning`: *"Even though you were winning at one point, at least you got the draw."*<br>• `lossLosing`: *"That could have gone either way - a very dynamic game!"*<br>• `lossWinningFlag`: *"You ended up with the advantage, but unfortunately too late."*<br>• `winLosingFlag`: *"A back and forth game - but you were quicker."*<br>• `winWinning`: *"That was a real battle - but you earned the win!"* |
| **`smooth`** | **Smooth** | *"One player took the advantage and never let go."* | • `drawLosing`: *"Nice save - could have been worse!"*<br>• `drawWinning`: *"You were winning but settled for the draw."*<br>• `lossLosing`: *"Looks like this game didn't go your way."*<br>• `lossWinningFlag`: *"Watch the clock - you were winning!"*<br>• `winLosingFlag`: *"Saved by the clock!"*<br>• `winWinning`: *"You had the advantage from start to finish!"* |
| **`throwAway`** | **Giveaway** | *"One player was winning, but then gave it away."* | • `drawLosing`: *"You went from winning to losing, but at least got the draw."*<br>• `drawWinning`: *"That should have been your win!"*<br>• `lossLosing`: *"Looks like that game slipped through your fingers."*<br>• `lossWinningFlag`: *"You fought back, but not quickly enough."*<br>• `winLosingFlag`: *"You lost the advantage but were saved by the clock!"*<br>• `winWinning`: *"Nice comeback win!"* |
| **`sudden`** | **Sudden** | *"A close game that was lost by a mistake."* | • `drawLosing`: *"You got into trouble but escaped with the draw!"*<br>• `drawWinning`: *"You weren't quite able to convert your advantage."*<br>• `lossLosing`: *"One mistake made all the difference."*<br>• `lossWinningFlag`: *"You broke through, but ran out of time."*<br>• `winLosingFlag`: *"You outlasted your opponent even after making a mistake."*<br>• `winWinning`: *"Great win! You saw your chance and took it."* |
| **`wild`** | **Wild** | *"A chaotic game where both players had many chances to win."* | • `drawEven`: *"A back and forth game that settled peacefully!"*<br>• `drawLosing`: *"That battle could have ended worse - good draw!"*<br>• `drawWinning`: *"You fought for an advantage, but ended up with a draw."*<br>• `lossLosing`: *"A back and forth fight that didn't go your way."*<br>• `lossWinningFlag`: *"You were finally winning - until the clock ran out."*<br>• `winLosingFlag`: *"Chances on both sides, but you were quicker."*<br>• `winWinning`: *"A wild game - and you came out on top!"* |

---

## 4. All 45 Game Review Loading Tips, Trivia & Quotes (`hr()` in `shared.39e302ce`)

While Game Review is computing (`EvaluationLoader`), Chess.com randomly selects (`gr()`) from this exact 45-entry pool:

### Coaching & Move Classification Tips (1–19)
1. *"Always look for checks, captures and attacks."*
2. *"The Sicilian Defense is the most popular response to 1.e4."*
3. *"Develop pieces from their starting squares to gain control of the board."*
4. *"Bringing your queen out too early can lead to opening blunders."*
5. *"Look for pawn moves which allow you to develop your pieces."*
6. *"Moving the same piece twice in the opening is generally considered a waste of tempo."*
7. *"The evaluation graph calculates player advantage after each move."*
8. *"A Blunder is a move which significantly impacts a player’s position in a negative way."*
9. *"A Miss is when a tactical opportunity or chance to punish your opponent’s mistake is overlooked."*
10. *"A Mistake is a bad move that immediately worsens your position."*
11. *"An Inaccuracy is a weak move which isn’t as good as the best move."*
12. *"A Book move is a standard opening move regularly played by good players."*
13. *"A Good move is fine, but also there were better moves on the board!"*
14. *"An Excellent move is essentially as good as the Best move: be proud!"*
15. *"The Best move is what the analysis engine determined was the top move."*
16. *"A Great move is a critical move which altered the course of the game."*
17. *"A Brilliant move is when you find a great sacrifice."*
18. *"Accuracy is a measurement of how closely you played to the Best moves."*
19. *"Learning a new opening is a fun way of keeping chess fresh."*

### Chess History & Trivia (20–34, 44–45)
20. *"After 3 moves there are 121 million possible positions."*
21. *"Some believe the \"Greek Gift Sacrifice\" was named after Gioachino Greco, who was Italian."*
22. *"Stanley Kubrick hustled chess in Washington Square Park to pay for food in his early 20s."*
23. *"There are nearly 1,800 grandmasters in the world."*
24. *"En passant is French for \"in passing\"."*
25. *"If \"rook\" comes from the Persian word \"rukh\" meaning chariot, why does the piece look like a tower?"*
26. *"Abhimanyu Mishra became the youngest grandmaster ever at the age of 12 years, 4 months, and 25 days."*
27. *"The name \"Deep Blue\" came from a naming contest held by IBM and is a play on their nickname \"Big Blue\"."*
28. *"Zugzwang is German for \"compulsion to move\" and happens when any move made puts the player at a disadvantage."*
29. *"The chess game played in Blade Runner is a recreation of the \"Immortal Game\" between Adolf Anderssen and Lionel Kiseritzky in 1851."*
30. *"There are 960 legal starting positions in a game of Chess960."*
31. *"English chess masters were recruited as code breakers during World War II."*
32. *"Until the mid-1800s, chess games were played without a time limit."*
33. *"Until the 1600s, castling required two moves."*
34. *"The current format for writing chess moves down, algebraic notation, was formalized in 1981."*
35. *"The first chess computer, The Mechanical Turk, was actually just a guy hiding in a box pretending to be an automaton."*
36. *"The last time checkmate happened in a World Championship match was 1929."*
37. *"In 1951, IM Robert Wade played a simultaneous exhibition against 30 Russian schoolboys. Wade won 0 games, drew 10, and lost the other 20."*
38. *"The quickest checkmate possible is only 2 moves."*
39. *"World Champion Alexander Alekhine had a cat named \"Chess\"."*
40. *"During the 1978 World Championship, Anatoly Karpov hired a hypnotist to sit in the front row and stare at his opponent."*
41. *"World Champion Mikhail Tal only had 3 fingers on his right hand."*
42. *"The Evans Gambit is named after 19th Century Welsh sea captain William Davies Evans."*
43. *"The 1984-85 World Championship was abandoned after 5 months and 48 games for the health of the players."*
44. *"The longest chess game in the history of the World Championship was game 6 of the 2021 World Championship, at 136 moves."*

### Famous Grandmaster Quotes (35–43)
* *"\"The blunders are all there on the board, waiting to be made.\" - Savielly Tartakower"*
* *"\"There are two types of sacrifices: Correct ones, and mine.\" - Mikhail Tal"*
* *"\"Chess is the gymnasium of the mind.\" - Blaise Pascal"*
* *"\"Even a poor plan is better than no plan at all.\" - Mikhail Chigorin"*
* *"\"The winner of the game is the player who makes the next to last mistake.\" - Savielly Tartakower"*
* *"\"I am Alekhine, chess champion of the world. I have a cat called Chess.\" - Alexander Alekhine, when stopped at the Polish-Russian border without a passport."*
* *"\"Chess problems demand from the composer the same virtues that characterize all worthwhile art.\" - Vladimir Nabokov"*
* *"\"Chess is a matter of delicate judgment, knowing when to punch and how to duck.\" - Bobby Fischer"*
* *"\"Steady effort pays off, even if not always in an immediate, tangible way.\" - Garry Kasparov"*
* *"\"A passed pawn increases in strength as the number of pieces on the board diminishes.\" - Jose Raul Capablanca"*
* *"\"Chess is the art which expresses the science of logic.\" - Mikhail Botvinnik"*
* *"\"If you want to play well, it's important to concentrate on the now.\" - Vassily Ivanchuk"*
