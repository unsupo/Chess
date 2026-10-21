# Architecture Principle: Backend/Frontend Boundary (MVC Mapping)

**Status:** Already true today — verified, not built. This document
codifies an existing property of the codebase as an explicit rule so it
stays true through the refactor ([refactor_overview.md](refactor_overview.md))
and any future feature that talks to a real backend (multiplayer, cloud
save, accounts — none of which exist yet, but the app should already be
shaped to add one without a rearchitect).

## The MVC mapping

This app doesn't use a web MVC framework, but the existing feature-first
`domain`/`data`/`presentation` split (required by `~/dev/CLAUDE.md`) already
maps directly onto MVC, which is the cleanest way to reason about where a
future backend would plug in:

| MVC role | This codebase | What lives there |
|---|---|---|
| **Model** | `domain/entities/`, `domain/usecases/`, `domain/repositories/` | Pure Dart business logic and data shapes (`GameReviewAnalyzer`, `ScholarsMateHunterPolicy`, `BotPersonality`, `ChessOpening`...) plus **abstract repository interfaces** (`ChessEngineRepository`) — the contract a backend must satisfy, with zero knowledge of how it's actually satisfied. |
| **Model's backend adapter** | `data/repositories/` | Concrete implementations of the `domain/repositories/` interfaces. Today: `native_engine_repository.dart` (local Stockfish via FFI/platform channel) and `web_engine_repository.dart` (pure-Dart mock). **This is the only layer allowed to import a real backend/IO/network/platform dependency.** |
| **Controller** | `presentation/providers/` | `GameNotifier`/`GameState` — mediates between View and Model, holds no business logic of its own beyond coordinating calls into `domain/` and reacting to their results. |
| **View** | `presentation/pages/`, `presentation/widgets/` | Widgets. Read `GameState` via Riverpod, fire callbacks on `GameNotifier`. No business logic, no data access, no awareness of *how* a move is validated or an engine answers — only that `GameNotifier` eventually updates `GameState` and the widget rebuilds. |

## The hard rule

**Nothing outside `data/` may import a backend/network/platform/IO
dependency directly.** Concretely, `domain/` and `presentation/` must never
import `dart:io`, `dart:ffi`, `package:http`, a database/SDK client
(`supabase_flutter`, `firebase_*`, etc.), or (today's one concrete case)
`package:stockfish`. If a future feature needs one of these, the dependency
is added to a new or existing `data/repositories/` class implementing a
`domain/repositories/` interface — never reached into directly from a
widget or from `GameNotifier`.

**Verified true today:**
```
$ grep -rln "dart:io\|package:http\|dart:ffi\|package:stockfish\|dio\|supabase\|firebase" \
    lib/features/game/domain/ lib/features/game/presentation/
(no matches)

$ grep -rln "package:stockfish" lib/
lib/features/game/data/repositories/native_engine_repository.dart

$ grep -rln "implements ChessEngineRepository\|extends ChessEngineRepository" lib/
lib/features/game/data/repositories/web_engine_repository.dart
lib/features/game/data/repositories/native_engine_repository.dart
```

## Why this matters for a future backend

If this app ever grows a real backend-dependent feature — multiplayer
matches, cloud game history, an account system, a server-hosted engine
instead of local Stockfish — the shape is already right:

1. Define the contract as a new (or extended) interface under
   `domain/repositories/`, e.g. `MatchRepository`.
2. Implement it under `data/repositories/`, e.g.
   `supabase_match_repository.dart` — this is the **only** file allowed
   to import the Supabase SDK, an HTTP client, a WebSocket, etc.
3. Wire it into Riverpod the same way `engineRepositoryProvider` already
   does (`chess_engine_repository_impl.dart`'s conditional export is the
   existing pattern for "which concrete backend implementation" — a
   non-platform-conditional case is even simpler, just a plain
   `Provider<MatchRepository>((ref) => SupabaseMatchRepository(...))`).
4. `GameNotifier` (Controller) calls the interface, never the concrete
   class. Widgets (View) never see either.

No widget, no `domain/` file, and no test fake needs to change shape —
exactly the same reason `ChessEngineRepository` already has a trivial
`web_engine_repository.dart` mock usable in tests/CI without a real
engine: the interface is the seam, and every consumer already only knows
about the seam.

## One case worth flagging explicitly: phase 3's `BotMoveStrategy`

[refactor_03_bot_strategy_pattern.md](refactor_03_bot_strategy_pattern.md)
proposes giving `BotMoveContext` (a `domain/entities/` class) a
`ChessEngineRepository engine` field, so personality strategies can call
`getTopMoves`/`getBestMove` with their own `multiPv`/`mateLimit` choices.
This does **not** violate the rule above: `ChessEngineRepository` is
itself an abstract `domain/repositories/` interface with no backend
dependency of its own — a domain class depending on another domain
interface is normal layering, not a boundary leak. The rule is about
concrete backend/IO types, not about domain interfaces referencing each
other. `BotMoveStrategy` implementations still never import
`package:stockfish` or anything data-layer-specific; they only ever see
the interface.

## Enforcement going forward

No tooling enforces this automatically today (no import-boundary lint
rule is configured). Until/unless that's worth adding, treat it as a
standing review checklist item: before merging any change that adds a
new dependency (a package, an SDK, a platform channel), ask "does
`domain/` or `presentation/` now import this directly, or does it stay
behind a `data/repositories/` class implementing a `domain/repositories/`
interface?" A grep like the one above is cheap enough to run as part of
any future architecture audit.

## Likely touched files

None today — this is a verification + standing rule, not a migration.
Revisit if a lint rule for import boundaries (e.g. a custom
`custom_lint`/`import_lint` rule restricting what `domain/`/`presentation/`
may import) is ever worth the setup cost; not proposed here since the
codebase is still small enough that a periodic grep check is sufficient.
