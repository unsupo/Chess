import 'package:flutter/material.dart';
import '../../../../core/widgets/chess_board/chess_board_widget.dart';
import '../providers/game_provider.dart';
import 'game_theme.dart';
import 'ticker_clock_widget.dart';

// ── Player bar ────────────────────────────────────────────────────────────────

class PlayerBar extends StatelessWidget {
  final bool flipped;
  final SideMaterial material;
  final bool canStepBack;
  final bool canStepForward;
  final int currentPly;
  final int totalPlies;
  final bool isViewingHistory;
  final bool lockHistory;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final TimeControl timeControl;
  final int playerTimeMs;
  final bool isPlayerClockActive;

  const PlayerBar({
    super.key,
    required this.flipped,
    required this.material,
    required this.canStepBack,
    required this.canStepForward,
    required this.currentPly,
    required this.totalPlies,
    required this.isViewingHistory,
    required this.lockHistory,
    required this.onStepBack,
    required this.onStepForward,
    required this.timeControl,
    required this.playerTimeMs,
    required this.isPlayerClockActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCard,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF2E4A2E),
            child: const Text('👤', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (isViewingHistory) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: kAccentFill,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kAccentBorder),
                      ),
                      child: Text(
                        lockHistory
                            ? 'Ply $currentPly/$totalPlies (View Only)'
                            : 'Ply $currentPly/$totalPlies (Editable)',
                        style: const TextStyle(
                          color: kAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'Playing as ${flipped ? "Black" : "White"}',
                style: const TextStyle(color: kMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(width: 8),
          HistoryStepBtn(
            key: const ValueKey('playerBarStepBackButton'),
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Previous move',
            enabled: canStepBack,
            onTap: onStepBack,
          ),
          const SizedBox(width: 4),
          HistoryStepBtn(
            key: const ValueKey('playerBarStepForwardButton'),
            icon: Icons.arrow_forward_ios,
            tooltip: 'Next move',
            enabled: canStepForward,
            onTap: onStepForward,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: CapturedPiecesBar(
                key: const ValueKey('playerCapturedBar'),
                material: material,
              ),
            ),
          ),
          const SizedBox(width: 8),
          MoveTimeWidget(
            key: const ValueKey('playerClockBadge'),
            timeControl: timeControl,
            timeMs: playerTimeMs,
            isActive: isPlayerClockActive,
            isDarkTheme: false,
          ),
        ],
      ),
    );
  }
}

class HistoryStepBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const HistoryStepBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2B1A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: enabled ? kAccentBorder : const Color(0xFF3A5A3A),
              ),
            ),
            child: Icon(icon, color: enabled ? kAccent : kMuted, size: 15),
          ),
        ),
      ),
    );
  }
}

class CapturedPiecesBar extends StatelessWidget {
  final SideMaterial material;

  const CapturedPiecesBar({super.key, required this.material});

  @override
  Widget build(BuildContext context) {
    final ptsLabel =
        '${material.capturedScore} ${material.capturedScore == 1 ? 'pt' : 'pts'}';
    final diffLabel = material.netAdvantage > 0
        ? ' (+${material.netAdvantage})'
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (material.capturedPieces.isNotEmpty) ...[
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFD8E4D0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Wrap(
                spacing: -3,
                runSpacing: 2,
                children: [
                  for (final code in material.capturedPieces)
                    buildChessPiece(code, 16),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: material.netAdvantage > 0
                  ? kAccentFill
                  : const Color(0xFF1A2B1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: material.netAdvantage > 0
                    ? kAccentBorder
                    : const Color(0xFF3A5A3A),
              ),
            ),
            child: Text(
              '$ptsLabel$diffLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: material.netAdvantage > 0 ? kAccent : kMuted,
                fontWeight: material.netAdvantage > 0
                    ? FontWeight.bold
                    : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
