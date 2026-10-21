import 'package:flutter/material.dart';
import '../../domain/entities/chess_opening.dart';
import 'game_theme.dart';

/// Dropdown to pick an opening to practice ("None" for free play). Picking
/// one (including re-picking the active one) starts a fresh game and
/// enforces that line for both sides until it runs out — see
/// docs/features/opening_book_follower.md.
class OpeningSelector extends StatelessWidget {
  final ChessOpening? selected;
  final ValueChanged<ChessOpening?> onChanged;

  const OpeningSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Opening',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButton<ChessOpening?>(
          key: const ValueKey('openingSelector'),
          value: selected,
          isExpanded: true,
          dropdownColor: kCard,
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: [
            const DropdownMenuItem<ChessOpening?>(
              value: null,
              child: Text('None', overflow: TextOverflow.ellipsis),
            ),
            for (final o in kOpenings)
              DropdownMenuItem<ChessOpening?>(
                value: o,
                child: Text(o.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
