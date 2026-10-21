# Feature: Personality-Driven Play Styles

**Status:** Built. Aggressor ended up with its own dedicated policy
(`ScholarsMateHunterPolicy`, `docs/features/scholars_mate_hunter.md` —
a more thorough mate-hunting/opening-trap implementation than the simple
scorer originally sketched below) instead of the generic
`BotStylePolicy` mechanism. Trickster and Defender were built as
originally planned here, via `bot_style_policy.dart`.

## Problem

Personalities (`docs/features/personalities.md`) currently only differ by
flavor text and `defaultElo` — every personality plays through the exact
same path, `ChessEngineRepository.getBestMove(fen)`, which just returns
Stockfish's single best move at the configured skill level. "The
Aggressor" doesn't actually attack, "The Trickster" doesn't actually set
traps.

The user wants real behavioral differences:
- **Aggressor** — prioritize mating as fast as possible and capturing
  material (especially high-value pieces); specifically avoid trading
  queens, since that makes mating harder; open with the Wayward Queen
  Attack (1. e4 e5 2. Qh5); keep pushing mating nets.
- **Trickster** — maximize "tricks" (traps / tactical complications), not
  just flavor text.
- **New personality: Defender** — build fortresses, avoid losing any
  pieces (maximally solid/risk-averse play).

## Why this needs a shared mechanism, not three one-off hacks

Stockfish has no "personality" knob — `Skill Level`/`UCI_Elo` only throttle
strength, not style. The only lever available is: **ask the engine for
several good-or-near-good candidate moves instead of just the top one, and
pick among them by a style-specific score.** All three requested behaviors
(and anything added later — Strategist, Crusher) fit this same shape, so
this doc proposes one reusable mechanism with a pluggable scorer per
personality, rather than bespoke logic per bot.

## Proposed architecture

### 1. Multi-candidate search

Add to `ChessEngineRepository` (`lib/features/game/domain/repositories/chess_engine_repository.dart`):

```dart
Future<List<EngineMoveCandidate>> getTopMoves(
  String fen, {
  int movetimeMs = 500,
  int multiPv = 5,
});
```

`EngineMoveCandidate { String uci; int scoreCp; int? mateIn; }`. Native
implementation: set UCI option `MultiPV` to the requested count before
`go movetime N`, and parse all `info ... multipv K score cp|mate V pv
movelist...` lines (today's `_handleUciOutput` only tracks a single
`_latestScore`; it'll need a `Map<int, EngineMoveCandidate>` keyed by the
`multipv` index instead, finalized on `bestmove`). `web_engine_repository.dart`
needs a matching stub (e.g. return N random legal moves) so the interface
stays satisfiable on web. **`getBestMove` stays as-is** — this is an
additive method, not a replacement, so personalities without a style
policy (Martin, Strategist, Crusher — not in scope here) are completely
unaffected.

### 2. Style policy

A small interface, e.g. `lib/features/game/domain/entities/bot_style_policy.dart`:

```dart
abstract class BotStylePolicy {
  /// Picks a move from the candidates, or null to fall back to plain
  /// getBestMove() behavior (e.g. no legal candidates matched the style).
  String? pickMove(String fen, List<EngineMoveCandidate> candidates);
}
```

`GameNotifier`'s bot-reply step (`onUserMove`, currently always calling
`getBestMove`) checks whether `state.personality` has a style policy; if
so, it calls `getTopMoves` and runs the policy instead. Only Aggressor,
Trickster, and Defender get one; everyone else is untouched.

Every style score is computed **relative to Stockfish's own eval**, with a
per-personality tolerance band (never pick a candidate that's objectively
losing compared to the engine's top choice just to "be in character"):

```
tolerance_cp:  Aggressor 150   Trickster 100   Defender 50
```

(Defender gets the tightest band — it should barely deviate from the
objectively safest line. Aggressor and Trickster get more room to pick a
flashier-but-still-sound move.)

### 3. Scripted opening (Aggressor only, separate mechanism)

The Wayward Queen Attack is a known-dubious but famous line that Stockfish
would never choose on its own — it needs to be scripted, not derived from
candidate scoring:

- Only when the Aggressor is playing **White**.
- Move 1: always `e2e4`.
- Move 2: `d1h5` **only if** the opponent replied `e7e5`. Any other black
  reply abandons the line permanently for that game — fall through to the
  style-scored policy below from that point on (no attempt to force the
  attack against a different defense).

This is per-personality, per-game state (which plies have been played,
whether the line is still "live") — lives in `GameNotifier` or a small
helper tracking move count, not in the engine repository.

## Per-personality style scoring

### Aggressor — superseded by `ScholarsMateHunterPolicy`

The simple scorer originally sketched here (mate bonus + capture value +
check bonus - queen-trade penalty) was superseded during implementation
by a more thorough, dedicated policy — see
`docs/features/scholars_mate_hunter.md`. That policy covers the same
ground (rush the mate, grab material, avoid trading queens, scripted
Wayward Queen Attack / Scholar's Mate opening, keep pressing mating
nets) plus immediate mate-in-1/forced mate-in-2 detection and a richer
king-hunt scoring formula (king-zone pressure, castling-rights denial,
mobility squeeze). Aggressor does **not** go through
`styleForPersonalityId`/`bot_style_policy.dart` — `GameNotifier._pickBotMove`
dispatches it straight to `ScholarsMateHunterPolicy.selectMove`.

### Trickster — maximize tricks (traps / tactical complications)

Operationalized as:

```
score = 40   if the move creates a fork (attacks ≥2 enemy pieces,
              at least one worth ≥ a knight, from the piece's new square)
      + 25   if the move is a discovered check or direct check
      + 20   if the move sacrifices material (lower material count than
              the top-eval candidate) while still inside the tolerance band
              — i.e. an objectively-fine-but-unobvious imbalance
```

Caveat worth flagging: "setting traps" really means anticipating what an
opponent is *likely* to misplay, which Stockfish's eval doesn't model at
all. This is a reasonable approximation (reward tactical complexity /
forcing moves), not true trap-setting — documenting that limitation here
rather than over-promising.

### Defender (new personality) — fortress, never drop a piece

```
score = -200 * hangingPieceValue   for each of the bot's own pieces left
                                     attacked-and-undefended after the move
                                     (big, dominant penalty — this is the
                                     whole point of the personality)
      + 10   if the move is a trade while material is even-or-ahead
             (simplify instead of complicate)
      + 10   if the move is castling
```

"Hanging" = after the hypothetical move, generate the opponent's legal
captures from the resulting FEN (same technique `_applyUci` already uses
to apply a move to a FEN) and check whether any land on a bot piece with
no defender of sufficient value recapturing. This is the most
implementation-heavy piece of the whole feature — needs its own small
helper, likely worth a unit test given it's pure domain logic (`chess`
package calls, no Flutter/engine dependency) per this repo's TDD guidance
for domain logic.

**New personality entry**, as built in `bot_personality.dart`:

```dart
BotPersonality(
  id: 'defender',
  name: 'The Defender',
  emoji: '🛡️',
  tagline: 'Fortress Builder',
  greeting: "Nothing gets through. I don't lose pieces — I outlast you.",
  defaultElo: 1500,
  category: 'Intermediate',
),
```

### Not in scope here

Martin, Strategist, and Crusher keep today's plain `getBestMove` behavior
— no style policy requested for them, so none is added. The architecture
above (candidate list + pluggable policy) is reusable if that's wanted
later.

## Decisions baked in as reasonable calls (not re-litigated here)

1. Tolerance bands: Aggressor 150cp / Trickster 100cp / Defender 50cp.
2. `multiPv = 5` for all style-driven searches.
3. Wayward Queen Attack: Aggressor-as-White only, abandoned permanently
   after move 1 if black doesn't reply `e7e5`.
4. Defender's name/emoji/tagline/greeting as drafted above.
5. "Trick" and "fortress" are approximated via the concrete, computable
   proxies above (forks/checks/sacrifices; hanging-piece avoidance) rather
   than anything resembling true opponent-blunder prediction.

## Risks / implementation notes

- `MultiPV` search is somewat more expensive than single-PV; reuse the
  existing `movetimeMs` budget (don't add extra sequential searches) so
  this doesn't blow past the existing `getBestMove` timeout
  (`movetimeMs + 4000ms`, see `docs/features/engine.md`).
- `_handleUciOutput` needs restructuring to track per-`multipv`-index
  candidates instead of one `_latestScore` — a real change to
  `native_engine_repository.dart`'s parsing, not just additive.
- Hanging-piece / fork detection is the highest-risk piece of new domain
  logic here and should get unit tests before wiring it into the UI, per
  this repo's TDD guidance for domain logic.

## Likely touched files

- `lib/features/game/domain/repositories/chess_engine_repository.dart` — new `getTopMoves` method
- `lib/features/game/data/repositories/native_engine_repository.dart` — MultiPV parsing
- `lib/features/game/data/repositories/web_engine_repository.dart` — matching stub
- `lib/features/game/domain/entities/bot_style_policy.dart` — new
- `lib/features/game/domain/entities/bot_personality.dart` — new Defender entry, optional policy reference
- `lib/features/game/presentation/providers/game_provider.dart` — bot-reply branch + scripted-opening tracking
- `docs/features/personalities.md` — update once built (new Defender row, note which personalities have a style policy)
