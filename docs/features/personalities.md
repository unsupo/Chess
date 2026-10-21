# Feature: Bot Personalities

## Overview

Five named bot personalities, each with a distinct emoji, tagline, flavor text, and default ELO. Selecting a personality sets the bot's ELO and updates the bot panel UI.

## Personalities

| ID | Emoji | Name | Tagline | Default ELO |
|---|---|---|---|---|
| `martin` | 🤖 | Martin | Friendly Beginner | 900 |
| `aggressor` | ⚔️ | The Aggressor | Reckless Attacker | 1400 |
| `strategist` | 📚 | The Strategist | Positional Master | 1700 |
| `trickster` | 🎭 | The Trickster | Trap Setter | 2000 |
| `crusher` | 👑 | The Crusher | Relentless GM | 2400 |

## Key files

- `lib/features/game/domain/entities/bot_personality.dart` — `BotPersonality` entity + `kPersonalities` list + `kDefaultPersonality` const

## `kDefaultPersonality` must be `const`

`GameState` uses `kDefaultPersonality` as a default parameter value. Default parameters must be compile-time constants. `kPersonalities[0]` is not a compile-time constant (list indexing), so `kDefaultPersonality` is declared as a standalone `const`. See GOTCHAS #8.

## ELO slider interaction

The ELO slider (800–2800) overrides the personality's default ELO. Selecting a new personality resets the slider to that personality's default ELO via `setPersonality(p)` → `state.copyWith(personality: p, botElo: p.defaultElo)`.

## Difficulty scaling

Stockfish skill level: `((elo - 800) / 100).clamp(0, 20).toInt()`. `UCI_LimitStrength` is disabled because it's unreliable in FFI builds (see engine.md).
