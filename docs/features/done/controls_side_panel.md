# Feature: Collapsible Side Panel for Controls

**Status:** Built.

## Overview

Replaces the legacy vertical bottom-controls strip on wide viewports (desktop, tablet, and landscape web) with an interactive, animated right-hand collapsible sidebar (`Sidebar`). This unburdens vertical space, allowing the chessboard to expand width-first rather than being constrained by vertical panel stacking. On narrow/mobile viewports (`< 700px`), the layout smoothly reverts to the bottom controls strip.

## Key Files in Flutter App

- [`lib/features/game/presentation/widgets/sidebar.dart`](file:///Users/jonathanarndt/dev/chess_teacher/lib/features/game/presentation/widgets/sidebar.dart) — `Sidebar`, `SidebarExpanded`, `SidebarCollapsedRail`, and `CollapseToggleButton`
- [`lib/features/game/presentation/pages/game_page.dart`](file:///Users/jonathanarndt/dev/chess_teacher/lib/features/game/presentation/pages/game_page.dart) — Responsive layout switch (`useSidePanel`), board size constraints, and collapse state management

---

## Architectural Layout

```
Wide Viewports (>= 700px):
┌──────────────────────────────────────────┬──────────────────┐
│ BotPanel                                 │  Controls        │
│                                          │  Sidebar         │
│          ChessBoardWidget                │  - Anti-Blunder  │
│         (Width-First Sizing)             │  - History Lock  │
│                                          │  - Mate Safety   │
│ MoveHistoryAndFeedbackBar + EvalGraph    │  - Eval Bar      │
│                                          │  - Opening Book  │
│ PlayerBar                                │  - Play Side     │
│                                          │  - Time Control  │
│                                          │  - Opponent List │
│                                          │  - Difficulty    │
│                                          │  - Action Bar    │
└──────────────────────────────────────────┴──────────────────┘

Collapsed Rail (56px):
┌──────────────────────────────────────────┬────┐
│ BotPanel                                 │ [>]│
│          ChessBoardWidget                │ 🛡️ │
│ MoveHistoryAndFeedbackBar + EvalGraph    │ 🔒 │
│ PlayerBar                                │ 🎯 │
│                                          │ 🔄 │
└──────────────────────────────────────────┴────┘
```

---

## Resolved Design Decisions

| # | Decision Item | Selected Implementation | Rationale |
|---|---|---|---|
| 1 | **Breakpoint** | `700.0px` (`_sidePanelBreakpoint`) | Below 700px (portrait phones), a 280px sidebar would excessively cramp the chessboard. At 700px and above, the board easily fits alongside the sidebar with comfortable margins. |
| 2 | **Collapsed State** | 56px slim icon-only rail (`_sidebarWidthCollapsed`) | Rather than fully hiding to width 0 (which requires floating reopen buttons), a 56px rail provides continuous single-tap access to primary toggles (Anti-Blunder, History Lock, Mate Safety) and board actions (Flip, FEN/PGN, New Game, Move History arrows). |
| 3 | **Default on Launch** | Expanded (`_sidebarCollapsed = false`) | Allows the user to immediately see bot options, time controls, and opening selection when starting the app. |
| 4 | **State Persistence** | Pure in-memory UI state | Resets to expanded on new sessions without introducing local storage dependencies, adhering to the Clean Architecture domain boundaries. |
| 5 | **Sidebar Width** | 280px expanded (`_sidebarWidthExpanded`) | Matches standard desktop design systems (e.g. Chess.com's 280–300px sidebar) and allows comfortable tap targets for all controls without wrapping labels. |
| 6 | **Personality Picker** | Vertical `ListView.separated` with crowns | Replaced the legacy horizontal scroller with a clean vertical list featuring bot emoji avatars, category tags, and 3-tier crown progression badges. |

---

## Anti-Overflow Animation Pattern

Collapsing a complex `Column` containing sliders, switches, and text directly into a narrowing container will cause Flutter layout overflow errors (`RenderFlex overflowed by X pixels`) during the 200ms width transition.

To guarantee zero layout overflow during animation:
```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeInOut,
  width: collapsed ? _sidebarWidthCollapsed : _sidebarWidthExpanded,
  color: kCard,
  child: ClipRect(
    child: OverflowBox(
      minWidth: _sidebarWidthExpanded,
      maxWidth: _sidebarWidthExpanded,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _sidebarWidthExpanded,
        child: Stack(
          children: [
            // Expanded content smoothly fades out
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: collapsed ? 0 : 1,
              child: IgnorePointer(
                ignoring: collapsed,
                child: SidebarExpanded(...),
              ),
            ),
            // Collapsed icon rail smoothly fades in
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: collapsed ? 1 : 0,
              child: IgnorePointer(
                ignoring: !collapsed,
                child: SidebarCollapsedRail(...),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
```

- **`OverflowBox` with fixed width constraint:** Ensures the internal widgets always measure themselves against a stable 280px width, completely preventing mid-animation text and slider wraps.
- **`ClipRect`:** Neatly clips overflowing pixels during the container width tween.
- **Cross-Fading `AnimatedOpacity`:** Transitions between the full panel and the icon rail in 120ms without visual tearing.

---

## Verification & Status

- **Automated Tests:** Covered by widget tests in `test/widget/game_page_test.dart` and `test/widget_test.dart`.
- **Zero Overflow Guarantee:** Verified responsive resize from 320px to 1920px with zero `RenderFlex` overflow warnings.
