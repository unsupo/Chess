import 'package:flutter/material.dart';
import '../../domain/entities/bot_personality.dart';
import '../providers/game_provider.dart';
import 'bot_crowns_and_selectors.dart';
import 'game_theme.dart';
import 'player_bar.dart';
import 'ticker_clock_widget.dart';

// ── Bot panel ─────────────────────────────────────────────────────────────────

class BotPanel extends StatelessWidget {
  final BotPersonality personality;
  final int botElo;
  final bool isThinking;
  final SideMaterial material;
  final int crowns;
  final TimeControl timeControl;
  final int botTimeMs;
  final bool isBotClockActive;

  const BotPanel({
    super.key,
    required this.personality,
    required this.botElo,
    required this.isThinking,
    required this.material,
    required this.crowns,
    required this.timeControl,
    required this.botTimeMs,
    required this.isBotClockActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCard,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF2E4A2E),
            child: Text(
              personality.emoji,
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      personality.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    BotCrownsWidget(
                      key: const ValueKey('botPanelCrowns'),
                      crowns: crowns,
                      size: 11,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${eloLabel(botElo)} · $botElo',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isThinking)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kAccent,
                          ),
                        ),
                      ),
                    MoveTimeWidget(
                      key: const ValueKey('botClockBadge'),
                      timeControl: timeControl,
                      timeMs: botTimeMs,
                      isActive: isBotClockActive,
                      isDarkTheme: true,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    color: kBubble,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    personality.greeting,
                    style: const TextStyle(
                      color: Color(0xFF1A2B1A),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                CapturedPiecesBar(
                  key: const ValueKey('botCapturedBar'),
                  material: material,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
