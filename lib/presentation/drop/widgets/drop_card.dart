import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../models/drop_with_tags.dart';
import '../repository/drop_repository.dart';
import '../services/drop_summarizer.dart';

class DropCard extends ConsumerWidget {
  final DropWithTags item;
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
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onToggleSelect,
    this.onImageTap,
    this.onRemindTap,
    this.onConvertToTask,
    this.onConvertToNote,
  });

  Future<void> _handlePrimaryTap(BuildContext context) async {
    if (isSelectionMode) {
      onToggleSelect?.call();
      return;
    }

    if (item.isImage) {
      onImageTap?.call();
      return;
    }

    if (item.isArticle || item.isVideo) {
      final raw = item.content.trim();
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(raw);
      final urlString = urlMatch != null ? urlMatch.group(0) : raw;
      if (urlString != null) {
        final uri = Uri.tryParse(urlString);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
    }

    // Default for clips: copy to clipboard with feedback
    await Clipboard.setData(ClipboardData(text: item.content));
    if (context.mounted) {
      HapticFeedback.lightImpact();
      brandToast(context, 'Copied to clipboard');
    }
  }

  void _showMoreActions(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final repo = ref.read(dropRepositoryProvider);
    final isArchived = item.isArchived;

    brandSheet(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: item.title ?? (item.isClip ? 'Text Drop' : 'Drop Actions'),
        child: Column(
          children: [
            BrandTile(
              leading: AppIcon(item.isPinned ? AppIcons.pin : AppIcons.pin),
              title: Text(item.isPinned ? 'Unpin' : 'Pin to top'),
              onTap: () {
                Navigator.pop(sheetContext);
                repo.togglePinned(item.id);
              },
            ),
            BrandTile(
              leading: AppIcon(isArchived ? AppIcons.unarchive : AppIcons.archive),
              title: Text(isArchived ? 'Move to Inbox' : 'Archive'),
              onTap: () {
                Navigator.pop(sheetContext);
                repo.setTriageStatus(
                  item.id,
                  isArchived ? 'inbox' : 'archived',
                );
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
              title: Text('Delete Drop', style: TextStyle(color: brand.danger)),
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
    final repo = ref.read(dropRepositoryProvider);

    HugeIconData typeIcon = AppIcons.document;
    String typeLabel = 'Clip';
    Color typeColor = brand.note;

    if (item.isArticle) {
      typeIcon = AppIcons.link;
      typeLabel = 'Article';
      typeColor = brand.task;
    } else if (item.isVideo) {
      typeIcon = AppIcons.play;
      typeLabel = 'Video';
      typeColor = brand.danger;
    } else if (item.isImage) {
      typeIcon = AppIcons.camera;
      typeLabel = 'Image';
      typeColor = brand.drop;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? brand.drop.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? brand.drop : brand.hairline,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handlePrimaryTap(context),
          onLongPress: () {
            HapticFeedback.selectionClick();
            if (onToggleSelect != null) {
              onToggleSelect?.call();
            } else {
              _showMoreActions(context, ref);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Type Chip, Domain/Time, Pin, Checkbox / Actions
                Row(
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(typeIcon, size: 13, color: typeColor),
                          const SizedBox(width: 4),
                          Text(
                            typeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: typeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (item.sourceDomain != null) ...[
                      Expanded(
                        child: Text(
                          item.sourceDomain!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: Text(
                          Fmt.relativeDay(item.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ],
                    if (item.isPinned) ...[
                      AppIcon(AppIcons.pin, size: 14, color: brand.warning),
                      const SizedBox(width: 6),
                    ],
                    if (item.reminderAt != null) ...[
                      AppIcon(AppIcons.clock, size: 14, color: brand.task),
                      const SizedBox(width: 6),
                    ],
                    IconButton(
                      icon: const AppIcon(AppIcons.moreHorizontal, size: 18),
                      tooltip: 'More actions',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showMoreActions(context, ref),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Visual content (Article/Video Cover or Local Image)
                if (item.isImage && item.mediaPath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      color: brand.canvas,
                      child: Image.file(
                        File(item.mediaThumbnailPath ?? item.mediaPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: AppIcon(AppIcons.camera, size: 36),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else if (item.previewImageUrl != null &&
                    item.previewImageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 160,
                          width: double.infinity,
                          color: brand.canvas,
                          child: Image.network(
                            item.previewImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                        ),
                        if (item.isVideo)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const ShapeDecoration(
                              color: Colors.black54,
                              shape: CircleBorder(),
                            ),
                            child: const AppIcon(
                              AppIcons.play,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Title
                if (item.title != null && item.title!.isNotEmpty) ...[
                  Text(
                    item.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // Body content / Description
                Text(
                  item.description ?? item.content,
                  maxLines: item.isClip ? 8 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: (item.isArticle || item.isVideo)
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurface,
                  ),
                ),

                // Tags row
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: item.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: brand.hairline.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: brand.task,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 8),

                // Action Footer: Quick Checkmark (Inbox <-> Archive), Quick Pin, 1-Tap Copy
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: AppIcon(
                        AppIcons.copy,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      tooltip: 'Copy text to clipboard',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: item.content));
                        if (context.mounted) {
                          HapticFeedback.lightImpact();
                          brandToast(context, 'Copied to clipboard');
                        }
                      },
                    ),
                    IconButton(
                      icon: AppIcon(
                        item.isPinned ? AppIcons.star : AppIcons.star,
                        size: 17,
                        color: item.isPinned
                            ? brand.warning
                            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      tooltip: item.isPinned ? 'Unstar' : 'Star / Favorite',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => repo.togglePinned(item.id),
                    ),
                    IconButton(
                      icon: AppIcon(
                        item.isArchived
                            ? AppIcons.unarchive
                            : AppIcons.checkCircle,
                        size: 18,
                        color: item.isArchived
                            ? brand.warning
                            : brand.success,
                      ),
                      tooltip: item.isArchived
                          ? 'Move to Inbox'
                          : 'Mark Done / Archive',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        repo.setTriageStatus(
                          item.id,
                          item.isArchived ? 'inbox' : 'archived',
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
