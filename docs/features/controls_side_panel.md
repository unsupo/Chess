# Feature: Collapsible Side Panel for Controls

**Status:** Planned — not built. Written to align on approach before implementation.

## Problem

`GamePage` currently stacks everything in one vertical `Column`:
`_BotPanel` → `ChessBoardWidget` → `_PlayerBar` → `_ControlsPanel` (opponent
picker, difficulty slider, New Game / flip / load-FEN buttons), with the
board sized by:

```dart
final boardSize = min(
  constraints.maxWidth,
  constraints.maxHeight - _botPanelH - _playerBarH - _controlsH,
).clamp(100.0, 600.0);
```

(`lib/features/game/presentation/pages/game_page.dart:90-95`, constants at
the top of the file: `_botPanelH = 100`, `_playerBarH = 50`,
`_controlsH = 220`.)

On any viewport that isn't tall and narrow, `_controlsH` eats a fixed 220px
of **vertical** space the board could otherwise use, and on short viewports
the controls' own content already overflows that budget — confirmed by the
`flutter test` run in this session (`A RenderFlex overflowed by 23 pixels`
from `_ControlsPanel`'s `Column`, see `docs/GOTCHAS.md`). The user wants the
controls moved to the **right** as a panel that can collapse, so the board
can use the full available space (width-bound instead of height-bound).

## Proposed approach

Replace the outer `Column` with a `Row`: a left side holding
`_BotPanel` / `ChessBoardWidget` / `_PlayerBar` stacked vertically (as
today, minus `_ControlsPanel`), and a right-hand sidebar holding
`_ControlsPanel`'s content.

```
┌─────────────────────────────┬──────────────┐
│ _BotPanel                   │              │
│                              │  Controls    │
│        ChessBoardWidget      │  (collapsible)│
│                              │              │
│ _PlayerBar                   │              │
└─────────────────────────────┴──────────────┘
```

- Board sizing becomes width-first instead of height-first: `boardSize =
  min(constraints.maxWidth - sidebarWidth, constraints.maxHeight -
  _botPanelH - _playerBarH)`, where `sidebarWidth` is 0 when collapsed.
- Wrap the sidebar in `AnimatedContainer` (width + `curve`/`duration`) so
  collapsing/expanding animates rather than snapping.
- A collapse/expand toggle button (icon, e.g. `Icons.chevron_right` /
  `Icons.chevron_left`) sits on the sidebar's edge.
- When collapsed, the sidebar's content needs to either disappear entirely
  or shrink to an icon-only rail (see decisions below) — collapsing a
  `Column` of text + a `Slider` to zero width without clipping/overflow
  errors needs the content wrapped so it doesn't try to lay out at
  negative/zero width mid-animation (e.g. `ClipRect` + `Align` or fading
  content out before the width animation finishes).
- `_ControlsPanel`'s existing content (personality `ListView`, difficulty
  `Slider` + row, action buttons) likely needs to go from a horizontal
  scroller + fixed-height rows to a narrower vertical layout, since a
  sidebar is narrower than the current full-width bottom panel. The
  personality picker in particular (`ListView.separated`,
  `scrollDirection: Axis.horizontal`) may want to become vertical or wrap.

## Decisions needed

1. **Breakpoint** — does the side-panel layout apply unconditionally, or
   only above some width (e.g. keep today's bottom-panel layout on narrow/
   phone-width viewports and switch to the sidebar on wider ones)? This
   repo's only configured run target so far is macOS desktop, but the
   `chess` in `GEMINI.md`'s stack list targets mobile-first (Android/iOS)
   plus web — worth confirming before locking in a desktop-only layout.
2. **Collapsed state** — fully hidden (width 0; needs a way to reopen,
   e.g. a small floating button) vs. a slim icon-only rail (e.g. 48px,
   showing New Game / flip / load-FEN icons with slider + personality
   picker hidden)?
3. **Default on launch** — expanded or collapsed?
4. **Persistence** — remember the user's collapsed/expanded choice across
   app restarts (would need local storage; nothing in this project
   persists state today), or always start the same way?
5. **Sidebar width** when expanded — current bottom panel has no fixed
   width constraint to borrow from; need a concrete value (suggest
   260–300px, open to adjustment once it's on screen).
6. **Personality picker** — keep horizontal scroll inside the narrower
   sidebar, or switch to a vertical list?

## Likely touched files

- `lib/features/game/presentation/pages/game_page.dart` — outer layout
  (`Column` → `Row`), board-size calculation, `_ControlsPanel` internal
  layout, new collapse state (`bool` in `_GamePageState`, no provider
  changes needed since this is pure UI state).

## Non-goals

- Not fixing the pre-existing `_ControlsPanel` `RenderFlex` overflow by
  patching the current bottom-panel layout — the sidebar redesign
  supersedes it. If the sidebar layout is deferred, that overflow should
  be tracked as its own fix.
- No changes to `game_provider.dart` — this is presentation-layer only.
