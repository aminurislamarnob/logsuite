import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/ai_drafts.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../notes/repository/note_repository.dart';
import '../tasks/widgets/task_editor_sheet.dart';
import 'models/drop_with_tags.dart';
import 'providers/drop_gamification_provider.dart';
import 'providers/drop_provider.dart';
import 'repository/drop_repository.dart';
import 'services/drop_media_storage.dart';
import 'utils/drop_gamification_feedback.dart';
import 'widgets/drop_card.dart';
import 'widgets/drop_gamification_bar.dart';
import 'widgets/drop_input_bar.dart';
import 'widgets/drop_lightbox_viewer.dart';
import 'widgets/drop_mastery_sheet.dart';

class DropScreen extends ConsumerStatefulWidget {
  const DropScreen({super.key});

  @override
  ConsumerState<DropScreen> createState() => _DropScreenState();
}

class _DropScreenState extends ConsumerState<DropScreen> {
  bool _isSearchVisible = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMediaPickerSheet() {
    brandSheet(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Attach Media',
        child: Column(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.camera),
              title: const Text('Take a photo / screenshot'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndDropMedia(fromCamera: true);
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.gallery),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndDropMedia(fromCamera: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndDropMedia({required bool fromCamera}) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;

      final sourceFile = File(picked.path);
      final storage = await DropMediaStorage.create();
      final saved = await storage.save(sourceFile);

      String? ocrText;
      try {
        final ocr = ref.read(ocrServiceProvider);
        ocrText = await ocr.extractText(File(saved.originalPath));
      } catch (_) {}

      final caption = (ocrText != null && ocrText.isNotEmpty)
          ? ocrText.split('\n').first.trim()
          : (fromCamera ? 'Camera photo' : 'Screenshot / Photo');

      await ref
          .read(dropRepositoryProvider)
          .createDrop(
            content: caption,
            assetType: 'image',
            mediaPath: saved.originalPath,
            mediaThumbnailPath: saved.thumbnailPath,
            ocrText: ocrText,
          );
    } catch (e) {
      if (mounted) {
        brandToast(context, 'Failed to save media: $e');
      }
    }
  }

  void _showReminderDialog(DropWithTags item) {
    final brand = context.brand;
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20, 0);
    final tomorrowMorning = DateTime(now.year, now.month, now.day + 1, 9, 0);
    final weekend = DateTime(
      now.year,
      now.month,
      now.day + (6 - now.weekday),
      10,
      0,
    );

    brandSheet(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Remind Me Later',
        child: Column(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.clock),
              title: const Text('Tonight at 8:00 PM'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref
                    .read(dropRepositoryProvider)
                    .setReminder(
                      item.id,
                      tonight,
                      notifier: ref.read(notificationServiceProvider),
                    );
                if (mounted) {
                  brandToast(context, 'Reminder set for tonight at 8:00 PM');
                }
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.clock),
              title: const Text('Tomorrow morning (9:00 AM)'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref
                    .read(dropRepositoryProvider)
                    .setReminder(
                      item.id,
                      tomorrowMorning,
                      notifier: ref.read(notificationServiceProvider),
                    );
                if (mounted) {
                  brandToast(context, 'Reminder set for tomorrow at 9:00 AM');
                }
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.calendar),
              title: const Text('This weekend (Saturday 10:00 AM)'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref
                    .read(dropRepositoryProvider)
                    .setReminder(
                      item.id,
                      weekend,
                      notifier: ref.read(notificationServiceProvider),
                    );
                if (mounted) {
                  brandToast(context, 'Reminder set for the weekend');
                }
              },
            ),
            if (item.reminderAt != null)
              BrandTile(
                leading: AppIcon(AppIcons.close, color: brand.danger),
                title: Text(
                  'Clear reminder',
                  style: TextStyle(color: brand.danger),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref
                      .read(dropRepositoryProvider)
                      .setReminder(
                        item.id,
                        null,
                        notifier: ref.read(notificationServiceProvider),
                      );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _convertToTask(DropWithTags item) async {
    final title =
        item.title ??
        (item.content.length > 60
            ? '${item.content.substring(0, 57)}...'
            : item.content);
    final description =
        item.description ?? (item.title != null ? item.content : null);
    final taskId = await TaskEditorSheet.show(
      context,
      draft: TaskDraft(title: title, description: description, tags: item.tags),
    );
    if (taskId != null && mounted) {
      final reward = await ref
          .read(dropGamificationProvider.notifier)
          .recordConvertedToTask();
      if (mounted) DropGamificationFeedback.show(context, reward);
    }
  }

  Future<void> _convertToNote(DropWithTags item) async {
    final noteRepo = ref.read(noteRepositoryProvider);
    final title =
        item.title ??
        (item.content.length > 50
            ? '${item.content.substring(0, 47)}...'
            : 'Drop Note');
    final body = item.description != null && item.description!.isNotEmpty
        ? '${item.content}\n\n${item.description}'
        : item.content;
    final noteId = await noteRepo.createNote(
      title: title,
      contentJson: NoteRepository.deltaFromPlainText(body),
    );
    final reward = await ref
        .read(dropGamificationProvider.notifier)
        .recordConvertedToNote();
    if (mounted) {
      DropGamificationFeedback.show(context, reward);
      context.push('/note_editor', extra: noteId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final dropsAsync = ref.watch(dropsStreamProvider);
    final tagsAsync = ref.watch(dropTagsStreamProvider);
    final activeFilter = ref.watch(dropFilterTypeProvider);
    final activeTriage = ref.watch(dropTriageStatusProvider);
    final activeTag = ref.watch(dropSelectedTagProvider);
    final selectedIds = ref.watch(dropSelectedIdsProvider);
    final isSelectionMode = selectedIds.isNotEmpty;

    final currentDrops = dropsAsync.valueOrNull ?? const <DropWithTags>[];
    final inboxSubtitle = activeTriage == 'inbox' && currentDrops.isNotEmpty
        ? '${currentDrops.length} to go through'
        : null;

    final filterOptions = [
      ('all', 'All'),
      ('article', 'Articles'),
      ('video', 'Videos'),
      ('clip', 'Clips'),
      ('image', 'Images'),
      ('favorites', 'Favorites'),
    ];

    return BrandScaffold(
      header: isSelectionMode
          ? BrandTopBar(
              title: '${selectedIds.length} selected',
              leadingIcon: AppIcons.close,
              onLeading: () =>
                  ref.read(dropSelectedIdsProvider.notifier).state = {},
              actions: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const CircleBorder(),
                    shadows: AppShadows.circleButton(theme.brightness),
                  ),
                  child: IconButton(
                    icon: const AppIcon(AppIcons.archive, size: 20),
                    tooltip: 'Bulk Archive',
                    onPressed: () async {
                      final count = selectedIds.length;
                      await ref
                          .read(dropRepositoryProvider)
                          .bulkSetTriageStatus(
                            selectedIds.toList(),
                            'archived',
                          );
                      ref.read(dropSelectedIdsProvider.notifier).state = {};
                      final reward = await ref
                          .read(dropGamificationProvider.notifier)
                          .recordBulkTriaged(count);
                      if (context.mounted) {
                        DropGamificationFeedback.show(context, reward);
                      }
                    },
                  ),
                ),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const CircleBorder(),
                    shadows: AppShadows.circleButton(theme.brightness),
                  ),
                  child: IconButton(
                    icon: AppIcon(
                      AppIcons.delete,
                      size: 20,
                      color: brand.danger,
                    ),
                    tooltip: 'Bulk Delete',
                    onPressed: () async {
                      final confirm = await brandConfirm(
                        context,
                        title: 'Delete selected items?',
                        message:
                            'This will delete ${selectedIds.length} drops permanently.',
                        confirmLabel: 'Delete',
                      );
                      if (confirm) {
                        await ref
                            .read(dropRepositoryProvider)
                            .deleteDrops(selectedIds.toList());
                        ref.read(dropSelectedIdsProvider.notifier).state = {};
                      }
                    },
                  ),
                ),
              ],
            )
          : BrandTopBar(
              title: activeTriage == 'archived' ? 'Archive' : 'Drop',
              subtitle: inboxSubtitle,
              leadingIcon: AppIcons.back,
              actions: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const CircleBorder(),
                    shadows: AppShadows.circleButton(theme.brightness),
                  ),
                  child: IconButton(
                    icon: AppIcon(
                      activeTriage == 'inbox'
                          ? AppIcons.archive
                          : AppIcons.inbox,
                      size: 20,
                      color: brand.ink,
                    ),
                    tooltip: activeTriage == 'inbox'
                        ? 'View Archive'
                        : 'View Inbox',
                    onPressed: () {
                      AppHaptics.selection();
                      ref.read(dropTriageStatusProvider.notifier).state =
                          activeTriage == 'inbox' ? 'archived' : 'inbox';
                    },
                  ),
                ),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: brand.surface,
                    shape: const CircleBorder(),
                    shadows: AppShadows.circleButton(theme.brightness),
                  ),
                  child: IconButton(
                    icon: AppIcon(
                      _isSearchVisible ? AppIcons.close : AppIcons.search,
                      size: 20,
                      color: brand.ink,
                    ),
                    tooltip: _isSearchVisible ? 'Close search' : 'Search drops',
                    onPressed: () {
                      AppHaptics.tap();
                      setState(() {
                        _isSearchVisible = !_isSearchVisible;
                        if (!_isSearchVisible) {
                          _searchController.clear();
                          ref.read(dropSearchQueryProvider.notifier).state = '';
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
      child: Column(
        children: [
          // Search Bar
          if (_isSearchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                4,
                AppSpacing.gutter,
                8,
              ),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: ShapeDecoration(
                  color: brand.surface,
                  shape: const StadiumBorder(),
                  shadows: AppShadows.circleButton(theme.brightness),
                ),
                child: Row(
                  children: [
                    AppIcon(AppIcons.search, size: 18, color: context.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: TextStyle(fontSize: 15, color: brand.ink),
                        decoration: InputDecoration(
                          hintText: 'Search titles, links, text and OCR...',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: context.muted,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          filled: false,
                        ),
                        onChanged: (val) {
                          ref.read(dropSearchQueryProvider.notifier).state =
                              val;
                        },
                      ),
                    ),
                    IconButton(
                      icon: AppIcon(
                        AppIcons.close,
                        size: 16,
                        color: context.muted,
                      ),
                      onPressed: () {
                        if (_searchController.text.isNotEmpty) {
                          _searchController.clear();
                          ref.read(dropSearchQueryProvider.notifier).state = '';
                        } else {
                          setState(() => _isSearchVisible = false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Gamification Status Bar (Streak, Level, XP)
          if (!isSelectionMode && !_isSearchVisible)
            DropGamificationBar(onTap: () => DropMasterySheet.show(context)),

          // Top Filter Pills (All, Articles, Videos, Clips, Images, Favorites)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: 4,
              ),
              itemCount: filterOptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final (key, label) = filterOptions[i];
                final isSelected = activeFilter == key;

                return GestureDetector(
                  onTap: () {
                    AppHaptics.selection();
                    ref.read(dropFilterTypeProvider.notifier).state = key;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: ShapeDecoration(
                      color: isSelected ? brand.ink : brand.surface,
                      shape: const StadiumBorder(),
                      shadows: isSelected
                          ? const []
                          : AppShadows.circleButton(theme.brightness),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isSelected ? brand.onInk : brand.ink,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Hashtag Chips (if any exist)
          tagsAsync.when(
            data: (tags) {
              if (tags.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                    vertical: 3,
                  ),
                  itemCount: tags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final tag = tags[i];
                    final isSelected = activeTag == tag;

                    return GestureDetector(
                      onTap: () {
                        AppHaptics.selection();
                        ref.read(dropSelectedTagProvider.notifier).state =
                            isSelected ? null : tag;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: ShapeDecoration(
                          color: isSelected
                              ? brand.dropRoles.tintFill
                              : brand.surface,
                          shape: const StadiumBorder(),
                          shadows: AppShadows.circleButton(theme.brightness),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? brand.dropRoles.textOnTint
                                : context.muted,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Main Feed
          Expanded(
            child: dropsAsync.when(
              data: (drops) {
                if (drops.isEmpty) {
                  final stats = ref.watch(dropGamificationProvider);
                  final isInboxZero =
                      activeTriage == 'inbox' &&
                      activeFilter == 'all' &&
                      _searchController.text.isEmpty &&
                      activeTag == null &&
                      stats.totalDropsCaptured > 0;

                  if (isInboxZero) {
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 20,
                        ),
                        child: _buildInboxZeroCelebration(context, brand),
                      ),
                    );
                  }

                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState(
                        icon: activeTriage == 'archived'
                            ? AppIcons.archive
                            : AppIcons.inbox,
                        title: activeTriage == 'archived'
                            ? 'Archive is empty'
                            : (activeFilter == 'favorites'
                                  ? 'No favorites yet'
                                  : (_searchController.text.isNotEmpty
                                        ? 'No matching drops'
                                        : 'Your Drop is empty')),
                        message: activeTriage == 'archived'
                            ? 'Completed items you archive will appear here.'
                            : (_searchController.text.isNotEmpty
                                  ? 'Try searching for other keywords or tags.'
                                  : 'Paste links, videos, thoughts or photos below.'),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 16),
                  itemCount: drops.length,
                  itemBuilder: (context, i) {
                    final item = drops[i];
                    final isSelected = selectedIds.contains(item.id);

                    return DropCard(
                      key: ValueKey(item.id),
                      item: item,
                      featured: i == 0 && !isSelectionMode,
                      isSelected: isSelected,
                      isSelectionMode: isSelectionMode,
                      onToggleSelect: () {
                        final next = Set<int>.from(selectedIds);
                        if (next.contains(item.id)) {
                          next.remove(item.id);
                        } else {
                          next.add(item.id);
                        }
                        ref.read(dropSelectedIdsProvider.notifier).state = next;
                      },
                      onRemindTap: () => _showReminderDialog(item),
                      onImageTap: () => DropLightboxViewer.show(context, item),
                      onConvertToTask: () => _convertToTask(item),
                      onConvertToNote: () => _convertToNote(item),
                    );
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, stack) =>
                  Center(child: Text('Error loading drops: $err')),
            ),
          ),

          // Bottom Input Bar (hidden when searching or selecting)
          if (!_isSearchVisible && !isSelectionMode)
            DropInputBar(onAttachPressed: _showMediaPickerSheet),
        ],
      ),
    );
  }

  Widget _buildInboxZeroCelebration(BuildContext context, BrandColors brand) {
    final warningRoles = brand.warningRoles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: brand.dropRoles.tintFill,
            border: Border.all(
              color: brand.drop.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: const Text('🎉', style: TextStyle(fontSize: 40)),
        ),
        const SizedBox(height: 18),
        Text(
          'Inbox Zero!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: brand.ink,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'All items triaged! Your workspace is clear and calm.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.muted, height: 1.4),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: warningRoles.tintFill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.star,
                size: 14,
                color: warningRoles.graphicOnTint,
              ),
              const SizedBox(width: 6),
              Text(
                'Inbox Zero Master • +50 XP Hero Bonus',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: warningRoles.textOnTint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
