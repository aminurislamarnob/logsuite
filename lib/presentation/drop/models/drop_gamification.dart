class DropBadge {
  final String id;
  final String title;
  final String description;
  final String iconEmoji;
  final int xpReward;

  const DropBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.iconEmoji,
    required this.xpReward,
  });

  static const List<DropBadge> allBadges = [
    DropBadge(
      id: 'first_drop',
      title: 'First Capture',
      description: 'Saved your very first drop item',
      iconEmoji: '🎯',
      xpReward: 25,
    ),
    DropBadge(
      id: 'tag_architect',
      title: 'Tag Architect',
      description: 'Organized drops using hashtags',
      iconEmoji: '🏷️',
      xpReward: 30,
    ),
    DropBadge(
      id: 'inbox_zero',
      title: 'Inbox Zero Hero',
      description: 'Cleared your drop inbox completely',
      iconEmoji: '🧹',
      xpReward: 50,
    ),
    DropBadge(
      id: 'action_taker',
      title: 'Action Taker',
      description: 'Converted a drop into an actionable task',
      iconEmoji: '🚀',
      xpReward: 35,
    ),
    DropBadge(
      id: 'scholar',
      title: 'Knowledge Scholar',
      description: 'Converted a drop into a rich note',
      iconEmoji: '📚',
      xpReward: 35,
    ),
    DropBadge(
      id: 'curator',
      title: 'Master Curator',
      description: 'Starred 3 or more favorite drops',
      iconEmoji: '⭐',
      xpReward: 30,
    ),
    DropBadge(
      id: 'streak_3',
      title: 'Consistent Collector',
      description: 'Maintained a 3-day capture streak',
      iconEmoji: '🔥',
      xpReward: 50,
    ),
    DropBadge(
      id: 'power_collector',
      title: 'Power Collector',
      description: 'Captured 10 or more drop items',
      iconEmoji: '📦',
      xpReward: 60,
    ),
    DropBadge(
      id: 'triage_specialist',
      title: 'Triage Specialist',
      description: 'Triaged 5 drops to archive or action',
      iconEmoji: '⚡',
      xpReward: 40,
    ),
  ];
}

class DropGamificationStats {
  final int xp;
  final int currentStreak;
  final int bestStreak;
  final String? lastActiveDate;
  final int totalDropsCaptured;
  final int totalDropsTriaged;
  final int totalDropsStarred;
  final int inboxZeroCount;
  final Set<String> unlockedBadgeIds;

  const DropGamificationStats({
    this.xp = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastActiveDate,
    this.totalDropsCaptured = 0,
    this.totalDropsTriaged = 0,
    this.totalDropsStarred = 0,
    this.inboxZeroCount = 0,
    this.unlockedBadgeIds = const {},
  });

  int get level {
    if (xp >= 700) return 5;
    if (xp >= 350) return 4;
    if (xp >= 150) return 3;
    if (xp >= 50) return 2;
    return 1;
  }

  String get levelTitle {
    switch (level) {
      case 5:
        return 'Knowledge Architect';
      case 4:
        return 'Triage Master';
      case 3:
        return 'Insight Hunter';
      case 2:
        return 'Active Gatherer';
      default:
        return 'Novice Collector';
    }
  }

  int get currentLevelFloorXp {
    switch (level) {
      case 5:
        return 700;
      case 4:
        return 350;
      case 3:
        return 150;
      case 2:
        return 50;
      default:
        return 0;
    }
  }

  int get nextLevelXp {
    switch (level) {
      case 5:
        return 1200;
      case 4:
        return 700;
      case 3:
        return 350;
      case 2:
        return 150;
      default:
        return 50;
    }
  }

  double get levelProgress {
    final floor = currentLevelFloorXp;
    final ceiling = nextLevelXp;
    if (xp >= ceiling) return 1.0;
    final range = ceiling - floor;
    if (range <= 0) return 1.0;
    return ((xp - floor) / range).clamp(0.0, 1.0);
  }

  bool isBadgeUnlocked(String badgeId) => unlockedBadgeIds.contains(badgeId);

  DropGamificationStats copyWith({
    int? xp,
    int? currentStreak,
    int? bestStreak,
    String? lastActiveDate,
    int? totalDropsCaptured,
    int? totalDropsTriaged,
    int? totalDropsStarred,
    int? inboxZeroCount,
    Set<String>? unlockedBadgeIds,
  }) {
    return DropGamificationStats(
      xp: xp ?? this.xp,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      totalDropsCaptured: totalDropsCaptured ?? this.totalDropsCaptured,
      totalDropsTriaged: totalDropsTriaged ?? this.totalDropsTriaged,
      totalDropsStarred: totalDropsStarred ?? this.totalDropsStarred,
      inboxZeroCount: inboxZeroCount ?? this.inboxZeroCount,
      unlockedBadgeIds: unlockedBadgeIds ?? this.unlockedBadgeIds,
    );
  }
}

class GamificationReward {
  final int xpGained;
  final String reason;
  final List<DropBadge> unlockedBadges;
  final bool didLevelUp;
  final int newLevel;
  final String newLevelTitle;
  final bool streakExtended;
  final int streakCount;

  const GamificationReward({
    required this.xpGained,
    required this.reason,
    this.unlockedBadges = const [],
    this.didLevelUp = false,
    this.newLevel = 1,
    this.newLevelTitle = '',
    this.streakExtended = false,
    this.streakCount = 0,
  });
}
