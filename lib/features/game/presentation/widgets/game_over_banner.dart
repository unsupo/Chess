import 'package:flutter/material.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import 'game_theme.dart';

// ── Game Over / Draw Banner ───────────────────────────────────────────────────

class PlayerReviewCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String colorLabel;
  final PlayerGameReview review;
  final bool highlight;

  const PlayerReviewCard({
    super.key,
    required this.emoji,
    required this.name,
    required this.colorLabel,
    required this.review,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight ? kAccentFill : const Color(0xFF1A2B1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? kAccent : const Color(0xFF3A5A3A),
          width: highlight ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          Text(colorLabel, style: const TextStyle(color: kMuted, fontSize: 10)),
          const SizedBox(height: 8),
          const Text(
            'Performance ELO',
            style: TextStyle(color: kMuted, fontSize: 10),
          ),
          Text(
            '${review.estimatedElo}',
            style: TextStyle(
              color: highlight ? kAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Accuracy',
                style: TextStyle(color: kMuted, fontSize: 11),
              ),
              Text(
                '${review.accuracyPercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Avg. CPL',
                style: TextStyle(color: kMuted, fontSize: 11),
              ),
              Text(
                '${review.acpl.round()}',
                style: const TextStyle(
                  color: kMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GameOverBanner extends StatelessWidget {
  final String message;
  final bool isDraw;
  final VoidCallback onReview;
  final VoidCallback onNewGame;

  const GameOverBanner({
    super.key,
    required this.message,
    required this.isDraw,
    required this.onReview,
    required this.onNewGame,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kCard.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAccent, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isDraw ? Icons.handshake_outlined : Icons.emoji_events_outlined,
            color: kAccent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onReview,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            child: const Text(
              'Review',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onNewGame,
            style: TextButton.styleFrom(
              foregroundColor: kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text(
              'New Game',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
