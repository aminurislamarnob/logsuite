import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'providers/notes_provider.dart';
import 'repository/note_repository.dart';
import 'utils/note_templates.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final notesAsync = ref.watch(notesListProvider);
    final folders = ref.watch(foldersProvider).valueOrNull ?? const [];
    final tags = ref.watch(noteTagsProvider).valueOrNull ?? const [];
    final filter = ref.watch(noteFilterProvider);
    final repo = ref.read(noteRepositoryProvider);

    final folderById = {for (final f in folders) f.id: f.name};

    return BrandScaffold(
      header: BrandTopBar(
        title: filter == const NoteFilter() ? 'Notes' : filter.title,
        leadingIcon: AppIcons.back,
        actions: [
          CircleIconButton(
            icon: AppIcons.journal,
            tooltip: "Today's journal",
            size: 44,
            onPressed: () async {
              final note = await repo.journalNoteFor(DateTime.now());
              if (context.mounted) context.push('/note_editor', extra: note.id);
            },
          ),
          CircleIconButton(
            icon: AppIcons.folder,
            tooltip: 'Folders',
            size: 44,
            onPressed: () => brandSideSheet(
              context: context,
              builder: (_) => const _NotesDrawer(),
            ),
          ),
          if (filter.scope == NoteScope.trash)
            CircleIconButton(
              icon: AppIcons.deleteForever,
              tooltip: 'Empty trash',
              size: 44,
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  'Empty trash?',
                  'Every note in the trash will be permanently deleted.',
                );
                if (ok) await repo.emptyTrash();
              },
            ),
        ],
      ),
      floatingAction: filter.scope == NoteScope.trash
          ? null
          : BrandFab(
              icon: AppIcons.edit,
              label: 'New note',
              tooltip: 'New note',
              onPressed: () => newNoteFlow(context, ref),
            ),
      child: notesAsync.when(
        loading: () => const Center(child: BrandSpinner()),
        error: (e, _) => EmptyState(
          icon: AppIcons.error,
          title: 'Could not load notes',
          message: '$e',
        ),
        data: (allNotes) {
          final q = _query.trim().toLowerCase();
          final notes = q.isEmpty
              ? allNotes
              : allNotes.where((n) {
                  final titleMatch = n.title.toLowerCase().contains(q);
                  final bodyMatch =
                      !n.isLocked &&
                      NoteRepository.previewOf(
                        n.content,
                      ).toLowerCase().contains(q);
                  return titleMatch || bodyMatch;
                }).toList();

          final pinned = notes.where((n) => n.isPinned).toList();
          final unpinned = notes.where((n) => !n.isPinned).toList();

          return ListView(
            padding: pageInsets(context, top: 8, end: PageEnd.fab),
            children: [
              // Search pill bar (52 high white stadium, 10-notes.html)
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(fontSize: 15, color: brand.ink),
                        decoration: InputDecoration(
                          hintText: allNotes.isEmpty
                              ? 'Search notes'
                              : 'Search ${allNotes.length} ${allNotes.length == 1 ? 'note' : 'notes'}',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: context.muted,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        child: AppIcon(
                          AppIcons.close,
                          size: 16,
                          color: context.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Filter pills strip (10-notes.html)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterPill(
                      label: 'All',
                      selected: filter == const NoteFilter(),
                      onTap: () => ref.read(noteFilterProvider.notifier).state =
                          const NoteFilter(),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'Favorites',
                      icon: AppIcons.star,
                      iconColor: brand.warningRoles.graphicOnTint,
                      selected: filter.scope == NoteScope.favorites,
                      onTap: () => ref.read(noteFilterProvider.notifier).state =
                          const NoteFilter(scope: NoteScope.favorites),
                    ),
                    for (final f in folders) ...[
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: f.name,
                        selected: filter.folderId == f.id,
                        onTap: () =>
                            ref.read(noteFilterProvider.notifier).state =
                                NoteFilter(folderId: f.id, label: f.name),
                      ),
                    ],
                    for (final t in tags) ...[
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: '#${t.name}',
                        selected: filter.tagId == t.id,
                        onTap: () =>
                            ref.read(noteFilterProvider.notifier).state =
                                NoteFilter(tagId: t.id, label: '#${t.name}'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (notes.isEmpty)
                EmptyState(
                  icon: AppIcons.notes,
                  title: switch (filter.scope) {
                    NoteScope.trash => 'Trash is empty',
                    NoteScope.archived => 'Nothing archived',
                    NoteScope.favorites => 'No favorites yet',
                    NoteScope.active =>
                      _query.isNotEmpty ? 'No matching notes' : 'No notes yet',
                  },
                  message: filter.scope == NoteScope.active && _query.isEmpty
                      ? 'Create your first note to get started.'
                      : null,
                  actionLabel:
                      filter.scope == NoteScope.active && _query.isEmpty
                      ? 'New note'
                      : null,
                  onAction: () => newNoteFlow(context, ref),
                )
              else ...[
                if (pinned.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'PINNED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: context.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final n in pinned) ...[
                    _PinnedNoteCard(
                      note: n,
                      scope: filter.scope,
                      folderName: n.folderId == null
                          ? null
                          : folderById[n.folderId!],
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                ],
                if (unpinned.isNotEmpty) ...[
                  if (pinned.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'RECENT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: context.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  MasonryGridView.count(
                    crossAxisCount: MediaQuery.of(context).size.width > 600
                        ? 3
                        : 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: unpinned.length,
                    itemBuilder: (context, i) {
                      final note = unpinned[i];
                      return _NoteCard(
                        note: note,
                        scope: filter.scope,
                        folderName: note.folderId == null
                            ? null
                            : folderById[note.folderId!],
                      );
                    },
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final HugeIconData? icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    return BrandTappable(
      onPressed: () {
        AppHaptics.selection();
        onTap();
      },
      semanticsLabel: label,
      child: Container(
        height: 38,
        padding: EdgeInsets.fromLTRB(icon == null ? 14 : 10, 0, 14, 0),
        decoration: ShapeDecoration(
          color: selected ? brand.ink : brand.surface,
          shape: const StadiumBorder(),
          shadows: selected
              ? const []
              : AppShadows.circleButton(theme.brightness),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(
                icon!,
                size: 14,
                color: selected ? brand.onInk : (iconColor ?? brand.ink),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? brand.onInk : brand.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presents the template picker, creates the note and opens the editor.
Future<void> newNoteFlow(
  BuildContext context,
  WidgetRef ref, {
  int? folderId,
}) async {
  final template = await brandSheet<NoteTemplate>(
    context: context,
    builder: (_) => SheetScaffold(
      title: 'New note',
      child: TileColumn(
        children: NoteTemplate.all
            .map(
              (t) => BrandTile(
                leading: AppIcon(t.icon, color: context.brand.note),
                title: Text(t.name),
                onTap: () => Navigator.pop(context, t),
              ),
            )
            .toList(),
      ),
    ),
  );
  if (template == null || !context.mounted) return;

  final id = await ref
      .read(noteRepositoryProvider)
      .createNote(
        title: template.title,
        contentJson: template.contentJson,
        folderId: folderId ?? ref.read(noteFilterProvider).folderId,
      );
  if (context.mounted) context.push('/note_editor', extra: id);
}

/// Kept as a positional shorthand for this screen's two call sites; the dialog
/// itself is the shared [brandConfirm].
Future<bool> confirmDialog(BuildContext context, String title, String body) =>
    brandConfirm(context, title: title, message: body, confirmLabel: 'Confirm');

/// Extracts checklist lines from Quill delta JSON when present.
List<({String text, bool checked})> _extractChecklist(String contentJson) {
  try {
    final decoded = jsonDecode(contentJson);
    if (decoded is! List) return const [];
    final items = <({String text, bool checked})>[];
    final buffer = StringBuffer();
    for (final op in decoded) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is! String) continue;
      final attrs = op['attributes'] as Map?;
      for (var i = 0; i < insert.length; i++) {
        final ch = insert[i];
        if (ch == '\n') {
          final listType = attrs?['list'];
          if (listType == 'checked' || listType == 'unchecked') {
            final line = buffer.toString().trim();
            if (line.isNotEmpty) {
              items.add((text: line, checked: listType == 'checked'));
            }
          }
          buffer.clear();
        } else {
          buffer.write(ch);
        }
      }
    }
    return items;
  } catch (_) {
    return const [];
  }
}

void _showNoteActions(
  BuildContext context,
  NoteRepository repo,
  Note note,
  NoteScope scope,
) {
  brandSheet(
    context: context,
    builder: (_) => SheetScaffold(
      title: note.title,
      child: TileColumn(
        children: scope == NoteScope.trash
            ? [
                BrandTile(
                  leading: const AppIcon(AppIcons.restore),
                  title: const Text('Restore'),
                  onTap: () {
                    repo.restoreFromTrash(note.id);
                    Navigator.pop(context);
                  },
                ),
                BrandTile(
                  leading: const AppIcon(AppIcons.deleteForever),
                  title: const Text('Delete forever'),
                  onTap: () {
                    repo.deleteForever(note.id);
                    Navigator.pop(context);
                  },
                ),
              ]
            : [
                BrandTile(
                  leading: const AppIcon(AppIcons.pin),
                  title: Text(note.isPinned ? 'Unpin' : 'Pin to top'),
                  onTap: () {
                    repo.updateNote(note.id, isPinned: !note.isPinned);
                    Navigator.pop(context);
                  },
                ),
                BrandTile(
                  leading: const AppIcon(AppIcons.star),
                  title: Text(
                    note.isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                  ),
                  onTap: () {
                    repo.updateNote(note.id, isFavorite: !note.isFavorite);
                    Navigator.pop(context);
                  },
                ),
                BrandTile(
                  leading: AppIcon(
                    note.isArchived ? AppIcons.unarchive : AppIcons.archive,
                  ),
                  title: Text(note.isArchived ? 'Unarchive' : 'Archive'),
                  onTap: () {
                    repo.updateNote(note.id, isArchived: !note.isArchived);
                    Navigator.pop(context);
                  },
                ),
                BrandTile(
                  leading: AppIcon(
                    note.isLocked ? AppIcons.unlock : AppIcons.lock,
                  ),
                  title: Text(note.isLocked ? 'Remove lock' : 'Lock note'),
                  onTap: () {
                    repo.updateNote(note.id, isLocked: !note.isLocked);
                    Navigator.pop(context);
                  },
                ),
                BrandTile(
                  leading: const AppIcon(AppIcons.delete),
                  title: const Text('Move to trash'),
                  onTap: () {
                    repo.moveToTrash(note.id);
                    Navigator.pop(context);
                  },
                ),
              ],
      ),
    ),
  );
}

class _PinnedNoteCard extends ConsumerWidget {
  final Note note;
  final NoteScope scope;
  final String? folderName;

  const _PinnedNoteCard({
    required this.note,
    required this.scope,
    this.folderName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final roles = brand.noteRoles;
    final repo = ref.read(noteRepositoryProvider);
    final preview = note.isLocked
        ? 'This note is locked.'
        : NoteRepository.previewOf(note.content);
    final tags =
        ref.watch(tagsForNoteProvider(note.id)).valueOrNull ?? const [];
    final pillLabel =
        folderName ?? (tags.isNotEmpty ? '#${tags.first.name}' : null);

    return BrandTappable(
      onPressed: () {
        if (scope == NoteScope.trash) return;
        context.push('/note_editor', extra: note.id);
      },
      onLongPress: () => _showNoteActions(context, repo, note, scope),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: roles.tintFill,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: brand.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (note.isLocked)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AppIcon(
                      AppIcons.lock,
                      size: 16,
                      color: roles.textOnTint,
                    ),
                  ),
                AppIcon(AppIcons.pin, size: 16, color: roles.graphicOnTint),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: brand.ink.withValues(alpha: 0.8),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (pillLabel != null) ...[
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pillLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: roles.textOnTint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  'Edited ${Fmt.relativeDay(note.updatedAt)}',
                  style: TextStyle(fontSize: 12, color: roles.textOnTint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  final NoteScope scope;
  final String? folderName;

  const _NoteCard({required this.note, required this.scope, this.folderName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final repo = ref.read(noteRepositoryProvider);
    final checklist = note.isLocked
        ? const <({String text, bool checked})>[]
        : _extractChecklist(note.content);
    final preview = note.isLocked
        ? 'This note is locked.'
        : NoteRepository.previewOf(note.content);
    final tags =
        ref.watch(tagsForNoteProvider(note.id)).valueOrNull ?? const [];

    final dateLabel = scope == NoteScope.trash && note.deletedAt != null
        ? 'Deleted ${Fmt.relativeDay(note.deletedAt!)}'
        : Fmt.relativeDay(note.updatedAt);

    final footerParts = <String>[
      dateLabel,
      if (checklist.isNotEmpty)
        '${checklist.where((c) => c.checked).length} of ${checklist.length}'
      else if (folderName != null)
        folderName!
      else if (tags.isNotEmpty)
        '#${tags.first.name}',
    ];

    return BrandTappable(
      onPressed: () {
        if (scope == NoteScope.trash) return;
        context.push('/note_editor', extra: note.id);
      },
      onLongPress: () => _showNoteActions(context, repo, note, scope),
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.card(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    if (note.isLocked)
                      AppIcon(AppIcons.lock, size: 16, color: context.muted),
                  ],
                ),
                const SizedBox(height: 8),
                if (checklist.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in checklist.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: item.checked
                                      ? brand.success
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: item.checked
                                      ? null
                                      : Border.all(
                                          color: brand.outlineIdle,
                                          width: 2,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  item.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: item.checked
                                        ? brand.subtle
                                        : context.muted,
                                    decoration: item.checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                else if (preview.isNotEmpty)
                  Text(
                    preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              footerParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesDrawer extends ConsumerWidget {
  const _NotesDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final folders = ref.watch(foldersProvider).valueOrNull ?? const [];
    final tags = ref.watch(noteTagsProvider).valueOrNull ?? const [];
    final trashCount = ref.watch(trashCountProvider).valueOrNull ?? 0;
    final filter = ref.watch(noteFilterProvider);

    void apply(NoteFilter f) {
      ref.read(noteFilterProvider.notifier).state = f;
      Navigator.pop(context);
    }

    final dotColors = <Color>[
      brand.medicineRoles.graphicOnTint,
      brand.taskRoles.graphicOnTint,
      brand.habitRoles.graphicOnTint,
      brand.expenseRoles.graphicOnTint,
      brand.noteRoles.graphicOnTint,
    ];

    return Drawer(
      width: 316,
      backgroundColor: brand.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Notes',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    CircleIconButton(
                      icon: AppIcons.close,
                      tooltip: 'Close',
                      size: 40,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _DrawerPillRow(
                      icon: AppIcons.notes,
                      label: 'All Notes',
                      selected: filter == const NoteFilter(),
                      onTap: () => apply(const NoteFilter()),
                    ),
                    const SizedBox(height: 4),
                    _DrawerPillRow(
                      icon: AppIcons.star,
                      iconColor: brand.warningRoles.graphicOnTint,
                      label: 'Favorites',
                      selected: filter.scope == NoteScope.favorites,
                      onTap: () =>
                          apply(const NoteFilter(scope: NoteScope.favorites)),
                    ),
                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 4, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'FOLDERS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: context.muted,
                            ),
                          ),
                          BrandTooltip(
                            message: 'New folder',
                            child: BrandTappable(
                              onPressed: () => _createFolder(context, ref),
                              semanticsLabel: 'New folder',
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: AppIcon(
                                  AppIcons.add,
                                  size: 18,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (folders.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: AppShadows.card(theme.brightness),
                        ),
                        child: Column(
                          children: [
                            for (final (i, f) in folders.indexed)
                              BrandTappable(
                                onPressed: () => apply(
                                  NoteFilter(folderId: f.id, label: f.name),
                                ),
                                onLongPress: () async {
                                  Navigator.pop(context);
                                  final ok = await confirmDialog(
                                    context,
                                    'Delete folder?',
                                    'Notes inside will be kept and moved to All Notes.',
                                  );
                                  if (ok) {
                                    await ref
                                        .read(noteRepositoryProvider)
                                        .deleteFolder(f.id);
                                  }
                                },
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    border: i < folders.length - 1
                                        ? Border(
                                            bottom: BorderSide(
                                              color: brand.hairline,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color:
                                              dotColors[i % dotColors.length],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          f.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: filter.folderId == f.id
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: brand.ink,
                                          ),
                                        ),
                                      ),
                                      if (filter.folderId == f.id)
                                        AppIcon(
                                          AppIcons.check,
                                          size: 16,
                                          color: brand.ink,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Text(
                        'TAGS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: context.muted,
                        ),
                      ),
                    ),
                    if (tags.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'Tags you add to notes appear here.',
                          style: TextStyle(fontSize: 12, color: context.muted),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in tags)
                            BrandTappable(
                              onPressed: () => apply(
                                NoteFilter(tagId: t.id, label: '#${t.name}'),
                              ),
                              child: Container(
                                height: 42,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                alignment: Alignment.center,
                                width: null,
                                decoration: ShapeDecoration(
                                  color: filter.tagId == t.id
                                      ? brand.ink
                                      : brand.surface,
                                  shape: const StadiumBorder(),
                                  shadows: filter.tagId == t.id
                                      ? const []
                                      : AppShadows.circleButton(
                                          theme.brightness,
                                        ),
                                ),
                                child: Text(
                                  '#${t.name}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: filter.tagId == t.id
                                        ? brand.onInk
                                        : brand.ink,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: brand.outlineIdle)),
                ),
                child: Column(
                  children: [
                    _DrawerPillRow(
                      icon: AppIcons.archive,
                      label: 'Archive',
                      selected: filter.scope == NoteScope.archived,
                      onTap: () =>
                          apply(const NoteFilter(scope: NoteScope.archived)),
                    ),
                    const SizedBox(height: 2),
                    _DrawerPillRow(
                      icon: AppIcons.delete,
                      label: 'Trash',
                      trailing: trashCount > 0 ? '$trashCount' : null,
                      selected: filter.scope == NoteScope.trash,
                      onTap: () =>
                          apply(const NoteFilter(scope: NoteScope.trash)),
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

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await brandDialog<String>(
      context,
      title: 'New folder',
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: controller,
            hint: 'Folder name',
            autofocus: true,
            onSubmit: (v) => Navigator.pop(dialogContext, v),
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Create',
            onPressed: () => Navigator.pop(dialogContext, controller.text),
          ),
          const SizedBox(height: 8),
          BrandButton(
            label: 'Cancel',
            kind: BrandButtonKind.ghost,
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(noteRepositoryProvider).createFolder(name.trim());
    }
  }
}

class _DrawerPillRow extends StatelessWidget {
  final HugeIconData icon;
  final Color? iconColor;
  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerPillRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return BrandTappable(
      onPressed: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? brand.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 20,
              color: selected ? brand.onInk : (iconColor ?? brand.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? brand.onInk : brand.ink,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? brand.onInkMuted : context.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
