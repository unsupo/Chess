# Architecture Refactor: Overview & Phase Index

**Status:** Built — all 5 phases complete. See each phase's own doc for
build notes and any deviations from its original sketch. See the audit
this is based on in the session history;
the short version: `game_page.dart` (2,329 lines) and `game_provider.dart`
(1,605 lines) are God Objects absorbing every new feature, personality
move-selection exists as three inconsistent shapes instead of one Strategy
interface, and several pure-dart chess helpers (piece values, move→UCI,
hanging-piece detection) are copy-pasted 2-3x with subtly different
answers. This refactor's goal is purely structural: **no behavior change**
in any phase. Every phase ends with `flutter analyze` clean and the full
`flutter test` suite green, same as before the phase started.

## Why phased, not one big rewrite

Each phase is independently shippable and de-risks the next one:
mechanical file splits first (near-zero behavior risk, immediately
useful), then helper consolidation (small, mechanical, removes
duplicated-logic risk), then the two structural patterns that actually
change control flow (Strategy, then Chain of Responsibility + Decorator
on top of it), then the riskiest one last (`GameNotifier` Facade split)
once everything underneath it is already clean and covered by tests.
Stopping after any phase leaves the codebase strictly better than before
it, never half-broken.

## Phase order

| # | Doc | What | Risk | Depends on |
|---|-----|------|------|------------|
| 1 | [refactor_01_widget_file_split.md](refactor_01_widget_file_split.md) | Split `game_page.dart` + `chess_feature_widgets.dart` into one file per widget | Low (pure move, no logic change) | — |
| 2 | [refactor_02_shared_chess_helpers.md](refactor_02_shared_chess_helpers.md) | Consolidate duplicated `pieceValue`/`_moveToUci`/hanging-piece-detection into one module | Low-medium (must preserve exact behavior of 3 slightly different implementations) | — |
| 3 | [refactor_03_bot_strategy_pattern.md](refactor_03_bot_strategy_pattern.md) | Unify `ScholarsMateHunterPolicy`/`PawnPusherPolicy`/`BotStylePolicy` under one `BotMoveStrategy` interface + registry | Medium | Phase 2 |
| 4 | [refactor_04_bot_move_pipeline.md](refactor_04_bot_move_pipeline.md) | Turn `_pickBotMove`'s inlined sequence (opening book → weak play → personality → draw avoidance → mate safety) into an explicit Chain of Responsibility, with weak-play/mate-safety as Decorators | Medium | Phase 3 |
| 5 | [refactor_05_game_notifier_facade.md](refactor_05_game_notifier_facade.md) | Extract `PgnCodec`, `ClockService`, `GameReviewService` out of `GameNotifier`; `GameNotifier` becomes a thin Facade | High (touches the most call sites) | Phases 1-4 |

Phases 1 and 2 have no dependency on each other and could be done in
either order or in parallel; 3, 4, 5 are strictly sequential (each
phase's target shape is what the next phase's doc assumes already
exists).

## Standing architectural principle: backend/frontend boundary

Separately from the 5 phases above (not a migration — already true,
just codified):
[architecture_backend_frontend_boundary.md](architecture_backend_frontend_boundary.md)
maps the existing `domain`/`data`/`presentation` split onto MVC and
states the hard rule that keeps it that way: only `data/repositories/`
may import a real backend/network/platform dependency, everything else
talks to it through a `domain/repositories/` interface. Worth re-reading
before any future feature that touches a network/platform/SDK
dependency for the first time (multiplayer, cloud save, accounts, etc.).

## Non-goals

- No new features, no UI changes, no test-behavior changes. Existing
  tests should need import-path updates at most, never new/changed
  assertions (a test needing a changed assertion to pass is a sign a
  phase broke behavior, not a sign the test was wrong).
- Not touching `lib/core/widgets/chess_board/` (the board widget itself)
  — it's already a single well-scoped file, not part of the God Object
  problem.
- Not touching the engine repository layer
  (`chess_engine_repository_impl.dart` + `native`/`web` implementations)
  — already a clean Bridge/Strategy pattern (platform selected via
  conditional export), nothing to fix there.
- Not introducing a DI container, router, or second state-management
  library — stays on Riverpod `StateNotifier`, per
  `~/dev/CLAUDE.md`'s "follow the repo's existing architecture" rule.

## Verification per phase

Every phase doc ends with the same checklist:
1. `dart format` the touched/new files.
2. `flutter analyze` — zero new issues.
3. `flutter test` — full suite green, no assertions changed.
4. For phases touching `presentation/` — a macOS debug build + launch +
   screenshot closed-loop check, per `~/dev/CLAUDE.md`'s UI-change rule.
