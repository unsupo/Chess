# Feature: Bot Personalities

## Overview

Seven named bot personalities, each with a distinct emoji, tagline, flavor text, and default ELO. Selecting a personality sets the bot's ELO and updates the bot panel UI. Four of the seven also have a dedicated move-selection strategy (see `docs/features/done/bot_play_styles.md`); the other three play through the plain engine best-move fallback.

## Personalities

| ID | Emoji | Name | Tagline | Default ELO | Category | Move-selection strategy |
|---|---|---|---|---|---|---|
| `martin` | 🤖 | Martin | Friendly Beginner | 900 | Beginner | `DefaultBotMoveStrategy` (plain best-move + draw avoidance) |
| `aggressor` | ⚔️ | The Aggressor | Fast-Mate & Trap Hunter | 1400 | Intermediate | `AggressorStrategy` → `ScholarsMateHunterPolicy` (`docs/features/done/scholars_mate_hunter.md`) |
| `pawn_pusher` | ♟️ | The Pawn Pusher | Relentless Pawn Storm | 1300 | Intermediate | `PawnPusherStrategy` → `PawnPusherPolicy` |
| `strategist` | 📚 | The Strategist | Positional Master | 1700 | Advanced | `DefaultBotMoveStrategy` |
| `trickster` | 🎭 | The Trickster | Trap Setter | 2000 | Advanced | `TricksterStylePolicy` (maximizes forks/checks/sacrifices within a tolerance band) |
| `defender` | 🛡️ | The Defender | Fortress Builder | 1500 | Intermediate | `DefenderStylePolicy` (heavily penalizes hanging pieces) |
| `crusher` | 👑 | The Crusher | Relentless GM | 2400 | Master | `DefaultBotMoveStrategy` |

## Key files

- `lib/features/game/domain/entities/bot_personality.dart` — `BotPersonality` entity + `kPersonalities` list + `kDefaultPersonality` const
- `lib/features/game/domain/entities/bot_move_strategy.dart` — `kBotMoveStrategies` registry mapping personality `id` to its strategy (`docs/features/done/refactor_03_bot_strategy_pattern.md`); an id with no entry falls back to `DefaultBotMoveStrategy`

## `kDefaultPersonality` must be `const`

`GameState` uses `kDefaultPersonality` as a default parameter value. Default parameters must be compile-time constants. `kPersonalities[0]` is not a compile-time constant (list indexing), so `kDefaultPersonality` is declared as a standalone `const`. See GOTCHAS #8.

## ELO slider interaction

The ELO slider (800–2800) overrides the personality's default ELO. Selecting a new personality resets the slider to that personality's default ELO via `setPersonality(p)` → `state.copyWith(personality: p, botElo: p.defaultElo)`.

## Difficulty scaling

Stockfish skill level: `((elo - 800) / 100).clamp(0, 20).toInt()`. `UCI_LimitStrength` is disabled because it's unreliable in FFI builds (see `docs/features/done/engine.md`). Below 1000 ELO, a separate weak-play curve (`docs/features/done/refactor_04_bot_move_pipeline.md`'s `WeakPlayStep`) applies to every personality regardless of its move-selection strategy, so dragging the difficulty slider down genuinely weakens Aggressor/Pawn Pusher/Trickster/Defender too, not just the three personalities without a dedicated strategy.
