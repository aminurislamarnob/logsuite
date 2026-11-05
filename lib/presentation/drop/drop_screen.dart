import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/ai_drafts.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../notes/repository/note_repository.dart';
import '../tasks/widgets/task_editor_sheet.dart';
import 'models/drop_with_tags.dart';
import 'providers/drop_provider.dart';
import 'repository/drop_repository.dart';
import 'services/drop_media_storage.dart';
import 'widgets/drop_card.dart';
import 'widgets/drop_input_bar.dart';
import 'widgets/drop_lightbox_viewer.dart';

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
    // Media attachment hook for Ticket 3
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

      // Extract text via OCR
      String? ocrText;
      try {
        final ocr = ref.read(ocrServiceProvider);
        ocrText = await ocr.extractText(File(saved.originalPath));
      } catch (_) {}

      final caption = (ocrText != null && ocrText.isNotEmpty)
          ? ocrText.split('\n').first.trim()
          : (fromCamera ? 'Camera photo' : 'Screenshot / Photo');

      await ref.read(dropRepositoryProvider).createDrop(
            content: caption,
            assetType: 'image',
            mediaPath: saved.originalPath,
            mediaThumbnailPath: saved.thumbnailPath,
            ocrText: ocrText,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save media: $e')),
        );
      }
    }
  }

  void _showReminderDialog(DropWithTags item) {
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20, 0);
    final tomorrowMorning = DateTime(now.year, now.month, now.day + 1, 9, 0);
    final weekend = DateTime(now.year, now.month, now.day + (6 - now.weekday), 10, 0);

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
                await ref.read(dropRepositoryProvider).setReminder(
                      item.id,
                      tonight,
                      notifier: ref.read(notificationServiceProvider),
                    );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder set for tonight at 8:00 PM')),
                  );
                }
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.clock),
              title: const Text('Tomorrow morning (9:00 AM)'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(dropRepositoryProvider).setReminder(
                      item.id,
                      tomorrowMorning,
                      notifier: ref.read(notificationServiceProvider),
                    );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder set for tomorrow at 9:00 AM')),
                  );
                }
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.calendar),
              title: const Text('This weekend (Saturday 10:00 AM)'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(dropRepositoryProvider).setReminder(
                      item.id,
                      weekend,
                      notifier: ref.read(notificationServiceProvider),
                    );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder set for the weekend')),
                  );
                }
              },
            ),
            if (item.reminderAt != null)
              BrandTile(
                leading: const AppIcon(AppIcons.close, color: Colors.red),
                title: const Text('Clear reminder', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(dropRepositoryProvider).setReminder(
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
    final title = item.title ??
        (item.content.length > 60
            ? '${item.content.substring(0, 57)}...'
            : item.content);
    final description =
        item.description ?? (item.title != null ? item.content : null);
    final taskId = await TaskEditorSheet.show(
      context,
      draft: TaskDraft(
        title: title,
        description: description,
        tags: item.tags,
      ),
    );
    if (taskId != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created from Drop')),
      );
    }
  }

  Future<void> _convertToNote(DropWithTags item) async {
    final noteRepo = ref.read(noteRepositoryProvider);
    final title = item.title ??
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
    if (mounted) {
      context.push('/notes/edit', extra: noteId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note created from Drop')),
      );
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

    final filterOptions = [
      ('all', 'All', AppIcons.inbox),
      ('article', 'Articles', AppIcons.link),
      ('video', 'Videos', AppIcons.play),
      ('clip', 'Clips', AppIcons.document),
      ('image', 'Images', AppIcons.camera),
      ('favorites', 'Favorites', AppIcons.star),
    ];

    return BrandScaffold(
      header: isSelectionMode
          ? BrandTopBar(
              title: '${selectedIds.length} selected',
              leadingIcon: AppIcons.close,
              onLeading: () =>
                  ref.read(dropSelectedIdsProvider.notifier).state = {},
              actions: [
                IconButton(
                  icon: const AppIcon(AppIcons.archive),
                  tooltip: 'Bulk Archive',
                  onPressed: () async {
                    await ref
                        .read(dropRepositoryProvider)
                        .bulkSetTriageStatus(selectedIds.toList(), 'archived');
                    ref.read(dropSelectedIdsProvider.notifier).state = {};
                  },
                ),
                IconButton(
                  icon: const AppIcon(AppIcons.delete, color: Colors.red),
                  tooltip: 'Bulk Delete',
                  onPressed: () async {
                    final confirm = await brandConfirm(
                      context,
                      title: 'Delete selected items?',
                      message: 'This will delete ${selectedIds.length} drops permanently.',
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
              ],
            )
          : BrandTopBar(
              title: 'Drop',
              leadingIcon: null,
              actions: [
                // Triage toggle (Inbox <-> Archive)
                IconButton(
                  icon: AppIcon(
                    activeTriage == 'inbox'
                        ? AppIcons.archive
                        : AppIcons.inbox,
                    color: brand.drop,
                  ),
                  tooltip: activeTriage == 'inbox'
                      ? 'View Archive'
                      : 'View Inbox',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(dropTriageStatusProvider.notifier).state =
                        activeTriage == 'inbox' ? 'archived' : 'inbox';
                  },
                ),
                // Search toggle
                IconButton(
                  icon: AppIcon(
                    _isSearchVisible ? AppIcons.close : AppIcons.search,
                  ),
                  tooltip: _isSearchVisible ? 'Close search' : 'Search drops',
                  onPressed: () {
                    setState(() {
                      _isSearchVisible = !_isSearchVisible;
                      if (!_isSearchVisible) {
                        _searchController.clear();
                        ref.read(dropSearchQueryProvider.notifier).state = '';
                      }
                    });
                  },
                ),
              ],
            ),
      child: Column(
        children: [
          // Search Bar
          if (_isSearchVisible)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: theme.colorScheme.surface,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search titles, links, text and OCR...',
                  prefixIcon: const AppIcon(AppIcons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const AppIcon(AppIcons.close, size: 18),
                    onPressed: () {
                      if (_searchController.text.isNotEmpty) {
                        _searchController.clear();
                        ref.read(dropSearchQueryProvider.notifier).state = '';
                      } else {
                        setState(() => _isSearchVisible = false);
                      }
                    },
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: brand.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: brand.hairline),
                  ),
                ),
                onChanged: (val) {
                  ref.read(dropSearchQueryProvider.notifier).state = val;
                },
              ),
            ),

          // Top Filter Pills (All, Articles, Videos, Clips, Images, Favorites)
          Container(
            height: 48,
            color: theme.colorScheme.surface,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: filterOptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (key, label, icon) = filterOptions[i];
                final isSelected = activeFilter == key;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(dropFilterTypeProvider.notifier).state = key;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? brand.drop
                          : brand.canvas,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? brand.drop : brand.hairline,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          icon,
                          size: 14,
                          color: isSelected
                              ? Colors.white
                              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
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
              return Container(
                height: 38,
                color: theme.colorScheme.surface,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: tags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final tag = tags[i];
                    final isSelected = activeTag == tag;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(dropSelectedTagProvider.notifier).state =
                            isSelected ? null : tag;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? brand.task.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? brand.task : brand.hairline,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? brand.task : brand.task.withValues(alpha: 0.7),
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

          const Divider(height: 1, thickness: 1),

          // Main Feed
          Expanded(
            child: dropsAsync.when(
              data: (drops) {
                if (drops.isEmpty) {
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
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  itemCount: drops.length,
                  itemBuilder: (context, i) {
                    final item = drops[i];
                    final isSelected = selectedIds.contains(item.id);

                    return DropCard(
                      key: ValueKey(item.id),
                      item: item,
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
              error: (err, stack) => Center(
                child: Text('Error loading drops: $err'),
              ),
            ),
          ),

          // Bottom Input Bar (hidden when searching or selecting)
          if (!_isSearchVisible && !isSelectionMode)
            DropInputBar(
              onAttachPressed: _showMediaPickerSheet,
            ),
        ],
      ),
    );
  }
}
