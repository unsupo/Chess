# Refactor Phase 1: Widget File Split

**Status:** Built. Part of
[refactor_overview.md](refactor_overview.md), phase 1.

## Problem

Two files hold almost every presentation-layer widget in the app:

- `lib/features/game/presentation/pages/game_page.dart` (2,329 lines):
  `GamePage`, `_GamePageState` (644-line `build()`), plus 16 more widget
  classes (`_PlayerReviewCard`, `_GameOverBanner`, `_BotPanel`,
  `_PlayerBar`, `_HistoryStepBtn`, `_CapturedPiecesBar`, `_ControlsPanel`,
  `_AntiBlunderToggle`, `_EvalBarToggle`, `_OpeningSelector`,
  `_HistoryLockToggle`, `_MateSafetyControl`, `_IconBtn`, `_Sidebar`,
  `_CollapseToggleButton`, `_SidebarExpanded`, `_SidebarCollapsedRail`).
- `lib/features/game/presentation/widgets/chess_feature_widgets.dart`
  (1,001 lines): 5 numbered, unrelated sections — ticker/move-time clock,
  the resizable board frame, bot crowns + play-side/time-control
  selectors, the move history/feedback bar, the eval bar/graph — each
  with its own widget classes and private painters.

Finding the right place to make a change means scrolling a file with no
relation to what you're changing. Every new control (the eval-bar
toggle, the opening selector) has so far meant adding another class to
one of these two files, making the problem worse each time.

## Proposed approach

Pure file move + import fix-up. **No widget's code changes**, only its
file location and the imports that follow it. One file per widget
family, grouped by what they're part of:

### From `game_page.dart`

| New file | Classes |
|---|---|
| `presentation/pages/game_page.dart` (stays, shrinks) | `GamePage`, `_GamePageState` only |
| `presentation/widgets/game_over_banner.dart` | `_GameOverBanner`, `_PlayerReviewCard` |
| `presentation/widgets/bot_panel.dart` | `_BotPanel` |
| `presentation/widgets/player_bar.dart` | `_PlayerBar`, `_HistoryStepBtn`, `_CapturedPiecesBar` |
| `presentation/widgets/controls_panel.dart` | `_ControlsPanel`, `_IconBtn` |
| `presentation/widgets/game_toggles.dart` | `_AntiBlunderToggle`, `_EvalBarToggle`, `_HistoryLockToggle`, `_MateSafetyControl` |
| `presentation/widgets/opening_selector.dart` | `_OpeningSelector` |
| `presentation/widgets/sidebar.dart` | `_Sidebar`, `_SidebarExpanded`, `_SidebarCollapsedRail`, `_CollapseToggleButton` |

### From `chess_feature_widgets.dart`

| New file | Classes |
|---|---|
| `presentation/widgets/ticker_clock_widget.dart` | `TickerIconWidget`, `_TickerClockPainter`, `MoveTimeWidget`, `_MoveTimeWidgetState` |
| `presentation/widgets/resizable_board_frame.dart` | `ResizableBoardFrame`, `_ResizableBoardFrameState`, `_ResizeGripPainter` |
| `presentation/widgets/bot_crowns_and_selectors.dart` | `BotCrownsWidget`, `PlaySideSelectorWidget`, `_PlaySideButton`, `TimeControlSelectorWidget` |
| `presentation/widgets/move_history_feedback_bar.dart` | `MoveHistoryAndFeedbackBar`, `classificationColor()` + the `k*MoveColor` constants |
| `presentation/widgets/eval_bar_and_graph.dart` | `EvalBar`, `EvalGraph`, `_EvalGraphPainter` |
| *(deleted)* `chess_feature_widgets.dart` | — |

### Shared private constants

Both files currently define their own copies of the same color palette
(`_cardBg`/`_card`, `_darkBg`/`_bg`, `_accent`, `_muted`, `_accentFill`,
`_borderSubtle`, etc. — same values, different names in each file). Move
these into one `presentation/widgets/game_theme.dart` (plain top-level
`const Color` values, not a Flutter `ThemeData` — scope stays small,
matching how they're used today) and import it everywhere instead of
each file redeclaring its own copy. This is the one place this phase
touches something beyond pure file-move, and it's additive-only: delete
the duplicate `const` declarations, point every reference at the shared
file, verify nothing resolves to a different color than before (diff the
two existing constant tables first — they should already agree on
values, just not names).

### Widget privacy

Several of these classes are currently private (`_BotPanel`,
`_PlayerBar`, etc.) because they only needed to be visible within one
file. Splitting them into their own files means either making them
public (drop the leading `_`) or keeping them private and marking each
new file's exports explicitly. Prefer **making them public** (drop the
`_`) — they're still only constructed from within
`presentation/pages/game_page.dart` and `presentation/widgets/sidebar.dart`
today, but a private-to-a-single-file naming convention stops making
sense once "the file" is now 8 files. Flutter/Dart convention for
internal-but-cross-file widgets is a plain public name with no leading
underscore, same as `ResizableBoardFrame` or `MoveHistoryAndFeedbackBar`
already are.

## Decisions baked in as reasonable calls

1. One file per widget *family* (a widget + its tightly-coupled private
   helper classes like a `CustomPainter` or `State` class), not strictly
   one file per class — `_TickerClockPainter` stays with
   `TickerIconWidget`, `_ResizeGripPainter` stays with
   `ResizableBoardFrame`, etc.
2. `game_toggles.dart` groups the four simple `Switch`-based toggle
   widgets together rather than giving each its own file — they're small
   (20-40 lines each) and structurally identical (a `Row` + label +
   `Switch`), so one file for the group reads better than four
   near-empty files.
3. Shared color constants move to `game_theme.dart`; nothing else about
   theming changes in this phase (no `ThemeData`/`ThemeExtension`
   introduced — that would be a separate, later decision if ever
   wanted).
4. No barrel file (`widgets.dart` re-exporting everything) — each
   consumer imports exactly the files it uses, consistent with how
   `game_provider.dart` is already imported directly rather than through
   an index.

## Likely touched files

- All of `game_page.dart` and `chess_feature_widgets.dart` (split, not
  deleted-and-rewritten — moved).
- `game_page.dart`'s own imports (needs to import every new
  `presentation/widgets/*.dart` file it uses).
- `test/widget/game_page_test.dart` — only if it imports any now-moved
  class directly (check for direct imports of
  `chess_feature_widgets.dart`; `ChessApp`/`gameProvider` imports are
  unaffected).

## Verification

Per `refactor_overview.md`'s checklist. Since this phase is a pure move,
a fast sanity check beyond the standard checklist: `git diff --stat`
should show the two source files mostly/fully deleted and ~13 new files
added, with no file showing large insertion+deletion counts on the same
lines (which would indicate logic actually changed, not just moved).
