import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/in_app_browser.dart';
import '../models/drop_with_tags.dart';
import '../providers/drop_gamification_provider.dart';
import '../repository/drop_repository.dart';
import '../services/drop_summarizer.dart';
import '../utils/drop_gamification_feedback.dart';

class DropCard extends ConsumerWidget {
  final DropWithTags item;
  final bool featured;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onImageTap;
  final VoidCallback? onRemindTap;
  final VoidCallback? onConvertToTask;
  final VoidCallback? onConvertToNote;

  const DropCard({
    super.key,
    required this.item,
    this.featured = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onToggleSelect,
    this.onImageTap,
    this.onRemindTap,
    this.onConvertToTask,
    this.onConvertToNote,
  });

  String? _extractUrl() {
    final raw = item.content.trim();
    final urlMatch = RegExp(r'https?://[^\s<>"]+').firstMatch(raw);
    if (urlMatch != null) return urlMatch.group(0);
    if (item.isArticle || item.isVideo) {
      return InAppBrowserScreen.normalizeUrl(raw);
    }
    return null;
  }

  Future<void> _handlePrimaryTap(BuildContext context) async {
    if (isSelectionMode) {
      onToggleSelect?.call();
      return;
    }

    if (item.isImage) {
      onImageTap?.call();
      return;
    }

    final urlString = _extractUrl();
    if (urlString != null &&
        (item.isArticle ||
            item.isVideo ||
            item.content.trim().startsWith('http://') ||
            item.content.trim().startsWith('https://'))) {
      await InAppBrowserScreen.open(
        context,
        urlString,
        initialTitle: item.title,
      );
      return;
    }

    // Default for clips: copy to clipboard with feedback
    await Clipboard.setData(ClipboardData(text: item.content));
    if (context.mounted) {
      AppHaptics.tap();
      brandToast(context, 'Copied to clipboard');
    }
  }

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(dropRepositoryProvider);
    AppHaptics.success();
    await repo.setTriageStatus(item.id, item.isArchived ? 'inbox' : 'archived');
    if (!item.isArchived) {
      final remaining = await repo.getDrops(triageStatus: 'inbox');
      final reward = await ref
          .read(dropGamificationProvider.notifier)
          .recordDropTriaged(reachedInboxZero: remaining.isEmpty);
      if (context.mounted) {
        DropGamificationFeedback.show(context, reward);
      }
    }
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(dropRepositoryProvider);
    AppHaptics.selection();
    await repo.togglePinned(item.id);
    if (!item.isPinned) {
      final reward = await ref
          .read(dropGamificationProvider.notifier)
          .recordDropFavorited();
      if (context.mounted) {
        DropGamificationFeedback.show(context, reward);
      }
    }
  }

  void _showMoreActions(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final repo = ref.read(dropRepositoryProvider);
    final isArchived = item.isArchived;
    final extractedUrl = _extractUrl();

    brandSheet(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: item.title ?? (item.isClip ? 'Text Drop' : 'Drop Actions'),
        child: TileColumn(
          children: [
            if (extractedUrl != null) ...[
              BrandTile(
                leading: const AppIcon(AppIcons.globe),
                title: const Text('Open in In-App Browser'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  InAppBrowserScreen.open(
                    context,
                    extractedUrl,
                    initialTitle: item.title,
                  );
                },
              ),
              BrandTile(
                leading: const AppIcon(AppIcons.externalLink),
                title: const Text('Open in External Browser'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  InAppBrowserScreen.openInExternalBrowser(
                    context,
                    extractedUrl,
                  );
                },
              ),
            ],
            BrandTile(
              leading: const AppIcon(AppIcons.pin),
              title: Text(item.isPinned ? 'Unpin' : 'Pin to top'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _togglePin(context, ref);
              },
            ),
            BrandTile(
              leading: AppIcon(
                isArchived ? AppIcons.unarchive : AppIcons.archive,
              ),
              title: Text(isArchived ? 'Move to Inbox' : 'Archive'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _toggleArchive(context, ref);
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.sparkle),
              title: const Text('AI Summarize'),
              onTap: () async {
                Navigator.pop(sheetContext);
                brandToast(context, 'Summarizing drop...');
                final summary = await ref
                    .read(dropSummarizerProvider)
                    .summarizeDrop(item);
                if (context.mounted) {
                  brandToast(
                    context,
                    'Summary updated: ${summary.split('\n').first}',
                  );
                }
              },
            ),
            if (onRemindTap != null)
              BrandTile(
                leading: const AppIcon(AppIcons.clock),
                title: Text(
                  item.reminderAt != null
                      ? 'Edit reminder (${Fmt.relativeDay(item.reminderAt!)})'
                      : 'Remind me later',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRemindTap?.call();
                },
              ),
            if (onConvertToTask != null)
              BrandTile(
                leading: const AppIcon(AppIcons.tasks),
                title: const Text('Convert to Task'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onConvertToTask?.call();
                },
              ),
            if (onConvertToNote != null)
              BrandTile(
                leading: const AppIcon(AppIcons.notes),
                title: const Text('Convert to Note'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onConvertToNote?.call();
                },
              ),
            BrandTile(
              leading: const AppIcon(AppIcons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: item.content));
                brandToast(context, 'Content copied for sharing');
              },
            ),
            BrandTile(
              leading: AppIcon(AppIcons.delete, color: brand.danger),
              title: Text(
                'Delete Drop',
                style: TextStyle(color: brand.danger),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirm = await brandConfirm(
                  context,
                  title: 'Delete Drop?',
                  message: 'This action cannot be undone.',
                  confirmLabel: 'Delete',
                );
                if (confirm) {
                  repo.deleteDrop(item.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final dropRoles = brand.dropRoles;

    HugeIconData typeIcon = AppIcons.document;
    String typeLabel = 'CLIP';

    if (item.isArticle) {
      typeIcon = AppIcons.document;
      typeLabel = 'ARTICLE';
    } else if (item.isVideo) {
      typeIcon = AppIcons.play;
      typeLabel = 'VIDEO';
    } else if (item.isImage) {
      typeIcon = AppIcons.camera;
      typeLabel = 'IMAGE';
    }

    final metaParts = <String>[
      if (item.sourceDomain != null) item.sourceDomain!,
      Fmt.relativeDay(item.createdAt),
      if (item.reminderAt != null)
        'reminder ${Fmt.relativeDay(item.reminderAt!)}',
    ];

    final radius = featured ? 24.0 : 22.0;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(radius),
        border: isSelected ? Border.all(color: brand.drop, width: 2.0) : null,
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () {
            AppHaptics.tap();
            _handlePrimaryTap(context);
          },
          onLongPress: () {
            AppHaptics.medium();
            if (onToggleSelect != null) {
              onToggleSelect?.call();
            } else {
              _showMoreActions(context, ref);
            }
          },
          child: featured
              ? _buildFeaturedContent(
                  context,
                  ref,
                  brand: brand,
                  dropRoles: dropRoles,
                  typeIcon: typeIcon,
                  typeLabel: typeLabel,
                  metaText: metaParts.join(' · '),
                )
              : _buildCompactContent(
                  context,
                  ref,
                  brand: brand,
                  dropRoles: dropRoles,
                  typeIcon: typeIcon,
                  typeLabel: typeLabel,
                  metaText: metaParts.join(' · '),
                ),
        ),
      ),
    );
  }

  Widget _buildFeaturedContent(
    BuildContext context,
    WidgetRef ref, {
    required BrandColors brand,
    required dynamic dropRoles,
    required HugeIconData typeIcon,
    required String typeLabel,
    required String metaText,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top dropRoles.tintFill banner (11-drop.html)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 132,
              width: double.infinity,
              color: dropRoles.tintFill,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.isImage && item.mediaPath != null)
                    Image.file(
                      File(item.mediaThumbnailPath ?? item.mediaPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: AppIcon(
                          typeIcon,
                          size: 44,
                          color: dropRoles.graphicOnTint,
                        ),
                      ),
                    )
                  else if (item.previewImageUrl != null &&
                      item.previewImageUrl!.isNotEmpty)
                    Image.network(
                      item.previewImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: AppIcon(
                          typeIcon,
                          size: 44,
                          color: dropRoles.graphicOnTint,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: AppIcon(
                        typeIcon,
                        size: 44,
                        color: dropRoles.graphicOnTint,
                      ),
                    ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: dropRoles.textOnTint,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: brand.surface.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: AppIcon(
                          AppIcons.moreHorizontal,
                          size: 18,
                          color: brand.ink,
                        ),
                        tooltip: 'More actions',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          AppHaptics.tap();
                          _showMoreActions(context, ref);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title != null && item.title!.isNotEmpty) ...[
                  Text(
                    item.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      height: 1.25,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  item.description ?? item.content,
                  maxLines: item.isClip ? 6 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: item.title != null ? 13 : 15,
                    fontWeight: item.title != null
                        ? FontWeight.w400
                        : FontWeight.w600,
                    height: 1.4,
                    color: item.title != null ? context.muted : brand.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: context.muted),
                      ),
                    ),
                    if (item.tags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: item.tags.map((tag) {
                          return Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: dropRoles.textOnTint,
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action row: Done ink pill + Tonight snooze pill + Star circle (11-drop.html)
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: item.isArchived
                      ? 'Move to Inbox'
                      : 'Mark Done / Archive',
                  child: GestureDetector(
                    onTap: () => _toggleArchive(context, ref),
                    child: Container(
                      height: 44,
                      decoration: ShapeDecoration(
                        color: brand.ink,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcon(
                            item.isArchived
                                ? AppIcons.unarchive
                                : AppIcons.check,
                            size: 16,
                            color: brand.onInk,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.isArchived ? 'Inbox' : 'Done',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: brand.onInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    AppHaptics.tap();
                    onRemindTap?.call();
                  },
                  child: Container(
                    height: 44,
                    decoration: ShapeDecoration(
                      color: brand.canvas,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.clock, size: 16, color: brand.ink),
                        const SizedBox(width: 6),
                        Text(
                          'Tonight',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: item.isPinned ? 'Unstar' : 'Star / Favorite',
                child: GestureDetector(
                  onTap: () => _togglePin(context, ref),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: brand.canvas,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      AppIcons.star,
                      size: 18,
                      color: item.isPinned
                          ? brand.warningRoles.graphicOnTint
                          : brand.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactContent(
    BuildContext context,
    WidgetRef ref, {
    required BrandColors brand,
    required dynamic dropRoles,
    required HugeIconData typeIcon,
    required String typeLabel,
    required String metaText,
  }) {
    final hasThumb = item.isVideo || item.isImage;

    return Padding(
      padding: EdgeInsets.fromLTRB(hasThumb ? 12 : 16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isSelectionMode) ...[
            Checkbox(
              value: isSelected,
              activeColor: brand.drop,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: (_) => onToggleSelect?.call(),
            ),
            const SizedBox(width: 4),
          ],
          if (hasThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 96,
                height: 72,
                color: item.isVideo ? brand.heroSurface : dropRoles.tintFill,
                child: Stack(
                  alignment: Alignment.center,
                  fit: StackFit.expand,
                  children: [
                    if (item.isImage && item.mediaPath != null)
                      Image.file(
                        File(item.mediaThumbnailPath ?? item.mediaPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      )
                    else if (item.previewImageUrl != null &&
                        item.previewImageUrl!.isNotEmpty)
                      Image.network(
                        item.previewImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                    Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: AppIcon(
                          item.isVideo ? AppIcons.play : AppIcons.camera,
                          size: 16,
                          color: item.isVideo
                              ? Colors.white
                              : dropRoles.graphicOnTint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: dropRoles.textOnTint,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: brand.canvas,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: brand.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QuickActionIcon(
                            icon: AppIcons.star,
                            tooltip: item.isPinned ? 'Unpin' : 'Pin',
                            color: item.isPinned
                                ? brand.warningRoles.graphicOnTint
                                : context.muted,
                            onTap: () => _togglePin(context, ref),
                          ),
                          if (onRemindTap != null)
                            _QuickActionIcon(
                              icon: AppIcons.clock,
                              tooltip: 'Remind me later',
                              color: item.reminderAt != null
                                  ? dropRoles.textOnTint
                                  : context.muted,
                              onTap: () {
                                AppHaptics.tap();
                                onRemindTap?.call();
                              },
                            ),
                          _QuickActionIcon(
                            icon: AppIcons.share,
                            tooltip: 'Copy for sharing',
                            color: context.muted,
                            onTap: () {
                              AppHaptics.tap();
                              Clipboard.setData(
                                ClipboardData(text: item.content),
                              );
                              brandToast(context, 'Content copied for sharing');
                            },
                          ),
                          Tooltip(
                            message: item.isArchived
                                ? 'Move to Inbox'
                                : 'Mark Done / Archive',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Transform.scale(
                                scale: 0.72,
                                child: BrandCheckbox(
                                  value: item.isArchived,
                                  semanticsLabel: item.isArchived
                                      ? 'Move to Inbox'
                                      : 'Mark Done / Archive',
                                  onChanged: (_) => _toggleArchive(context, ref),
                                ),
                              ),
                            ),
                          ),
                          _QuickActionIcon(
                            icon: AppIcons.moreHorizontal,
                            tooltip: 'More actions',
                            color: context.muted,
                            onTap: () {
                              AppHaptics.tap();
                              _showMoreActions(context, ref);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                if (item.title != null && item.title!.isNotEmpty) ...[
                  Text(
                    item.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  item.description ?? item.content,
                  maxLines: item.isClip ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: item.title != null ? 13 : 15,
                    fontWeight: item.title != null
                        ? FontWeight.w400
                        : FontWeight.w600,
                    height: 1.35,
                    color: item.title != null ? context.muted : brand.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      metaText,
                      style: TextStyle(fontSize: 12, color: context.muted),
                    ),
                    for (final tag in item.tags)
                      Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: dropRoles.textOnTint,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionIcon extends StatelessWidget {
  final HugeIconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: AppIcon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
