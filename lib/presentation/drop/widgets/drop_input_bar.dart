import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../notes/providers/notes_provider.dart';
import '../providers/drop_provider.dart';
import '../repository/drop_repository.dart';

class DropInputBar extends ConsumerStatefulWidget {
  final VoidCallback? onAttachPressed;

  const DropInputBar({
    super.key,
    this.onAttachPressed,
  });

  @override
  ConsumerState<DropInputBar> createState() => _DropInputBarState();
}

class _DropInputBarState extends ConsumerState<DropInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSubmitting = false;

  String? _activeTagQuery;
  int? _hashIndex;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _activeTagQuery != null) {
      setState(() {
        _activeTagQuery = null;
        _hashIndex = null;
      });
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid || selection.baseOffset < 0) {
      if (_activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _hashIndex = null;
        });
      }
      return;
    }

    final cursor = selection.baseOffset;
    if (cursor > text.length) {
      if (_activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _hashIndex = null;
        });
      }
      return;
    }

    final textBeforeCursor = text.substring(0, cursor);
    final lastHash = textBeforeCursor.lastIndexOf('#');

    if (lastHash == -1) {
      if (_activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _hashIndex = null;
        });
      }
      return;
    }

    // Ensure # is either at the beginning of the text or preceded by whitespace
    if (lastHash > 0 && textBeforeCursor[lastHash - 1].trim().isNotEmpty) {
      if (_activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _hashIndex = null;
        });
      }
      return;
    }

    final query = textBeforeCursor.substring(lastHash + 1);

    // If query contains whitespace or characters that end a hashtag, close suggestions
    if (query.contains(RegExp(r'\s')) ||
        !RegExp(r'^[a-zA-Z0-9_\-]*$').hasMatch(query)) {
      if (_activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _hashIndex = null;
        });
      }
      return;
    }

    if (_activeTagQuery != query || _hashIndex != lastHash) {
      setState(() {
        _activeTagQuery = query;
        _hashIndex = lastHash;
      });
    }
  }

  void _selectTag(String tag) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (_hashIndex == null || _hashIndex! < 0 || _hashIndex! > text.length) {
      return;
    }

    final prefix = text.substring(0, _hashIndex!);
    final suffix = (cursor >= 0 && cursor <= text.length) ? text.substring(cursor) : '';
    final suffixStartsWithSpace = suffix.startsWith(' ');
    final replacement = suffixStartsWithSpace ? '#$tag' : '#$tag ';
    final newText = '$prefix$replacement$suffix';
    final newCursor = prefix.length + replacement.length + (suffixStartsWithSpace ? 1 : 0);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    setState(() {
      _activeTagQuery = null;
      _hashIndex = null;
    });

    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final rawText = _controller.text.trim();
    if (rawText.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      // Extract hashtags (#tag)
      final hashtagRegex = RegExp(r'#([a-zA-Z0-9_\-]+)');
      final matches = hashtagRegex.allMatches(rawText);
      final tags = matches.map((m) => m.group(1)!).toList();

      // Determine initial asset type
      final isUrl = rawText.startsWith('http://') || rawText.startsWith('https://');
      String assetType = 'clip';
      String? domain;

      if (isUrl) {
        try {
          final uri = Uri.parse(rawText.split(RegExp(r'\s+')).first);
          domain = uri.host.replaceFirst('www.', '');
          if (domain.contains('youtube.com') ||
              domain.contains('youtu.be') ||
              domain.contains('vimeo.com') ||
              domain.contains('tiktok.com')) {
            assetType = 'video';
          } else {
            assetType = 'article';
          }
        } catch (_) {
          assetType = 'article';
        }
      }

      await ref.read(dropRepositoryProvider).createDrop(
            content: rawText,
            assetType: assetType,
            sourceDomain: domain,
            tags: tags,
          );

      _controller.clear();
      _focusNode.unfocus();
      if (mounted) {
        setState(() {
          _activeTagQuery = null;
          _hashIndex = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;

    // Collect all existing (old) tags across drops and notes
    final dropTagsAsync = ref.watch(dropTagsStreamProvider);
    final noteTagsAsync = ref.watch(noteTagsProvider);

    final tagSet = <String>{};
    final dropTags = dropTagsAsync.value ?? const <String>[];
    for (final t in dropTags) {
      final clean = t.trim().replaceAll('#', '');
      if (clean.isNotEmpty) tagSet.add(clean);
    }

    final noteTags = (noteTagsAsync.value ?? const <Tag>[]).map((t) => t.name);
    for (final t in noteTags) {
      final clean = t.trim().replaceAll('#', '');
      if (clean.isNotEmpty) tagSet.add(clean);
    }

    List<String> matchingTags = [];
    if (_activeTagQuery != null) {
      final q = _activeTagQuery!.toLowerCase();
      matchingTags = tagSet.where((t) => t.toLowerCase().contains(q)).toList();
      matchingTags.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        final aStarts = aLower.startsWith(q);
        final bStarts = bLower.startsWith(q);
        if (aStarts && !bStarts) return -1;
        if (!aStarts && bStarts) return 1;
        return aLower.compareTo(bLower);
      });
    }

    final showSuggestions = _activeTagQuery != null && matchingTags.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: brand.hairline, width: 1),
        ),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -2),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSuggestions)
              _buildTagSuggestionsCard(
                context,
                theme: theme,
                brand: brand,
                matchingTags: matchingTags,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.onAttachPressed != null) ...[
                    IconButton(
                      icon: const AppIcon(AppIcons.camera, size: 22),
                      tooltip: 'Attach photo or screenshot',
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      onPressed: widget.onAttachPressed,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: brand.canvas,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: brand.hairline),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'Drop a link, note or #tag...',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45),
                            fontSize: 14,
                          ),
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: ShapeDecoration(
                      color: brand.drop,
                      shape: const CircleBorder(),
                    ),
                    child: IconButton(
                      icon: _isSubmitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const AppIcon(
                              AppIcons.arrowUp,
                              color: Colors.white,
                              size: 20,
                            ),
                      tooltip: 'Drop',
                      onPressed: _isSubmitting ? null : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSuggestionsCard(
    BuildContext context, {
    required ThemeData theme,
    required dynamic brand,
    required List<String> matchingTags,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: brand.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.35 : 0.08,
            ),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  AppIcon(AppIcons.tag, size: 14, color: brand.drop),
                  const SizedBox(width: 6),
                  Text(
                    'SUGGESTED TAGS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${matchingTags.length} ${matchingTags.length == 1 ? 'tag' : 'tags'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _activeTagQuery = null;
                        _hashIndex = null;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: AppIcon(
                        AppIcons.close,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: brand.hairline),
            // Scrollable list of suggestion tiles
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: matchingTags.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 48,
                  color: brand.hairline.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final tag = matchingTags[index];
                  return _TagSuggestionTile(
                    key: ValueKey('tag_suggestion_$tag'),
                    tag: tag,
                    query: _activeTagQuery ?? '',
                    onTap: () => _selectTag(tag),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagSuggestionTile extends StatelessWidget {
  final String tag;
  final String query;
  final VoidCallback onTap;

  const _TagSuggestionTile({
    super.key,
    required this.tag,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: brand.drop.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: brand.drop,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildHighlightedTag(theme, brand),
              ),
              AppIcon(
                AppIcons.arrowUp,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedTag(ThemeData theme, dynamic brand) {
    if (query.isEmpty) {
      return Text(
        tag,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    final lowerTag = tag.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerTag.indexOf(lowerQuery);

    if (matchIndex == -1) {
      return Text(
        tag,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    final before = tag.substring(0, matchIndex);
    final matched = tag.substring(matchIndex, matchIndex + query.length);
    final after = tag.substring(matchIndex + query.length);

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSurface,
        ),
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: matched,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: brand.drop,
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }
}
