import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _pluralLabel(ResultKind kind) => switch (kind) {
    ResultKind.task => 'Tasks',
    ResultKind.note => 'Notes',
    ResultKind.expense => 'Expenses',
    ResultKind.medicine => 'Medicine',
    ResultKind.habit => 'Habits',
    ResultKind.focus => 'Focus',
  };

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final filter = ref.watch(searchKindFilterProvider);
    final settings = ref.watch(settingsProvider);
    final query = ref.watch(searchQueryProvider);
    final brand = context.brand;
    final theme = Theme.of(context);

    final kinds = ResultKind.values
        .where((k) => settings.isEnabled(k.module))
        .toList();
    final allHits = results.valueOrNull ?? const <SearchHit>[];

    return BrandScaffold(
      header: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                8,
                AppSpacing.gutter,
                10,
              ),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: AppIcons.back,
                    tooltip: 'Back',
                    size: 44,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: brand.ink, width: 2),
                        boxShadow: AppShadows.composer(theme.brightness),
                      ),
                      child: Row(
                        children: [
                          AppIcon(AppIcons.search, size: 18, color: brand.ink),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search across every module',
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: context.subtle,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) =>
                                  ref.read(searchQueryProvider.notifier).state =
                                      v,
                            ),
                          ),
                          if (query.isNotEmpty)
                            BrandTappable(
                              onPressed: () {
                                _controller.clear();
                                ref.read(searchQueryProvider.notifier).state =
                                    '';
                              },
                              semanticsLabel: 'Clear',
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: brand.canvas,
                                  shape: BoxShape.circle,
                                ),
                                child: AppIcon(
                                  AppIcons.close,
                                  size: 16,
                                  color: brand.ink,
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
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                children: [
                  _FilterTab(
                    label: allHits.isEmpty ? 'All' : 'All ${allHits.length}',
                    selected: filter == null,
                    onTap: () =>
                        ref.read(searchKindFilterProvider.notifier).state =
                            null,
                  ),
                  for (final k in kinds) ...[
                    const SizedBox(width: 6),
                    Builder(
                      builder: (context) {
                        final count = allHits.where((h) => h.kind == k).length;
                        final label = count > 0
                            ? '${_pluralLabel(k)} $count'
                            : _pluralLabel(k);
                        return _FilterTab(
                          label: label,
                          dotColor: k.color(brand),
                          selected: filter == k,
                          onTap: () =>
                              ref
                                  .read(searchKindFilterProvider.notifier)
                                  .state = filter == k
                              ? null
                              : k,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
      child: results.when(
        data: (hits) {
          if (query.trim().length < 2) {
            return const EmptyState(
              icon: AppIcons.search,
              title: 'Search across every module',
              message:
                  'Notes, tasks, habits, medicines, expenses and focus '
                  'sessions — all from one bar.',
            );
          }
          if (hits.isEmpty) {
            return EmptyState(
              icon: AppIcons.searchOff,
              title: 'No matches for "$query"',
            );
          }

          final grouped = <ResultKind, List<SearchHit>>{};
          for (final h in hits) {
            grouped.putIfAbsent(h.kind, () => []).add(h);
          }

          return ListView(
            padding: pageInsets(context, top: 8),
            children: [
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                  child: Text(
                    _pluralLabel(entry.key).toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: brand.roleFor(entry.key.color(brand)).textOnTint,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    boxShadow: AppShadows.card(theme.brightness),
                  ),
                  child: Column(
                    children: [
                      for (final (idx, hit) in entry.value.indexed)
                        _SearchHitRow(
                          hit: hit,
                          query: query.trim(),
                          showDivider: idx < entry.value.length - 1,
                          onTap: () => _open(hit),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
        loading: () => const Center(child: BrandSpinner()),
        error: (e, _) =>
            EmptyState(icon: AppIcons.error, title: 'Error', message: '$e'),
      ),
    );
  }

  void _open(SearchHit hit) {
    switch (hit.kind) {
      case ResultKind.note:
        context.push('/note_editor', extra: hit.id);
      case ResultKind.task:
        context.push('/tasks');
      case ResultKind.habit:
        context.push('/habits');
      case ResultKind.medicine:
        context.push('/medicine');
      case ResultKind.expense:
        context.push('/expenses');
      case ResultKind.focus:
        context.push('/focus');
    }
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final Color? dotColor;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    this.dotColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return BrandTappable(
      onPressed: onTap,
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 12),
        decoration: BoxDecoration(
          color: selected ? brand.ink : brand.surface,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null && !selected) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? brand.onInk : context.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHitRow extends StatelessWidget {
  final SearchHit hit;
  final String query;
  final bool showDivider;
  final VoidCallback onTap;

  const _SearchHitRow({
    required this.hit,
    required this.query,
    required this.showDivider,
    required this.onTap,
  });

  Widget _highlightedText(
    BuildContext context,
    String text, {
    required TextStyle style,
    int maxLines = 1,
  }) {
    final brand = context.brand;
    if (query.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);
    if (idx < 0) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + query.length);
    final after = text.substring(idx + query.length);
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: match,
            style: style.copyWith(
              backgroundColor: brand.medicineRoles.tintFill,
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final accent = hit.kind.color(brand);
    final roles = brand.roleFor(accent);

    return BrandTappable(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: brand.hairline))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: roles.tintFill,
                borderRadius: BorderRadius.circular(11),
              ),
              child: AppIcon(
                hit.kind.icon,
                size: 17,
                color: roles.graphicOnTint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightedText(
                    context,
                    hit.title,
                    style: baseStyle.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _highlightedText(
                    context,
                    hit.subtitle,
                    maxLines: 2,
                    style: baseStyle.copyWith(
                      fontSize: 12,
                      color: context.muted,
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
}
