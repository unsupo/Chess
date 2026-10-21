class BotPersonality {
  final String id;
  final String name;
  final String emoji;
  final String tagline;
  final String greeting;
  final int defaultElo;
  final String category;

  const BotPersonality({
    required this.id,
    required this.name,
    required this.emoji,
    required this.tagline,
    required this.greeting,
    required this.defaultElo,
    this.category = 'Beginner',
  });
}

const kDefaultPersonality = BotPersonality(
  id: 'martin',
  name: 'Martin',
  emoji: '🤖',
  tagline: 'Friendly Beginner',
  greeting:
      "Welcome! Let's play. I'll undo your blunders so you can find the best move.",
  defaultElo: 900,
  category: 'Beginner',
);

const kPersonalities = [
  kDefaultPersonality,
  BotPersonality(
    id: 'aggressor',
    name: 'The Aggressor',
    emoji: '⚔️',
    tagline: 'Fast-Mate & Trap Hunter',
    greeting:
        "I attack until something breaks. Watch your f7 square—your king will not survive!",
    defaultElo: 1400,
    category: 'Intermediate',
  ),
  BotPersonality(
    id: 'pawn_pusher',
    name: 'The Pawn Pusher',
    emoji: '♟️',
    tagline: 'Relentless Pawn Storm',
    greeting:
        "Pawns are the soul of chess! Watch my phalanx march straight down the board.",
    defaultElo: 1300,
    category: 'Intermediate',
  ),
  BotPersonality(
    id: 'strategist',
    name: 'The Strategist',
    emoji: '📚',
    tagline: 'Positional Master',
    greeting: "Every move must serve the position. Patience wins games.",
    defaultElo: 1700,
    category: 'Advanced',
  ),
  BotPersonality(
    id: 'trickster',
    name: 'The Trickster',
    emoji: '🎭',
    tagline: 'Trap Setter',
    greeting: "Hehehe… I've already set a trap. Can you see it?",
    defaultElo: 2000,
    category: 'Advanced',
  ),
  BotPersonality(
    id: 'defender',
    name: 'The Defender',
    emoji: '🛡️',
    tagline: 'Fortress Builder',
    greeting: "Nothing gets through. I don't lose pieces — I outlast you.",
    defaultElo: 1500,
    category: 'Intermediate',
  ),
  BotPersonality(
    id: 'crusher',
    name: 'The Crusher',
    emoji: '👑',
    tagline: 'Relentless GM',
    greeting: "I play for the win. Every. Single. Time.",
    defaultElo: 2400,
    category: 'Master',
  ),
];
