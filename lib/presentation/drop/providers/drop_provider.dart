import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/drop_with_tags.dart';
import '../repository/drop_repository.dart';

final dropFilterTypeProvider = StateProvider<String>((ref) => 'all');
final dropTriageStatusProvider = StateProvider<String>((ref) => 'inbox');
final dropSelectedTagProvider = StateProvider<String?>((ref) => null);
final dropSearchQueryProvider = StateProvider<String>((ref) => '');
final dropSelectedIdsProvider = StateProvider<Set<int>>((ref) => {});

final dropTagsStreamProvider = StreamProvider<List<String>>((ref) {
  final repo = ref.watch(dropRepositoryProvider);
  return repo.watchAllTags();
});

final dropsStreamProvider = StreamProvider<List<DropWithTags>>((ref) {
  final repo = ref.watch(dropRepositoryProvider);
  final filterType = ref.watch(dropFilterTypeProvider);
  final triageStatus = ref.watch(dropTriageStatusProvider);
  final selectedTag = ref.watch(dropSelectedTagProvider);
  final query = ref.watch(dropSearchQueryProvider);

  final isFavorites = filterType == 'favorites';
  final effectiveAssetType =
      (filterType == 'all' || isFavorites) ? null : filterType;

  return repo.watchDrops(
    triageStatus: isFavorites ? null : triageStatus,
    assetType: effectiveAssetType,
    isPinned: isFavorites ? true : null,
    tag: selectedTag,
    query: query,
  );
});

final unreadDropsCountProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(dropRepositoryProvider);
  return repo.watchDrops(triageStatus: 'inbox').map((drops) => drops.length);
});

final recentDropsProvider = StreamProvider<List<DropWithTags>>((ref) {
  final repo = ref.watch(dropRepositoryProvider);
  return repo
      .watchDrops(triageStatus: 'inbox')
      .map((drops) => drops.take(4).toList());
});
