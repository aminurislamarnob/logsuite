import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/common.dart';
import '../models/drop_gamification.dart';

class DropGamificationFeedback {
  static void show(BuildContext context, GamificationReward reward) {
    HapticFeedback.lightImpact();

    if (reward.unlockedBadges.isNotEmpty) {
      final b = reward.unlockedBadges.first;
      brandToast(
        context,
        '🏆 Badge Unlocked: ${b.iconEmoji} ${b.title}! (+${b.xpReward} XP)',
      );
      return;
    }

    if (reward.didLevelUp) {
      brandToast(
        context,
        '⚡ Level Up! Level ${reward.newLevel}: ${reward.newLevelTitle} (+${reward.xpGained} XP)',
      );
      return;
    }

    if (reward.streakExtended && reward.streakCount > 1) {
      brandToast(
        context,
        '🔥 ${reward.streakCount}-Day Capture Streak! (+${reward.xpGained} XP)',
      );
      return;
    }

    brandToast(context, reward.reason);
  }
}
