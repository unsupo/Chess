import 'package:flutter/material.dart';
import '../../domain/entities/bot_personality.dart';
import '../../domain/entities/chess_opening.dart';
import '../../domain/entities/time_control.dart';
import 'bot_crowns_and_selectors.dart';
import 'game_theme.dart';
import 'game_toggles.dart';
import 'opening_selector.dart';
import 'player_bar.dart';

// ── Controls ──────────────────────────────────────────────────────────────────

class ControlsPanel extends StatelessWidget {
  final int elo;
  final BotPersonality selectedPersonality;
  final ValueChanged<BotPersonality> onPersonalitySelected;
  final ValueChanged<int> onEloChanged;
  final VoidCallback onNewGame;
  final VoidCallback onFlipBoard;
  final VoidCallback onLoadFen;
  final bool canStepBack;
  final bool canStepForward;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final bool lockHistory;
  final ValueChanged<bool> onLockHistoryChanged;
  final bool antiBlunderEnabled;
  final ValueChanged<bool> onAntiBlunderChanged;
  final bool mateSafetyEnabled;
  final int mateSafetyN;
  final ValueChanged<bool> onMateSafetyEnabledChanged;
  final ValueChanged<int> onMateSafetyNChanged;
  final PlaySide playSide;
  final ValueChanged<PlaySide> onPlaySideChanged;
  final TimeControl timeControl;
  final ValueChanged<TimeControl> onTimeControlChanged;
  final Map<String, int> botCrowns;
  final ChessOpening? selectedOpening;
  final ValueChanged<ChessOpening?> onOpeningChanged;
  final bool showEvalBar;
  final ValueChanged<bool> onShowEvalBarChanged;

  const ControlsPanel({
    super.key,
    required this.elo,
    required this.selectedPersonality,
    required this.onPersonalitySelected,
    required this.onEloChanged,
    required this.onNewGame,
    required this.onFlipBoard,
    required this.onLoadFen,
    required this.canStepBack,
    required this.canStepForward,
    required this.onStepBack,
    required this.onStepForward,
    required this.lockHistory,
    required this.onLockHistoryChanged,
    required this.antiBlunderEnabled,
    required this.onAntiBlunderChanged,
    required this.mateSafetyEnabled,
    required this.mateSafetyN,
    required this.onMateSafetyEnabledChanged,
    required this.onMateSafetyNChanged,
    required this.playSide,
    required this.onPlaySideChanged,
    required this.timeControl,
    required this.onTimeControlChanged,
    required this.botCrowns,
    required this.selectedOpening,
    required this.onOpeningChanged,
    required this.showEvalBar,
    required this.onShowEvalBarChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        color: kCard,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AntiBlunderToggle(
                enabled: antiBlunderEnabled,
                onChanged: onAntiBlunderChanged,
              ),
              HistoryLockToggle(
                locked: lockHistory,
                onChanged: onLockHistoryChanged,
              ),
              MateSafetyControl(
                enabled: mateSafetyEnabled,
                n: mateSafetyN,
                onEnabledChanged: onMateSafetyEnabledChanged,
                onNChanged: onMateSafetyNChanged,
              ),
              const SizedBox(height: 6),
              EvalBarToggle(
                shown: showEvalBar,
                onChanged: onShowEvalBarChanged,
              ),
              const SizedBox(height: 6),
              OpeningSelector(
                selected: selectedOpening,
                onChanged: onOpeningChanged,
              ),
              const SizedBox(height: 6),
              PlaySideSelectorWidget(
                selected: playSide,
                onChanged: onPlaySideChanged,
              ),
              const SizedBox(height: 6),
              TimeControlSelectorWidget(
                selected: timeControl,
                onChanged: onTimeControlChanged,
              ),
              const SizedBox(height: 8),
              // Personality picker
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Opponent',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    selectedPersonality.category,
                    style: const TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kPersonalities.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = kPersonalities[i];
                    final selected = p.id == selectedPersonality.id;
                    final crowns = botCrowns[p.id] ?? 0;
                    return GestureDetector(
                      onTap: () => onPersonalitySelected(p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 64,
                        decoration: BoxDecoration(
                          color: selected
                              ? kAccentFill
                              : const Color(0xFF1A2B1A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? kAccent : const Color(0xFF3A5A3A),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(p.emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(height: 2),
                            Text(
                              p.name.split(' ').last,
                              style: TextStyle(
                                color: selected ? kAccent : kMuted,
                                fontSize: 9,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            BotCrownsWidget(crowns: crowns, size: 8),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Difficulty row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Difficulty',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: kAccentFill,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: kAccentBorder),
                    ),
                    child: Text(
                      '${eloLabel(elo)}  ·  $elo',
                      style: const TextStyle(
                        color: kAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('difficultySlider'),
                value: elo.toDouble(),
                min: 0,
                max: 2800,
                divisions: 56,
                onChanged: (val) => onEloChanged(val.toInt()),
              ),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onNewGame,
                      child: const Text(
                        'New Game',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  HistoryStepBtn(
                    icon: Icons.arrow_back_ios_new,
                    tooltip: 'Previous move',
                    enabled: canStepBack,
                    onTap: onStepBack,
                  ),
                  const SizedBox(width: 4),
                  HistoryStepBtn(
                    icon: Icons.arrow_forward_ios,
                    tooltip: 'Next move',
                    enabled: canStepForward,
                    onTap: onStepForward,
                  ),
                  const SizedBox(width: 8),
                  IconBtn(
                    icon: Icons.swap_vert,
                    tooltip: 'Flip board',
                    onTap: onFlipBoard,
                  ),
                  const SizedBox(width: 8),
                  IconBtn(
                    icon: Icons.edit_outlined,
                    tooltip: 'FEN / PGN',
                    onTap: onLoadFen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const IconBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A2B1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A5A3A)),
          ),
          child: Icon(icon, color: kMuted, size: 20),
        ),
      ),
    );
  }
}
