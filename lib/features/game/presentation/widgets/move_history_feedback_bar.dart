import 'package:flutter/material.dart';
import '../../domain/usecases/game_review_analyzer.dart';
import 'game_theme.dart';

const kBrilliantMoveColor = Color(0xFF1BACA6);
const kGreatFindMoveColor = Color(0xFF5C8BB0);
const kBestMoveColor = Color(0xFF7BBF44);
const kBookMoveColor = Color(0xFFD5A47D);
const kInaccuracyColor = Color(0xFFF7C631);
const kMistakeColor = Color(0xFFFFA459);
const kBlunderColor = Color(0xFFFA412D);

Color classificationColor(MoveClassification c) {
  switch (c) {
    case MoveClassification.brilliant:
      return kBrilliantMoveColor;
    case MoveClassification.great:
      return kGreatFindMoveColor;
    case MoveClassification.best:
    case MoveClassification.good:
      return kBestMoveColor;
    case MoveClassification.book:
      return kBookMoveColor;
    case MoveClassification.inaccuracy:
      return kInaccuracyColor;
    case MoveClassification.mistake:
      return kMistakeColor;
    case MoveClassification.blunder:
      return kBlunderColor;
  }
}

/// Displays the opening name (`eco-opening-panel`), live evaluation score pill
/// (`score-text`), latest move feedback (`move-feedback-row`), and clickable
/// SAN move chips (`move-san`).
class MoveHistoryAndFeedbackBar extends StatelessWidget {
  final List<String> sanMoves;
  final int currentPly;
  final List<MoveClassification> classifications;
  final String evalScoreText;
  final int whiteCp;
  final String? openingName;
  final ValueChanged<int> onSelectPly;

  const MoveHistoryAndFeedbackBar({
    super.key,
    required this.sanMoves,
    required this.currentPly,
    required this.classifications,
    required this.evalScoreText,
    required this.whiteCp,
    required this.openingName,
    required this.onSelectPly,
  });

  @override
  Widget build(BuildContext context) {
    final currentClassification =
        (currentPly > 0 && currentPly - 1 < classifications.length)
        ? classifications[currentPly - 1]
        : null;
    final currentMoveSan = (currentPly > 0 && currentPly - 1 < sanMoves.length)
        ? sanMoves[currentPly - 1]
        : null;
    final isNegativeEval = whiteCp < 0 || evalScoreText.startsWith('-');

    return Container(
      key: const ValueKey('moveHistoryFeedbackBar'),
      color: kCard,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Evaluation score pill (`score-text`)
              Container(
                key: const ValueKey('evalScorePill'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isNegativeEval
                      ? const Color(0xFF403D39)
                      : const Color(0xFFF5F5F0),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: kBorderSubtle),
                ),
                child: Text(
                  evalScoreText,
                  style: TextStyle(
                    color: isNegativeEval ? Colors.white : kBg,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Opening name (`eco-opening-panel`)
              if (openingName != null) ...[
                Flexible(
                  child: Text(
                    openingName!,
                    key: const ValueKey('openingNameLabel'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              // Move feedback badge (`move-feedback-row`)
              if (currentMoveSan != null && currentClassification != null)
                Container(
                  key: const ValueKey('moveFeedbackBadge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: classificationColor(
                      currentClassification,
                    ).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: classificationColor(currentClassification),
                    ),
                  ),
                  child: Text(
                    '$currentMoveSan is ${currentClassification.label} ${currentClassification.symbol}',
                    style: TextStyle(
                      color: classificationColor(currentClassification),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          if (sanMoves.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 22,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: sanMoves.length,
                itemBuilder: (context, idx) {
                  final ply = idx + 1;
                  final isWhiteMove = idx.isEven;
                  final moveNum = (idx ~/ 2) + 1;
                  final san = sanMoves[idx];
                  final isSelected = ply == currentPly;
                  final cls = idx < classifications.length
                      ? classifications[idx]
                      : null;

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      key: ValueKey('movePly_$ply'),
                      onTap: () => onSelectPly(ply),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? kAccentFill : kBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? kAccent : kBorderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isWhiteMove)
                              Text(
                                '$moveNum. ',
                                style: const TextStyle(
                                  color: kMuted,
                                  fontSize: 10,
                                ),
                              ),
                            Text(
                              san,
                              style: TextStyle(
                                color: isSelected ? kAccent : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 10,
                              ),
                            ),
                            if (cls != null &&
                                cls != MoveClassification.good &&
                                cls != MoveClassification.book) ...[
                              const SizedBox(width: 2),
                              Text(
                                cls.symbol,
                                style: TextStyle(
                                  color: classificationColor(cls),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
