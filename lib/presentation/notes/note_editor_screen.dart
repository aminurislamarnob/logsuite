import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/speech_service.dart';
import '../../core/database/app_database.dart';
import '../../core/services/export_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/security_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/in_app_browser.dart';
import '../tasks/repository/task_repository.dart';
import 'providers/notes_provider.dart';
import 'repository/note_repository.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final int? noteId;
  const NoteEditorScreen({super.key, this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  quill.QuillController? _controller;
  final _titleController = TextEditingController();
  final _editorFocus = FocusNode();

  Note? _note;
  bool _loading = true;
  bool _unlocked = false;
  bool _listening = false;
  bool _dirty = false;
  bool _isPinned = false;
  bool _isLocked = false;
  List<String> _tags = [];
  int? _folderId;
  DateTime? _reminderAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(noteRepositoryProvider);
    quill.Document document;

    if (widget.noteId != null) {
      _note = await repo.getNote(widget.noteId!);
      if (_note != null) {
        _titleController.text = _note!.title;
        _folderId = _note!.folderId;
        _reminderAt = _note!.reminderAt;
        _isPinned = _note!.isPinned;
        _isLocked = _note!.isLocked;
        _tags = (await repo.tagsForNote(_note!.id)).map((t) => t.name).toList();
        document = _parseDelta(_note!.content);
        _unlocked = !_note!.isLocked;
      } else {
        document = quill.Document();
      }
    } else {
      document = quill.Document();
      _unlocked = true;
    }

    _controller =
        quill.QuillController(
          document: document,
          selection: const TextSelection.collapsed(offset: 0),
        )..addListener(() {
          if (mounted) setState(() => _dirty = true);
        });

    if (mounted) setState(() => _loading = false);

    if (_note?.isLocked == true) await _requestUnlock();
  }

  quill.Document _parseDelta(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List && decoded.isNotEmpty) {
        return quill.Document.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt or legacy content falls back to an empty document rather than
      // crashing the editor and stranding the user.
    }
    return quill.Document();
  }

  Future<void> _requestUnlock() async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.authenticate(
      reason: 'Unlock "${_note?.title ?? 'this note'}"',
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _unlocked = true);
      return;
    }

    // Biometric failed or was cancelled: offer the PIN before giving up.
    if (security.hasPin) {
      final pinOk = await promptForPin(
        context,
        security.verifyPin,
        title: 'Unlock note',
      );
      if (!mounted) return;
      if (pinOk) {
        setState(() => _unlocked = true);
      }
      return;
    }

    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _titleController.dispose();
    _editorFocus.dispose();
    if (_listening) ref.read(speechServiceProvider).stop();
    super.dispose();
  }

  String get _contentJson =>
      jsonEncode(_controller!.document.toDelta().toJson());

  List<String> _uncheckedItems() {
    if (_controller == null) return const [];
    final ops = _controller!.document.toDelta().toJson();
    final items = <String>[];
    final buffer = StringBuffer();

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String) continue;
      final attrs = op['attributes'] as Map?;

      for (var i = 0; i < insert.length; i++) {
        final ch = insert[i];
        if (ch == '\n') {
          if (attrs != null && attrs['list'] == 'unchecked') {
            final text = buffer.toString().trim();
            if (text.isNotEmpty) items.add(text);
          }
          buffer.clear();
        } else {
          buffer.write(ch);
        }
      }
    }
    return items;
  }

  Future<void> _save({bool pop = true}) async {
    final repo = ref.read(noteRepositoryProvider);
    final title = _titleController.text.trim().isEmpty
        ? 'Untitled'
        : _titleController.text.trim();

    int id;
    if (_note == null) {
      id = await repo.createNote(
        title: title,
        contentJson: _contentJson,
        folderId: _folderId,
      );
      await repo.updateNote(
        id,
        isPinned: _isPinned,
        isLocked: _isLocked,
        reminderAt: _reminderAt,
      );
      _note = await repo.getNote(id);
    } else {
      id = _note!.id;
      await repo.updateNote(
        id,
        title: title,
        contentJson: _contentJson,
        folderId: _folderId,
        clearFolder: _folderId == null,
        isPinned: _isPinned,
        isLocked: _isLocked,
        reminderAt: _reminderAt,
        clearReminder: _reminderAt == null,
      );
    }
    await repo.setNoteTags(id, _tags);

    final notifier = ref.read(notificationServiceProvider);
    if (_reminderAt != null) {
      await notifier.scheduleNoteReminder(
        noteId: id,
        title: title,
        when: _reminderAt!,
      );
    } else {
      await notifier.cancelNoteReminder(id);
    }

    _dirty = false;
    if (pop && mounted) Navigator.of(context).pop();
  }

  /// Pulls unchecked checklist lines out of the note and creates tasks.
  Future<void> _convertChecklistToTasks() async {
    final items = _uncheckedItems();
    if (items.isEmpty) {
      _toast('No unchecked checklist items found in this note.');
      return;
    }

    final repo = ref.read(taskRepositoryProvider);
    for (final title in items) {
      await repo.createTask(title: title);
    }
    _toast('Added ${items.length} task${items.length == 1 ? '' : 's'}.');
  }

  Future<void> _toggleDictation() async {
    final speech = ref.read(speechServiceProvider);
    if (_listening) {
      await speech.stop();
      setState(() => _listening = false);
      return;
    }
    final started = await speech.listen(
      onResult: (words, isFinal) {
        if (!isFinal || !mounted) return;
        setState(() => _listening = false);
        if (words.isEmpty) return;
        final index = _controller!.selection.baseOffset.clamp(
          0,
          _controller!.document.length - 1,
        );
        _controller!.document.insert(index, '$words ');
        _controller!.updateSelection(
          TextSelection.collapsed(offset: index + words.length + 1),
          quill.ChangeSource.local,
        );
      },
    );
    if (!started) {
      _toast('Speech recognition is not available on this device.');
      return;
    }
    setState(() => _listening = true);
  }

  void _toast(String message) {
    if (!mounted) return;
    brandToast(context, message);
  }

  void _toggleInlineAttribute(quill.Attribute attr) {
    final controller = _controller;
    if (controller == null) return;
    AppHaptics.selection();
    final isApplied = controller.getSelectionStyle().attributes.containsKey(
      attr.key,
    );
    controller.formatSelection(
      isApplied ? quill.Attribute.clone(attr, null) : attr,
    );
  }

  void _toggleBlockAttribute(quill.Attribute attr) {
    final controller = _controller;
    if (controller == null) return;
    AppHaptics.selection();
    final current = controller.getSelectionStyle().attributes[attr.key];
    final isSame = current?.value == attr.value;
    controller.formatSelection(
      isSame ? quill.Attribute.clone(attr, null) : attr,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _controller == null) {
      return const BrandScaffold(child: Center(child: BrandSpinner()));
    }
    if (_note?.isLocked == true && !_unlocked) {
      return BrandScaffold(
        header: const BrandTopBar(title: '', leadingIcon: AppIcons.back),
        child: EmptyState(
          icon: AppIcons.lock,
          title: 'Note locked',
          message: 'Authenticate to view this note.',
          actionLabel: 'Unlock',
          onAction: _requestUnlock,
        ),
      );
    }

    final theme = Theme.of(context);
    final brand = context.brand;
    final folders = ref.watch(foldersProvider).valueOrNull ?? const [];
    final folderName = folders
        .where((f) => f.id == _folderId)
        .firstOrNull
        ?.name;
    final uncheckedCount = _uncheckedItems().length;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _save();
      },
      child: BrandScaffold(
        header: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              8,
              AppSpacing.gutter,
              8,
            ),
            child: Row(
              children: [
                CircleIconButton(
                  icon: AppIcons.back,
                  tooltip: 'Back',
                  size: 44,
                  onPressed: () async {
                    if (_dirty) {
                      await _save();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _note == null
                        ? 'New note'
                        : _dirty
                        ? 'Unsaved'
                        : 'Saved · ${Fmt.relativeDay(_note!.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: context.muted),
                  ),
                ),
                const SizedBox(width: 8),
                BrandTooltip(
                  message: _isLocked ? 'Unlock note' : 'Lock note',
                  child: BrandTappable(
                    onPressed: () {
                      AppHaptics.selection();
                      setState(() {
                        _isLocked = !_isLocked;
                        _dirty = true;
                      });
                    },
                    semanticsLabel: _isLocked ? 'Unlock note' : 'Lock note',
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _isLocked
                            ? brand.noteRoles.tintFill
                            : brand.surface,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.circleButton(theme.brightness),
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        _isLocked ? AppIcons.lock : AppIcons.unlock,
                        size: 18,
                        color: _isLocked
                            ? brand.noteRoles.graphicOnTint
                            : brand.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BrandTooltip(
                  message: _isPinned ? 'Unpin' : 'Pin note',
                  child: BrandTappable(
                    onPressed: () {
                      AppHaptics.selection();
                      setState(() {
                        _isPinned = !_isPinned;
                        _dirty = true;
                      });
                    },
                    semanticsLabel: _isPinned ? 'Unpin' : 'Pin note',
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _isPinned
                            ? brand.noteRoles.tintFill
                            : brand.surface,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.circleButton(theme.brightness),
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.pin,
                        size: 18,
                        color: _isPinned
                            ? brand.noteRoles.graphicOnTint
                            : brand.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleIconButton(
                  icon: AppIcons.moreHorizontal,
                  tooltip: 'More',
                  size: 44,
                  onPressed: _showMoreSheet,
                ),
                const SizedBox(width: 8),
                CircleIconButton(
                  icon: AppIcons.check,
                  tooltip: 'Save',
                  size: 44,
                  filled: true,
                  color: brand.ink,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    4,
                    AppSpacing.gutter,
                    0,
                  ),
                  child: BrandField(
                    controller: _titleController,
                    hint: 'Title',
                    bare: true,
                    onChanged: (_) => _dirty = true,
                    textStyle: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                      color: brand.ink,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    4,
                    AppSpacing.gutter,
                    10,
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (folderName != null)
                        BrandTappable(
                          onPressed: _pickFolder,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                            decoration: ShapeDecoration(
                              color: brand.noteRoles.tintFill,
                              shape: const StadiumBorder(),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  AppIcons.folder,
                                  size: 15,
                                  color: brand.noteRoles.textOnTint,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  folderName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: brand.noteRoles.textOnTint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (final t in _tags)
                        BrandTappable(
                          onPressed: _editTags,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: ShapeDecoration(
                              color: brand.surface,
                              shape: const StadiumBorder(),
                              shadows: AppShadows.circleButton(
                                theme.brightness,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '#$t',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: brand.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_reminderAt != null)
                        BrandTappable(
                          onPressed: _pickReminder,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                            decoration: ShapeDecoration(
                              color: brand.surface,
                              shape: const StadiumBorder(),
                              shadows: AppShadows.circleButton(
                                theme.brightness,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  AppIcons.notifications,
                                  size: 15,
                                  color: brand.ink,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  Fmt.due(_reminderAt!, withTime: true),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: brand.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      BrandTappable(
                        onPressed: _editTags,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: brand.outlineIdle,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                AppIcons.add,
                                size: 14,
                                color: context.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Tag',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (uncheckedCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      10,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BrandTappable(
                        onPressed: _convertChecklistToTasks,
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
                          decoration: ShapeDecoration(
                            color: brand.taskRoles.tintFill,
                            shape: const StadiumBorder(),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                AppIcons.tasks,
                                size: 18,
                                color: brand.taskRoles.textOnTint,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Convert $uncheckedCount ${uncheckedCount == 1 ? 'item' : 'items'} to tasks',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: brand.taskRoles.textOnTint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: quill.QuillEditor.basic(
                    controller: _controller!,
                    focusNode: _editorFocus,
                    config: quill.QuillEditorConfig(
                      placeholder: 'Keep writing…',
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        12,
                        AppSpacing.gutter,
                        110,
                      ),
                      expands: true,
                      onLaunchUrl: (url) =>
                          InAppBrowserScreen.open(context, url),
                    ),
                  ),
                ),
              ],
            ),

            // Bottom floating dark toolbar pill (28-note-editor.html)
            Positioned(
              left: AppSpacing.gutter,
              right: AppSpacing.gutter,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: Container(
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: ShapeDecoration(
                  color: brand.heroSurface,
                  shape: const StadiumBorder(),
                  shadows: AppShadows.navBar(theme.brightness),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ToolbarButton(
                      tooltip: 'Bold',
                      active: _controller!
                          .getSelectionStyle()
                          .attributes
                          .containsKey(quill.Attribute.bold.key),
                      onPressed: () =>
                          _toggleInlineAttribute(quill.Attribute.bold),
                      child: const Text(
                        'B',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _ToolbarButton(
                      tooltip: 'Italic',
                      active: _controller!
                          .getSelectionStyle()
                          .attributes
                          .containsKey(quill.Attribute.italic.key),
                      onPressed: () =>
                          _toggleInlineAttribute(quill.Attribute.italic),
                      child: const Text(
                        'I',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    _ToolbarButton(
                      tooltip: 'Heading',
                      active: _controller!
                          .getSelectionStyle()
                          .attributes
                          .containsKey(quill.Attribute.header.key),
                      onPressed: () =>
                          _toggleBlockAttribute(quill.Attribute.h2),
                      child: const Text(
                        'H',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _ToolbarButton(
                      tooltip: 'Checklist',
                      active:
                          _controller!
                                  .getSelectionStyle()
                                  .attributes[quill.Attribute.list.key]
                                  ?.value ==
                              'unchecked' ||
                          _controller!
                                  .getSelectionStyle()
                                  .attributes[quill.Attribute.list.key]
                                  ?.value ==
                              'checked',
                      onPressed: () =>
                          _toggleBlockAttribute(quill.Attribute.unchecked),
                      child: const AppIcon(
                        AppIcons.checklist,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    _ToolbarButton(
                      tooltip: 'Bullet list',
                      active:
                          _controller!
                              .getSelectionStyle()
                              .attributes[quill.Attribute.list.key]
                              ?.value ==
                          'bullet',
                      onPressed: () =>
                          _toggleBlockAttribute(quill.Attribute.ul),
                      child: const AppIcon(
                        AppIcons.compact,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    BrandTooltip(
                      message: _listening ? 'Stop dictation' : 'Dictate',
                      child: BrandTappable(
                        onPressed: _toggleDictation,
                        semanticsLabel: _listening
                            ? 'Stop dictation'
                            : 'Dictate',
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _listening ? brand.danger : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: AppIcon(
                            _listening ? AppIcons.micOff : AppIcons.mic,
                            size: 20,
                            color: _listening ? Colors.white : brand.inkDeep,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreSheet() {
    brandSheet(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: 'Note options',
        child: TileColumn(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.tag),
              title: const Text('Tags'),
              subtitle: Text(_tags.isEmpty ? 'None' : _tags.join(', ')),
              onTap: () {
                Navigator.pop(sheetContext);
                _editTags();
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.folder),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFolder();
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.alarmAdd),
              title: const Text('Set reminder'),
              subtitle: _reminderAt == null
                  ? null
                  : Text(Fmt.due(_reminderAt!, withTime: true)),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickReminder();
              },
            ),
            const BrandDivider(),
            BrandTile(
              leading: const AppIcon(AppIcons.checklist),
              title: const Text('Convert checklist to tasks'),
              onTap: () {
                Navigator.pop(sheetContext);
                _convertChecklistToTasks();
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.pdf),
              title: const Text('Export as PDF'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _save(pop: false);
                await ref
                    .read(exportServiceProvider)
                    .shareNoteAsPdf(
                      title: _titleController.text.trim(),
                      body: NoteRepository.plainTextOf(_contentJson),
                    );
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.share),
              title: const Text('Share as text'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref
                    .read(exportServiceProvider)
                    .shareText(
                      '${_titleController.text}\n\n'
                      '${NoteRepository.plainTextOf(_contentJson)}',
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTags() async {
    final controller = TextEditingController(text: _tags.join(', '));
    final result = await brandDialog<String>(
      context,
      title: 'Tags',
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandField(
            controller: controller,
            hint: 'work, ideas, urgent',
            helper: 'Separate with commas',
            autofocus: true,
          ),
          const SizedBox(height: 20),
          BrandButton(
            label: 'Save',
            onPressed: () => Navigator.pop(dialogContext, controller.text),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      _tags = result
          .split(',')
          .map((e) => e.trim().replaceAll('#', ''))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      _dirty = true;
    });
  }

  Future<void> _pickFolder() async {
    final folders = await ref.read(noteRepositoryProvider).watchFolders().first;
    if (!mounted) return;
    final picked = await brandSheet<int?>(
      context: context,
      builder: (_) => SheetScaffold(
        title: 'Move to folder',
        child: TileColumn(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.clear),
              title: const Text('No folder'),
              onTap: () => Navigator.pop(context, -1),
            ),
            ...folders.map(
              (f) => BrandTile(
                leading: const AppIcon(AppIcons.folder),
                title: Text(f.name),
                selected: f.id == _folderId,
                onTap: () => Navigator.pop(context, f.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _folderId = picked == -1 ? null : picked;
      _dirty = true;
    });
  }

  Future<void> _pickReminder() async {
    final fallback = DateTime.now().add(const Duration(hours: 1));
    final date = await brandDatePicker(
      context,
      initial: _reminderAt ?? fallback,
      first: DateTime.now().subtract(const Duration(days: 1)),
      last: DateTime.now().add(const Duration(days: 3650)),
      title: 'Reminder date',
    );
    if (date == null || !mounted) return;
    final at = _reminderAt ?? fallback;
    final minutes = await brandTimePicker(
      context,
      initialMinutes: at.hour * 60 + at.minute,
      title: 'Reminder time',
    );
    if (minutes == null) return;
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        minutes ~/ 60,
        minutes % 60,
      );
      _dirty = true;
    });
  }
}

class _ToolbarButton extends StatelessWidget {
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final Widget child;

  const _ToolbarButton({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BrandTooltip(
      message: tooltip,
      child: BrandTappable(
        onPressed: onPressed,
        semanticsLabel: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
