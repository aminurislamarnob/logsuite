import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drop_gamification.dart';

class DropGamificationService {
  final SharedPreferences _prefs;

  static const _keyXp = 'drop_gamification_xp';
  static const _keyCurrentStreak = 'drop_gamification_current_streak';
  static const _keyBestStreak = 'drop_gamification_best_streak';
  static const _keyLastActiveDate = 'drop_gamification_last_active_date';
  static const _keyTotalCaptured = 'drop_gamification_total_captured';
  static const _keyTotalTriaged = 'drop_gamification_total_triaged';
  static const _keyTotalStarred = 'drop_gamification_total_starred';
  static const _keyInboxZeroCount = 'drop_gamification_inbox_zero_count';
  static const _keyUnlockedBadges = 'drop_gamification_unlocked_badges';

  DropGamificationService(this._prefs);

  DropGamificationStats getStats() {
    return DropGamificationStats(
      xp: _prefs.getInt(_keyXp) ?? 0,
      currentStreak: _prefs.getInt(_keyCurrentStreak) ?? 0,
      bestStreak: _prefs.getInt(_keyBestStreak) ?? 0,
      lastActiveDate: _prefs.getString(_keyLastActiveDate),
      totalDropsCaptured: _prefs.getInt(_keyTotalCaptured) ?? 0,
      totalDropsTriaged: _prefs.getInt(_keyTotalTriaged) ?? 0,
      totalDropsStarred: _prefs.getInt(_keyTotalStarred) ?? 0,
      inboxZeroCount: _prefs.getInt(_keyInboxZeroCount) ?? 0,
      unlockedBadgeIds: (_prefs.getStringList(_keyUnlockedBadges) ?? []).toSet(),
    );
  }

  Future<GamificationReward> recordDropCaptured({bool hasTags = false}) async {
    final stats = getStats();
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    var currentStreak = stats.currentStreak;
    var bestStreak = stats.bestStreak;
    var streakExtended = false;

    if (stats.lastActiveDate == null) {
      currentStreak = 1;
      streakExtended = true;
    } else {
      final lastDate = DateTime.tryParse(stats.lastActiveDate!);
      if (lastDate != null) {
        final diffDays = DateTime(now.year, now.month, now.day)
            .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
            .inDays;

        if (diffDays == 1) {
          currentStreak++;
          streakExtended = true;
        } else if (diffDays > 1) {
          currentStreak = 1;
          streakExtended = true;
        }
      }
    }

    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
    }

    final totalCaptured = stats.totalDropsCaptured + 1;
    int earnedXp = hasTags ? 15 : 10;
    String reason = hasTags ? 'Organized Drop (+15 XP)' : 'Quick Drop (+10 XP)';

    final unlockedBadgeIds = Set<String>.from(stats.unlockedBadgeIds);
    final newlyUnlockedBadges = <DropBadge>[];

    void checkBadge(String id) {
      if (!unlockedBadgeIds.contains(id)) {
        final b = DropBadge.allBadges.firstWhere((element) => element.id == id);
        unlockedBadgeIds.add(id);
        newlyUnlockedBadges.add(b);
        earnedXp += b.xpReward;
      }
    }

    // Badge: first_drop
    checkBadge('first_drop');

    // Badge: tag_architect
    if (hasTags) {
      checkBadge('tag_architect');
    }

    // Badge: power_collector
    if (totalCaptured >= 10) {
      checkBadge('power_collector');
    }

    // Badge: streak_3
    if (currentStreak >= 3) {
      checkBadge('streak_3');
    }

    final oldLevel = stats.level;
    final newXp = stats.xp + earnedXp;

    await _prefs.setInt(_keyXp, newXp);
    await _prefs.setInt(_keyCurrentStreak, currentStreak);
    await _prefs.setInt(_keyBestStreak, bestStreak);
    await _prefs.setString(_keyLastActiveDate, todayStr);
    await _prefs.setInt(_keyTotalCaptured, totalCaptured);
    await _prefs.setStringList(_keyUnlockedBadges, unlockedBadgeIds.toList());

    final updatedStats = getStats();
    final didLevelUp = updatedStats.level > oldLevel;

    return GamificationReward(
      xpGained: earnedXp,
      reason: reason,
      unlockedBadges: newlyUnlockedBadges,
      didLevelUp: didLevelUp,
      newLevel: updatedStats.level,
      newLevelTitle: updatedStats.levelTitle,
      streakExtended: streakExtended,
      streakCount: currentStreak,
    );
  }

  Future<GamificationReward> recordDropTriaged({bool reachedInboxZero = false}) async {
    final stats = getStats();
    final totalTriaged = stats.totalDropsTriaged + 1;
    var inboxZeroCount = stats.inboxZeroCount;
    if (reachedInboxZero) {
      inboxZeroCount++;
    }

    int earnedXp = 10;
    String reason = 'Inbox Triaged (+10 XP)';

    if (reachedInboxZero) {
      earnedXp += 50;
      reason = 'Inbox Zero Achieved! (+60 XP)';
    }

    final unlockedBadgeIds = Set<String>.from(stats.unlockedBadgeIds);
    final newlyUnlockedBadges = <DropBadge>[];

    void checkBadge(String id) {
      if (!unlockedBadgeIds.contains(id)) {
        final b = DropBadge.allBadges.firstWhere((element) => element.id == id);
        unlockedBadgeIds.add(id);
        newlyUnlockedBadges.add(b);
        earnedXp += b.xpReward;
      }
    }

    if (reachedInboxZero) {
      checkBadge('inbox_zero');
    }

    if (totalTriaged >= 5) {
      checkBadge('triage_specialist');
    }

    final oldLevel = stats.level;
    final newXp = stats.xp + earnedXp;

    await _prefs.setInt(_keyXp, newXp);
    await _prefs.setInt(_keyTotalTriaged, totalTriaged);
    await _prefs.setInt(_keyInboxZeroCount, inboxZeroCount);
    await _prefs.setStringList(_keyUnlockedBadges, unlockedBadgeIds.toList());

    final updatedStats = getStats();
    final didLevelUp = updatedStats.level > oldLevel;

    return GamificationReward(
      xpGained: earnedXp,
      reason: reason,
      unlockedBadges: newlyUnlockedBadges,
      didLevelUp: didLevelUp,
      newLevel: updatedStats.level,
      newLevelTitle: updatedStats.levelTitle,
    );
  }

  Future<GamificationReward> recordBulkTriaged(int count) async {
    final stats = getStats();
    final totalTriaged = stats.totalDropsTriaged + count;
    int earnedXp = count * 8;
    String reason = 'Bulk Triaged $count items (+$earnedXp XP)';

    final unlockedBadgeIds = Set<String>.from(stats.unlockedBadgeIds);
    final newlyUnlockedBadges = <DropBadge>[];

    void checkBadge(String id) {
      if (!unlockedBadgeIds.contains(id)) {
        final b = DropBadge.allBadges.firstWhere((element) => element.id == id);
        unlockedBadgeIds.add(id);
        newlyUnlockedBadges.add(b);
        earnedXp += b.xpReward;
      }
    }

    if (totalTriaged >= 5) {
      checkBadge('triage_specialist');
    }

    final oldLevel = stats.level;
    final newXp = stats.xp + earnedXp;

    await _prefs.setInt(_keyXp, newXp);
    await _prefs.setInt(_keyTotalTriaged, totalTriaged);
    await _prefs.setStringList(_keyUnlockedBadges, unlockedBadgeIds.toList());

    final updatedStats = getStats();
    final didLevelUp = updatedStats.level > oldLevel;

    return GamificationReward(
      xpGained: earnedXp,
      reason: reason,
      unlockedBadges: newlyUnlockedBadges,
      didLevelUp: didLevelUp,
      newLevel: updatedStats.level,
      newLevelTitle: updatedStats.levelTitle,
    );
  }

  Future<GamificationReward> recordConvertedToNote() async {
    final stats = getStats();
    int earnedXp = 15;
    final reason = 'Drop Converted to Note (+15 XP)';

    final unlockedBadgeIds = Set<String>.from(stats.unlockedBadgeIds);
    final newlyUnlockedBadges = <DropBadge>[];

    if (!unlockedBadgeIds.contains('scholar')) {
      final b = DropBadge.allBadges.firstWhere((element) => element.id == 'scholar');
      unlockedBadgeIds.add('scholar');
      newlyUnlockedBadges.add(b);
      earnedXp += b.xpReward;
    }

    final oldLevel = stats.level;
    final newXp = stats.xp + earnedXp;

    await _prefs.setInt(_keyXp, newXp);
    await _prefs.setStringList(_keyUnlockedBadges, unlockedBadgeIds.toList());

    final updatedStats = getStats();
    final didLevelUp = updatedStats.level > oldLevel;

    return GamificationReward(
      xpGained: earnedXp,
      reason: reason,
      unlockedBadges: newlyUnlockedBadges,
      didLevelUp: didLevelUp,
      newLevel: updatedStats.level,
      newLevelTitle: updatedStats.levelTitle,
    );
  }

  Future<GamificationReward> recordConvertedToTask() async {
    final stats = getStats();
    int earnedXp = 15;
    final reason = 'Drop Converted to Task (+15 XP)';

    final unlockedBadgeIds = Set<String>.from(stats.unlockedBadgeIds);
    final newlyUnlockedBadges = <DropBadge>[];

    if (!unlockedBadgeIds.contains('action_taker')) {
      final b = DropBadge.allBadges.firstWhere((element) => element.id == 'action_taker');
      unlockedBadgeIds.add('action_taker');
      newlyUnlockedBadges.add(b);
      earnedXp += b.xpReward;
    }

    final oldLevel = stats.level;
    final newXp = stats.xp + earnedXp;

    await _prefs.setInt(_keyXp, newXp);
    await _prefs.setStringList(_keyUnlockedBadges, unlockedBadgeIds.toList());

    final updatedStats = getStats();
    final didLevelUp = updatedStats.level > oldLevel;

    return GamificationReward(
      xpGained: earnedXp,
      reason: reason,
      unlockedBadges: newlyUnlockedBadges,
      didLevelUp: didLevelUp,
      newLevel: updatedStats.level,
      newLevelTitle: updatedStats.levelTitle,
    );
  }

  Future<GamificationReward> recordDropFavorited() async {
    final stats = getStats();
    final totalStarred = stats.totalDropsStarred + 1;
    int earnedXp = 5;
    final reason = 'Drop Favorited (+5 XP)';

    final unlockedBadgeIds = Set<String>.from(stats.unlockedBadgeIds);
    final newlyUnlockedBadges = <DropBadge>[];

    if (totalStarred >= 3 && !unlockedBadgeIds.contains('curator')) {
      final b = DropBadge.allBadges.firstWhere((element) => element.id == 'curator');
      unlockedBadgeIds.add('curator');
      newlyUnlockedBadges.add(b);
      earnedXp += b.xpReward;
    }

    final oldLevel = stats.level;
    final newXp = stats.xp + earnedXp;

    await _prefs.setInt(_keyXp, newXp);
    await _prefs.setInt(_keyTotalStarred, totalStarred);
    await _prefs.setStringList(_keyUnlockedBadges, unlockedBadgeIds.toList());

    final updatedStats = getStats();
    final didLevelUp = updatedStats.level > oldLevel;

    return GamificationReward(
      xpGained: earnedXp,
      reason: reason,
      unlockedBadges: newlyUnlockedBadges,
      didLevelUp: didLevelUp,
      newLevel: updatedStats.level,
      newLevelTitle: updatedStats.levelTitle,
    );
  }
}
