import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../models/drop_gamification.dart';
import '../providers/drop_gamification_provider.dart';

class DropMasterySheet extends ConsumerWidget {
  const DropMasterySheet({super.key});

  static Future<void> show(BuildContext context) {
    return brandSheet(
      context: context,
      builder: (_) => const DropMasterySheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final stats = ref.watch(dropGamificationProvider);
    final allBadges = DropBadge.allBadges;
    final unlockedCount = stats.unlockedBadgeIds.length;

    return SheetScaffold(
      title: 'Drop Mastery & Badges',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Level Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: brand.canvas,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: brand.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: brand.drop.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${stats.level}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: brand.drop,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Level ${stats.level} · ${stats.levelTitle}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${stats.xp} / ${stats.nextLevelXp} XP to Level ${stats.level + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stats.levelProgress,
                    minHeight: 6,
                    backgroundColor: brand.hairline,
                    valueColor: AlwaysStoppedAnimation<Color>(brand.drop),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3-Column Stats Summary
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  theme: theme,
                  brand: brand,
                  icon: AppIcons.streak,
                  iconColor: brand.warning,
                  value: '${stats.currentStreak}d',
                  caption: 'Streak',
                  subcaption: 'Best: ${stats.bestStreak}d',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatBox(
                  theme: theme,
                  brand: brand,
                  icon: AppIcons.document,
                  iconColor: brand.drop,
                  value: '${stats.totalDropsCaptured}',
                  caption: 'Captured',
                  subcaption: 'Total drops',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatBox(
                  theme: theme,
                  brand: brand,
                  icon: AppIcons.archive,
                  iconColor: brand.success,
                  value: '${stats.inboxZeroCount}',
                  caption: 'Inbox Zero',
                  subcaption: 'Clean sweeps',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Achievements Header
          Row(
            children: [
              Text(
                'ACHIEVEMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              Text(
                '$unlockedCount of ${allBadges.length} unlocked',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.drop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Badges List
          ...allBadges.map((badge) {
            final isUnlocked = stats.isBadgeUnlocked(badge.id);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? brand.canvas
                    : brand.canvas.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnlocked
                      ? brand.hairline
                      : brand.hairline.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? brand.drop.withValues(alpha: 0.12)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge.iconEmoji,
                      style: TextStyle(
                        fontSize: 18,
                        color: isUnlocked ? null : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          badge.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isUnlocked
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          badge.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: isUnlocked ? 0.65 : 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? brand.success.withValues(alpha: 0.12)
                          : brand.hairline.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${badge.xpReward} XP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isUnlocked
                            ? brand.success
                            : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required ThemeData theme,
    required dynamic brand,
    required HugeIconData icon,
    required Color iconColor,
    required String value,
    required String caption,
    required String subcaption,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: brand.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.hairline),
      ),
      child: Column(
        children: [
          AppIcon(icon, size: 16, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            subcaption,
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
