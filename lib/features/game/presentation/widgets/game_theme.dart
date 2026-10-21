import 'package:flutter/material.dart';

// chess.com bot-play forest palette — shared across the game screen's
// widgets. Previously duplicated (under different names) in both
// game_page.dart and chess_feature_widgets.dart; consolidated here so every
// widget imports one shared copy instead of redeclaring its own.
const kBg = Color(0xFF1A2B1A);
const kCard = Color(0xFF243324);
const kAccent = Color(0xFF7BBF44);
const kMuted = Color(0xFF8AAD8A);
const kAccentFill = Color(0x287BBF44);
const kAccentBorder = Color(0x647BBF44);
const kBubble = Color(0xFFF5F5F0);
const kBorderSubtle = Color(0xFF3A5A3A);

/// Difficulty-tier label for a bot ELO. Shared by `BotPanel`,
/// `ControlsPanel`, and `SidebarExpanded` — previously triplicated
/// identically across all three during the phase-1 widget file split (see
/// docs/features/done/refactor_01_widget_file_split.md), consolidated here.
String eloLabel(int elo) {
  if (elo < 250) return 'Trying to Lose';
  if (elo < 700) return 'Very Easy';
  if (elo < 1000) return 'Beginner';
  if (elo < 1400) return 'Intermediate';
  if (elo < 1800) return 'Advanced';
  if (elo < 2200) return 'Expert';
  return 'Master';
}
