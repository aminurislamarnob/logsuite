import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand.dart';
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
    final dropRoles = brand.dropRoles;
    final stats = ref.watch(dropGamificationProvider);
    final allBadges = DropBadge.allBadges;
    final unlockedCount = stats.unlockedBadgeIds.length;
    final remainingXp = math.max(0, stats.nextLevelXp - stats.xp);

    return SheetScaffold(
      title: 'Drop Mastery & Badges',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ink Hero Rank Card (24-drop-mastery.html)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: brand.heroSurface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppShadows.hero(theme.brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ProgressRing(
                      value: stats.levelProgress,
                      size: 88,
                      thickness: 10,
                      onInk: true,
                      color: dropRoles.onInk,
                      center: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'LEVEL',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: brand.onInkMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              '${stats.level}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR RANK · Level ${stats.level}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: dropRoles.onInk,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stats.levelTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${stats.xp} XP · $remainingXp to Level ${stats.level + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              color: brand.onInkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: LinearProgressIndicator(
                      value: stats.levelProgress,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        dropRoles.onInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Lv ${stats.level} · ${stats.currentLevelFloorXp}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: brand.onInkMuted,
                      ),
                    ),
                    Text(
                      'Lv ${stats.level + 1} · ${stats.nextLevelXp}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: brand.onInkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3-Column White Stats Cards (24-drop-mastery.html)
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  label: 'Streak',
                  value: '${stats.currentStreak}d',
                  icon: AppIcons.streak,
                  iconColor: brand.warningRoles.graphicOnTint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  context,
                  label: 'Captured',
                  value: '${stats.totalDropsCaptured}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  context,
                  label: 'Inbox Zero',
                  value: '${stats.inboxZeroCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Badges Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Badges',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  '$unlockedCount of ${allBadges.length} unlocked',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2-Column Badges Grid (24-drop-mastery.html)
          _BadgesGrid(badges: allBadges, stats: stats),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    HugeIconData? icon,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (icon != null) ...[
                AppIcon(icon, size: 18, color: iconColor ?? brand.ink),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: brand.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgesGrid extends StatelessWidget {
  final List<DropBadge> badges;
  final DropGamificationStats stats;

  const _BadgesGrid({required this.badges, required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < badges.length; i += 2) {
      final first = badges[i];
      final second = i + 1 < badges.length ? badges[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < badges.length ? 10 : 0),
          child: Row(
            children: [
              Expanded(
                child: _BadgeCard(
                  badge: first,
                  isUnlocked: stats.isBadgeUnlocked(first.id),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: second != null
                    ? _BadgeCard(
                        badge: second,
                        isUnlocked: stats.isBadgeUnlocked(second.id),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _BadgeCard extends StatelessWidget {
  final DropBadge badge;
  final bool isUnlocked;

  const _BadgeCard({required this.badge, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final dropRoles = brand.dropRoles;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnlocked ? dropRoles.tintFill : brand.well,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isUnlocked ? dropRoles.graphicOnTint : brand.surface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isUnlocked
                ? Text(badge.iconEmoji, style: const TextStyle(fontSize: 18))
                : AppIcon(AppIcons.lock, size: 18, color: context.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: isUnlocked ? brand.ink : context.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isUnlocked ? '+${badge.xpReward} XP' : badge.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isUnlocked ? FontWeight.w700 : FontWeight.w500,
                    color: isUnlocked ? dropRoles.textOnTint : context.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
