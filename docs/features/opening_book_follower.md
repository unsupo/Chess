# Feature: Opening Book Follower

**Status:** Built, matching this plan: 10 curated openings
(`lib/features/game/domain/entities/chess_opening.dart`), `setOpening`
always starts a fresh game, enforcement rejects off-book user moves
(`GameNotifier.onUserMove`'s ply-0 check) and the bot also plays the book
line on its own turns (`GameNotifier._pickBotMove`) so both sides rehearse
the exact line. UI: `_OpeningSelector` dropdown in the sidebar and the
narrow-viewport controls panel (not added to the collapsed icon rail,
matching the existing precedent of `mateSafetyN` also being omitted
there).

## Problem

The user wants to practice a specific named opening: pick one from a
dropdown (with a "None" option for free play), and once picked, the game
only lets them play moves that belong to that opening's book line —
off-book moves get rejected so they're forced to learn the correct
sequence, instead of accidentally wandering into a different opening.

## Proposed approach

### Data: a small curated opening list

No opening-book data exists in the repo yet. Rather than pull in a large
ECO database, hardcode a short, well-known starter set as UCI move
sequences (each is standard textbook theory, safe to hardcode without a
licensed dataset):

```dart
class ChessOpening {
  final String id;
  final String name;
  final List<String> uciMoves; // e.g. ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4']
  const ChessOpening({required this.id, required this.name, required this.uciMoves});
}

const kOpenings = [
  ChessOpening(id: 'italian', name: 'Italian Game', uciMoves: [...]),
  ChessOpening(id: 'ruy_lopez', name: 'Ruy Lopez', uciMoves: [...]),
  ChessOpening(id: 'sicilian', name: 'Sicilian Defense', uciMoves: [...]),
  ChessOpening(id: 'french', name: 'French Defense', uciMoves: [...]),
  ChessOpening(id: 'caro_kann', name: 'Caro-Kann Defense', uciMoves: [...]),
  ChessOpening(id: 'queens_gambit', name: "Queen's Gambit", uciMoves: [...]),
  ChessOpening(id: 'kings_indian', name: "King's Indian Defense", uciMoves: [...]),
  ChessOpening(id: 'english', name: 'English Opening', uciMoves: [...]),
  ChessOpening(id: 'london', name: 'London System', uciMoves: [...]),
  ChessOpening(id: 'scandinavian', name: 'Scandinavian Defense', uciMoves: [...]),
];
```

~6-8 plies (3-4 full moves) each — enough to establish the opening's
characteristic structure. New file:
`lib/features/game/domain/entities/chess_opening.dart`.

### Selecting an opening always starts a fresh game

"If you select an opening again it'll make sure you only do that
opening" — read as: picking an opening (including re-picking the one
that's already active) resets to a clean board with that opening tracked
from ply 0. This sidesteps the ambiguity of retroactively enforcing an
opening on a game already in progress (which could be unsatisfiable if
you're already several moves into something else). `GameNotifier`:

```dart
Future<void> setOpening(ChessOpening? opening) async {
  state = state.copyWith(selectedOpening: opening, clearSelectedOpening: opening == null);
  await newGame(); // clean board; _maybeBotMove() already handles bot-to-move-first if flipped
}
```

`GameState` gains `final ChessOpening? selectedOpening;` (null = "None",
free play — today's behavior, unchanged). `newGame()`/`loadFen()` should
carry `selectedOpening` through like the other settings fields
(`botElo`, `personality`, `boardFlipped`, `antiBlunderEnabled`), *except*
`loadFen()` probably shouldn't try to reconcile an arbitrary pasted FEN
against a book line — simplest: loading a FEN clears the selected opening
back to "None" rather than trying to make them consistent.

### Enforcement

Because the current ply count in a freshly-started, opening-tracked game
indexes directly into `selectedOpening.uciMoves`, no separate counter is
needed — `chess.history.length` (or equivalent from the `chess` package)
at the moment of the user's move gives the index to check against.

`onUserMove` currently only receives the resulting FEN
(`onUserMove(String newFen)`), reconstructed from `from`/`to` in
`game_page.dart`'s board `onMove` callback. Diffing two FENs back into a
UCI move to compare against the book is exactly the kind of fragile
inference this codebase got burned by once already this session (see
GOTCHAS #11) — cleaner to just pass the UCI move through directly instead
of re-deriving it:

```dart
// game_page.dart
onMove: (from, to, {promotion}) {
  ref.read(gameProvider.notifier).onUserMove('$from$to${promotion ?? ""}');
}
```

```dart
// game_provider.dart — onUserMove becomes:
Future<void> onUserMove(String uciMove) async {
  final preMoveFen = state.fen;
  final newFen = _applyUci(preMoveFen, uciMove); // already exists
  ...
  final opening = state.selectedOpening;
  if (opening != null) {
    final plyIndex = chess_lib.Chess()..load(preMoveFen); // then .history.length, or track a ply counter in GameState
    if (plyIndex < opening.uciMoves.length && uciMove != opening.uciMoves[plyIndex]) {
      state = state.copyWith(
        isEvaluating: false,
        errorMessage: "That's not the ${opening.name} — try again.",
        clearLastMove: true,
      ); // move is simply never applied — board already reflects preMoveFen
      return;
    }
    // past the end of the stored line (or it matched) — normal play / blunder check resumes
  }
  if (state.antiBlunderEnabled) { ... existing blunder check ... }
  ...
}
```

Opening-conformance is checked **before** the (optional) blunder check —
if a move is both off-book and a blunder, the opening message is the more
specific, relevant one to show. The two checks are otherwise independent:
an on-book move can still be rejected as a blunder if anti-blunder is on,
and once the ply count exceeds the stored book length, enforcement simply
stops applying for the rest of that game (free play resumes — no attempt
to extend book tracking indefinitely).

### UI

A dropdown in the sidebar (`_SidebarExpanded`, `docs/features/controls_side_panel.md`'s
sidebar), e.g. `DropdownButton<ChessOpening?>` with `kOpenings` plus a
leading "None" entry, wired to `setOpening`. Needs a corresponding entry
in the collapsed rail (an icon showing whether an opening is active, same
pattern as the anti-blunder toggle's rail icon) and in the narrow/bottom
`_ControlsPanel` layout for viewport-size parity with every other control.

## Decisions baked in as reasonable calls

1. Starter set: the 10 openings listed above, ~6-8 plies each, standard
   main-line theory.
2. Picking an opening (including re-picking the active one) always starts
   a fresh game — no retroactive enforcement mid-game.
3. Loading a FEN clears the selected opening back to "None" rather than
   trying to reconcile it against a book line.
4. Enforcement is a hard reject-and-revert (matches the existing blunder
   UX exactly: `errorMessage` + board snaps back), not a soft hint —
   matches "make sure you only do that opening."
5. Once past the end of the stored line, tracking silently stops; no
   "book complete!" indicator in v1 (nice-to-have, not essential).
6. Independent of, and checked before, the anti-blunder toggle.

## Likely touched files

- `lib/features/game/domain/entities/chess_opening.dart` — new
- `lib/features/game/presentation/providers/game_provider.dart` — `GameState.selectedOpening`, `setOpening`, `onUserMove` signature change + conformance check
- `lib/features/game/presentation/pages/game_page.dart` — dropdown in sidebar + collapsed-rail indicator + narrow-layout `_ControlsPanel`, updated `onMove` callback
- `docs/features/personalities.md` or a new doc section — n/a, this is independent of personalities
