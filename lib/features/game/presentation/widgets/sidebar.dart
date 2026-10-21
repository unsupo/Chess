import 'package:flutter/material.dart';
import '../../domain/entities/bot_personality.dart';
import '../../domain/entities/chess_opening.dart';
import '../../domain/entities/time_control.dart';
import 'bot_crowns_and_selectors.dart';
import 'controls_panel.dart';
import 'game_theme.dart';
import 'game_toggles.dart';
import 'opening_selector.dart';
import 'player_bar.dart';

// side-panel layout: used instead of the bottom controls strip once the
// viewport is wide enough that a right-hand sidebar doesn't cramp the board.
const _sidebarWidthExpanded = 280.0;
const _sidebarWidthCollapsed = 56.0;
const _sidebarAnimDuration = Duration(milliseconds: 200);

// ── Sidebar (wide-viewport layout) ──────────────────────────────────────────

class Sidebar extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggle;
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

  const Sidebar({
    super.key,
    required this.collapsed,
    required this.onToggle,
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
    return AnimatedContainer(
      duration: _sidebarAnimDuration,
      curve: Curves.easeInOut,
      width: collapsed ? _sidebarWidthCollapsed : _sidebarWidthExpanded,
      color: kCard,
      // The content below is always laid out at the full expanded width
      // (via OverflowBox) so it never has to render into a near-zero-width
      // box mid-animation, which would overflow. ClipRect then hides
      // whatever sticks out past the AnimatedContainer's current width.
      child: ClipRect(
        child: OverflowBox(
          minWidth: _sidebarWidthExpanded,
          maxWidth: _sidebarWidthExpanded,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _sidebarWidthExpanded,
            child: Stack(
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: collapsed ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: collapsed,
                    child: SidebarExpanded(
                      onToggle: onToggle,
                      elo: elo,
                      selectedPersonality: selectedPersonality,
                      onPersonalitySelected: onPersonalitySelected,
                      onEloChanged: onEloChanged,
                      onNewGame: onNewGame,
                      onFlipBoard: onFlipBoard,
                      onLoadFen: onLoadFen,
                      canStepBack: canStepBack,
                      canStepForward: canStepForward,
                      onStepBack: onStepBack,
                      onStepForward: onStepForward,
                      lockHistory: lockHistory,
                      onLockHistoryChanged: onLockHistoryChanged,
                      antiBlunderEnabled: antiBlunderEnabled,
                      onAntiBlunderChanged: onAntiBlunderChanged,
                      mateSafetyEnabled: mateSafetyEnabled,
                      mateSafetyN: mateSafetyN,
                      onMateSafetyEnabledChanged: onMateSafetyEnabledChanged,
                      onMateSafetyNChanged: onMateSafetyNChanged,
                      playSide: playSide,
                      onPlaySideChanged: onPlaySideChanged,
                      timeControl: timeControl,
                      onTimeControlChanged: onTimeControlChanged,
                      botCrowns: botCrowns,
                      selectedOpening: selectedOpening,
                      onOpeningChanged: onOpeningChanged,
                      showEvalBar: showEvalBar,
                      onShowEvalBarChanged: onShowEvalBarChanged,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: collapsed ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !collapsed,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: _sidebarWidthCollapsed,
                        child: SidebarCollapsedRail(
                          onToggle: onToggle,
                          onNewGame: onNewGame,
                          onFlipBoard: onFlipBoard,
                          onLoadFen: onLoadFen,
                          canStepBack: canStepBack,
                          canStepForward: canStepForward,
                          onStepBack: onStepBack,
                          onStepForward: onStepForward,
                          lockHistory: lockHistory,
                          onLockHistoryChanged: onLockHistoryChanged,
                          antiBlunderEnabled: antiBlunderEnabled,
                          onAntiBlunderChanged: onAntiBlunderChanged,
                          mateSafetyEnabled: mateSafetyEnabled,
                          onMateSafetyEnabledChanged:
                              onMateSafetyEnabledChanged,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollapseToggleButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onTap;

  const CollapseToggleButton({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Expand panel' : 'Collapse panel',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            collapsed ? Icons.chevron_left : Icons.chevron_right,
            color: kMuted,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class SidebarExpanded extends StatelessWidget {
  final VoidCallback onToggle;
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

  const SidebarExpanded({
    super.key,
    required this.onToggle,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              CollapseToggleButton(collapsed: false, onTap: onToggle),
            ],
          ),
          const SizedBox(height: 4),
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
          const SizedBox(height: 4),
          EvalBarToggle(shown: showEvalBar, onChanged: onShowEvalBarChanged),
          const SizedBox(height: 6),
          OpeningSelector(
            selected: selectedOpening,
            onChanged: onOpeningChanged,
          ),
          const SizedBox(height: 4),
          PlaySideSelectorWidget(
            selected: playSide,
            onChanged: onPlaySideChanged,
          ),
          const SizedBox(height: 6),
          TimeControlSelectorWidget(
            selected: timeControl,
            onChanged: onTimeControlChanged,
          ),
          const SizedBox(height: 6),
          const Text(
            'Opponent',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          // Vertical list — a sidebar is too narrow for the horizontal
          // scroller the bottom-panel layout uses.
          Expanded(
            child: ListView.separated(
              itemCount: kPersonalities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, i) {
                final p = kPersonalities[i];
                final selected = p.id == selectedPersonality.id;
                final crowns = botCrowns[p.id] ?? 0;
                return GestureDetector(
                  onTap: () => onPersonalitySelected(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? kAccentFill : const Color(0xFF1A2B1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? kAccent : const Color(0xFF3A5A3A),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(p.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${p.name} · ${p.category}',
                            style: TextStyle(
                              color: selected ? kAccent : kMuted,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        BotCrownsWidget(crowns: crowns, size: 10),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Difficulty',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              key: const ValueKey('difficultySlider'),
              value: elo.toDouble(),
              min: 0,
              max: 2800,
              divisions: 56,
              onChanged: (val) => onEloChanged(val.toInt()),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNewGame,
              child: const Text(
                'New Game',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              HistoryStepBtn(
                icon: Icons.arrow_back_ios_new,
                tooltip: 'Previous move',
                enabled: canStepBack,
                onTap: onStepBack,
              ),
              HistoryStepBtn(
                icon: Icons.arrow_forward_ios,
                tooltip: 'Next move',
                enabled: canStepForward,
                onTap: onStepForward,
              ),
              IconBtn(
                icon: Icons.swap_vert,
                tooltip: 'Flip board',
                onTap: onFlipBoard,
              ),
              IconBtn(
                icon: Icons.edit_outlined,
                tooltip: 'FEN / PGN',
                onTap: onLoadFen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SidebarCollapsedRail extends StatelessWidget {
  final VoidCallback onToggle;
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
  final ValueChanged<bool> onMateSafetyEnabledChanged;

  const SidebarCollapsedRail({
    super.key,
    required this.onToggle,
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
    required this.onMateSafetyEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          CollapseToggleButton(collapsed: true, onTap: onToggle),
          const SizedBox(height: 16),
          IconBtn(
            icon: antiBlunderEnabled ? Icons.shield : Icons.shield_outlined,
            tooltip: antiBlunderEnabled
                ? 'Anti-Blunder: on'
                : 'Anti-Blunder: off',
            onTap: () => onAntiBlunderChanged(!antiBlunderEnabled),
          ),
          const SizedBox(height: 10),
          IconBtn(
            icon: lockHistory ? Icons.lock_outline : Icons.lock_open_outlined,
            tooltip: lockHistory
                ? 'View-Only History: on'
                : 'View-Only History: off (editable)',
            onTap: () => onLockHistoryChanged(!lockHistory),
          ),
          const SizedBox(height: 10),
          IconBtn(
            icon: mateSafetyEnabled ? Icons.gpp_good : Icons.gpp_maybe_outlined,
            tooltip: mateSafetyEnabled ? 'Mate Safety: on' : 'Mate Safety: off',
            onTap: () => onMateSafetyEnabledChanged(!mateSafetyEnabled),
          ),
          const SizedBox(height: 10),
          HistoryStepBtn(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Previous move',
            enabled: canStepBack,
            onTap: onStepBack,
          ),
          const SizedBox(height: 8),
          HistoryStepBtn(
            icon: Icons.arrow_forward_ios,
            tooltip: 'Next move',
            enabled: canStepForward,
            onTap: onStepForward,
          ),
          const SizedBox(height: 10),
          IconBtn(
            icon: Icons.restart_alt,
            tooltip: 'New Game',
            onTap: onNewGame,
          ),
          const SizedBox(height: 10),
          IconBtn(
            icon: Icons.swap_vert,
            tooltip: 'Flip board',
            onTap: onFlipBoard,
          ),
          const SizedBox(height: 10),
          IconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'FEN / PGN',
            onTap: onLoadFen,
          ),
        ],
      ),
    );
  }
}
