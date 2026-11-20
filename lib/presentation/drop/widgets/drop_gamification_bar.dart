import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../providers/drop_gamification_provider.dart';

class DropGamificationBar extends ConsumerWidget {
  final VoidCallback onTap;

  const DropGamificationBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final stats = ref.watch(dropGamificationProvider);
    final dropRoles = brand.dropRoles;
    final warningRoles = brand.warningRoles;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('drop_gamification_bar'),
        onTap: () {
          AppHaptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: 4,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.card(theme.brightness),
          ),
          child: Row(
            children: [
              // Streak Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: warningRoles.tintFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.streak,
                      size: 13,
                      color: warningRoles.graphicOnTint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${stats.currentStreak}d',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: warningRoles.textOnTint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Level & Progress Bar
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Lvl ${stats.level}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: dropRoles.textOnTint,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '· ${stats.levelTitle}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: stats.levelProgress,
                        minHeight: 4,
                        backgroundColor: brand.track,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          dropRoles.graphicOnTint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // XP Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: dropRoles.tintFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.star,
                      size: 12,
                      color: dropRoles.graphicOnTint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${stats.xp} XP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: dropRoles.textOnTint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
