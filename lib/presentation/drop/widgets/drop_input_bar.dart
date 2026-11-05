import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../notes/providers/notes_provider.dart';
import '../providers/drop_gamification_provider.dart';
import '../providers/drop_provider.dart';
import '../repository/drop_repository.dart';
import '../utils/drop_gamification_feedback.dart';

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
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  bool _isSubmitting = false;
  String? _activeTagQuery;
  String? _searchQueryOverride;
  int? _hashIndex;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    // Only dismiss if neither the main text field nor the search box has focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_focusNode.hasFocus &&
          !_searchFocusNode.hasFocus &&
          _activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _searchQueryOverride = null;
          _hashIndex = null;
        });
      }
    });
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid || selection.baseOffset < 0) {
      if (_activeTagQuery != null) {
        setState(() {
          _activeTagQuery = null;
          _searchQueryOverride = null;
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
          _searchQueryOverride = null;
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
          _searchQueryOverride = null;
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
          _searchQueryOverride = null;
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
          _searchQueryOverride = null;
          _hashIndex = null;
        });
      }
      return;
    }

    if (_activeTagQuery != query || _hashIndex != lastHash) {
      setState(() {
        _activeTagQuery = query;
        _searchQueryOverride = null;
        _hashIndex = lastHash;
      });
      if (_searchController.text != query) {
        _searchController.value = TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
        );
      }
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
      _searchQueryOverride = null;
      _hashIndex = null;
    });

    _searchFocusNode.unfocus();
    _focusNode.requestFocus();
  }

  static bool _isSubsequence(String query, String text) {
    int qIdx = 0;
    int tIdx = 0;
    while (qIdx < query.length && tIdx < text.length) {
      if (query[qIdx] == text[tIdx]) {
        qIdx++;
      }
      tIdx++;
    }
    return qIdx == query.length;
  }

  static int _matchRank(String tag, String query) {
    if (query.isEmpty) return 0;
    final t = tag.toLowerCase();
    final q = query.toLowerCase();
    if (t == q) return 0;
    if (t.startsWith(q)) return 1;
    if (t.contains(q)) return 2;
    if (_isSubsequence(q, t)) return 3;
    return -1;
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

      final reward = await ref
          .read(dropGamificationProvider.notifier)
          .recordDropCaptured(hasTags: tags.isNotEmpty);

      _controller.clear();
      _focusNode.unfocus();
      if (mounted) {
        setState(() {
          _activeTagQuery = null;
          _searchQueryOverride = null;
          _hashIndex = null;
        });
        DropGamificationFeedback.show(context, reward);
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

    final effectiveQuery = _searchQueryOverride ?? _activeTagQuery ?? '';

    List<String> matchingTags = [];
    if (_activeTagQuery != null) {
      matchingTags = tagSet
          .where((t) => _matchRank(t, effectiveQuery) >= 0)
          .toList();
      matchingTags.sort((a, b) {
        final rankA = _matchRank(a, effectiveQuery);
        final rankB = _matchRank(b, effectiveQuery);
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    }

    final showSuggestions = _activeTagQuery != null;

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
                tagSet: tagSet,
                effectiveQuery: effectiveQuery,
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
                        key: const ValueKey('drop_message_input_field'),
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
    required Set<String> tagSet,
    required String effectiveQuery,
  }) {
    final isExactMatch = tagSet.any(
      (t) => t.toLowerCase() == effectiveQuery.toLowerCase().trim(),
    );
    final canCreateNew = effectiveQuery.trim().isNotEmpty && !isExactMatch;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      constraints: const BoxConstraints(maxHeight: 220),
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
                    'SEARCH TAGS',
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
                    key: const ValueKey('dismiss_tag_suggestions'),
                    onTap: () {
                      setState(() {
                        _activeTagQuery = null;
                        _searchQueryOverride = null;
                        _hashIndex = null;
                      });
                      _searchFocusNode.unfocus();
                      _focusNode.requestFocus();
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

            // Search input field
            Container(
              height: 36,
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brand.hairline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.search,
                    size: 15,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('mention_tag_search_field'),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search or filter tags...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.4),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        fillColor: Colors.transparent,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQueryOverride = val;
                        });
                      },
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      key: const ValueKey('clear_tag_search'),
                      onTap: () {
                        _searchController.clear();
                        setState(() {
                          _searchQueryOverride = '';
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: AppIcon(
                          AppIcons.close,
                          size: 14,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: brand.hairline),

            // Scrollable list of suggestion tiles
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (matchingTags.isEmpty && !canCreateNew)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Center(
                        child: Text(
                          tagSet.isEmpty
                              ? 'No tags saved yet. Type a name to create one.'
                              : 'No matching tags found.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ...matchingTags.map((tag) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TagSuggestionTile(
                            key: ValueKey('tag_suggestion_$tag'),
                            tag: tag,
                            query: effectiveQuery,
                            onTap: () => _selectTag(tag),
                          ),
                          Divider(
                            height: 1,
                            indent: 48,
                            color: brand.hairline.withValues(alpha: 0.5),
                          ),
                        ],
                      )),
                  if (canCreateNew)
                    _CreateTagTile(
                      key: ValueKey('create_tag_${effectiveQuery.trim()}'),
                      tag: effectiveQuery.trim(),
                      onTap: () => _selectTag(effectiveQuery.trim()),
                    ),
                ],
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

    if (matchIndex != -1) {
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

    // Subsequence match highlighting
    final spans = <TextSpan>[];
    int qIdx = 0;
    for (int i = 0; i < tag.length; i++) {
      final char = tag[i];
      if (qIdx < lowerQuery.length && char.toLowerCase() == lowerQuery[qIdx]) {
        spans.add(
          TextSpan(
            text: char,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: brand.drop,
            ),
          ),
        );
        qIdx++;
      } else {
        spans.add(TextSpan(text: char));
      }
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSurface,
        ),
        children: spans,
      ),
    );
  }
}

class _CreateTagTile extends StatelessWidget {
  final String tag;
  final VoidCallback onTap;

  const _CreateTagTile({
    super.key,
    required this.tag,
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
                  color: brand.drop.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.add,
                  size: 14,
                  color: brand.drop,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: 'Create tag '),
                      TextSpan(
                        text: '#$tag',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: brand.drop,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: brand.drop.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: brand.drop,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
