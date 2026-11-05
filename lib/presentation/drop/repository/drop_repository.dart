import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';
import '../models/drop_with_tags.dart';
import '../services/drop_metadata_scraper.dart';

final dropRepositoryProvider = Provider<DropRepository>((ref) {
  return DropRepository(ref.watch(databaseProvider));
});

class DropRepository {
  final AppDatabase _db;
  final DropMetadataScraper _scraper;

  DropRepository(this._db, {DropMetadataScraper? scraper})
      : _scraper = scraper ?? DropMetadataScraper();

  Stream<List<DropWithTags>> watchDrops({
    String? triageStatus,
    String? assetType,
    bool? isPinned,
    String? tag,
    String? query,
  }) {
    final dropsQuery = _db.select(_db.drops);

    if (triageStatus != null) {
      dropsQuery.where((d) => d.triageStatus.equals(triageStatus));
    }

    if (assetType != null && assetType != 'all') {
      dropsQuery.where((d) => d.assetType.equals(assetType));
    }

    if (isPinned != null) {
      dropsQuery.where((d) => d.isPinned.equals(isPinned));
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim().toLowerCase()}%';
      dropsQuery.where((d) =>
          d.content.lower().like(q) |
          d.title.lower().like(q) |
          d.description.lower().like(q) |
          d.ocrText.lower().like(q) |
          d.sourceDomain.lower().like(q));
    }

    dropsQuery.orderBy([
      (d) => OrderingTerm(expression: d.isPinned, mode: OrderingMode.desc),
      (d) => OrderingTerm(expression: d.createdAt, mode: OrderingMode.desc),
    ]);

    return dropsQuery.watch().asyncMap((dropsList) async {
      if (dropsList.isEmpty) return <DropWithTags>[];

      final dropIds = dropsList.map((d) => d.id).toList();
      final tagsQuery = _db.select(_db.dropTags)
        ..where((t) => t.dropId.isIn(dropIds));
      final allTags = await tagsQuery.get();

      final tagsByDrop = <int, List<String>>{};
      for (final tagRow in allTags) {
        tagsByDrop.putIfAbsent(tagRow.dropId, () => []).add(tagRow.tag);
      }

      var result = dropsList.map((drop) {
        return DropWithTags(
          drop: drop,
          tags: tagsByDrop[drop.id] ?? const [],
        );
      }).toList();

      if (tag != null && tag.isNotEmpty) {
        result = result.where((d) => d.tags.contains(tag)).toList();
      }

      return result;
    });
  }

  Future<List<DropWithTags>> getDrops({
    String? triageStatus,
    String? assetType,
    bool? isPinned,
    String? tag,
    String? query,
  }) async {
    final dropsQuery = _db.select(_db.drops);

    if (triageStatus != null) {
      dropsQuery.where((d) => d.triageStatus.equals(triageStatus));
    }

    if (assetType != null && assetType != 'all') {
      dropsQuery.where((d) => d.assetType.equals(assetType));
    }

    if (isPinned != null) {
      dropsQuery.where((d) => d.isPinned.equals(isPinned));
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim().toLowerCase()}%';
      dropsQuery.where((d) =>
          d.content.lower().like(q) |
          d.title.lower().like(q) |
          d.description.lower().like(q) |
          d.ocrText.lower().like(q) |
          d.sourceDomain.lower().like(q));
    }

    dropsQuery.orderBy([
      (d) => OrderingTerm(expression: d.isPinned, mode: OrderingMode.desc),
      (d) => OrderingTerm(expression: d.createdAt, mode: OrderingMode.desc),
    ]);

    final dropsList = await dropsQuery.get();
    if (dropsList.isEmpty) return [];

    final dropIds = dropsList.map((d) => d.id).toList();
    final tagsQuery = _db.select(_db.dropTags)
      ..where((t) => t.dropId.isIn(dropIds));
    final allTags = await tagsQuery.get();

    final tagsByDrop = <int, List<String>>{};
    for (final tagRow in allTags) {
      tagsByDrop.putIfAbsent(tagRow.dropId, () => []).add(tagRow.tag);
    }

    var result = dropsList.map((drop) {
      return DropWithTags(
        drop: drop,
        tags: tagsByDrop[drop.id] ?? const [],
      );
    }).toList();

    if (tag != null && tag.isNotEmpty) {
      result = result.where((d) => d.tags.contains(tag)).toList();
    }

    return result;
  }

  Future<DropWithTags?> getDrop(int id) async {
    final drop = await (_db.select(_db.drops)..where((d) => d.id.equals(id)))
        .getSingleOrNull();
    if (drop == null) return null;

    final tags = await (_db.select(_db.dropTags)
          ..where((t) => t.dropId.equals(id)))
        .get();

    return DropWithTags(
      drop: drop,
      tags: tags.map((t) => t.tag).toList(),
    );
  }

  Future<int> createDrop({
    required String content,
    String? title,
    String? description,
    String? previewImageUrl,
    String? faviconUrl,
    String? sourceDomain,
    String assetType = 'clip',
    String triageStatus = 'inbox',
    bool isPinned = false,
    String? mediaPath,
    String? mediaThumbnailPath,
    String? ocrText,
    DateTime? reminderAt,
    List<String> tags = const [],
  }) async {
    final id = await _db.transaction(() async {
      final now = DateTime.now();
      final id = await _db.into(_db.drops).insert(
            DropsCompanion.insert(
              content: content,
              title: Value(title),
              description: Value(description),
              previewImageUrl: Value(previewImageUrl),
              faviconUrl: Value(faviconUrl),
              sourceDomain: Value(sourceDomain),
              assetType: Value(assetType),
              triageStatus: Value(triageStatus),
              isPinned: Value(isPinned),
              mediaPath: Value(mediaPath),
              mediaThumbnailPath: Value(mediaThumbnailPath),
              ocrText: Value(ocrText),
              reminderAt: Value(reminderAt),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      if (tags.isNotEmpty) {
        for (final tag in tags.toSet()) {
          final cleanTag = tag.trim().replaceAll('#', '');
          if (cleanTag.isNotEmpty) {
            await _db.into(_db.dropTags).insert(
                  DropTagsCompanion.insert(dropId: id, tag: cleanTag),
                  mode: InsertMode.insertOrIgnore,
                );
          }
        }
      }

      return id;
    });

    if (title == null &&
        previewImageUrl == null &&
        DropMetadataScraper.extractFirstUrl(content) != null) {
      enrichDrop(id).catchError((_) {});
    }

    return id;
  }

  Future<void> enrichDrop(int id) async {
    try {
      final current = await (_db.select(_db.drops)..where((d) => d.id.equals(id)))
          .getSingleOrNull();
      if (current == null) return;

      final meta = await _scraper.scrape(current.content);
      if (meta == null) return;

      await (_db.update(_db.drops)..where((d) => d.id.equals(id))).write(
        DropsCompanion(
          title: meta.title != null ? Value(meta.title) : const Value.absent(),
          description: meta.description != null
              ? Value(meta.description)
              : const Value.absent(),
          previewImageUrl: meta.previewImageUrl != null
              ? Value(meta.previewImageUrl)
              : const Value.absent(),
          faviconUrl:
              meta.faviconUrl != null ? Value(meta.faviconUrl) : const Value.absent(),
          sourceDomain: meta.sourceDomain != null
              ? Value(meta.sourceDomain)
              : const Value.absent(),
          assetType: Value(meta.assetType),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (_) {
      // Ignore errors when db is closed or scraping fails
    }
  }

  Future<void> updateDrop(
    int id, {
    String? content,
    String? title,
    String? description,
    String? previewImageUrl,
    String? faviconUrl,
    String? sourceDomain,
    String? assetType,
    String? triageStatus,
    bool? isPinned,
    String? mediaPath,
    String? mediaThumbnailPath,
    String? ocrText,
    DateTime? reminderAt,
    List<String>? tags,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.drops)..where((d) => d.id.equals(id))).write(
        DropsCompanion(
          content: content != null ? Value(content) : const Value.absent(),
          title: title != null ? Value(title) : const Value.absent(),
          description:
              description != null ? Value(description) : const Value.absent(),
          previewImageUrl: previewImageUrl != null
              ? Value(previewImageUrl)
              : const Value.absent(),
          faviconUrl:
              faviconUrl != null ? Value(faviconUrl) : const Value.absent(),
          sourceDomain:
              sourceDomain != null ? Value(sourceDomain) : const Value.absent(),
          assetType:
              assetType != null ? Value(assetType) : const Value.absent(),
          triageStatus:
              triageStatus != null ? Value(triageStatus) : const Value.absent(),
          isPinned: isPinned != null ? Value(isPinned) : const Value.absent(),
          mediaPath:
              mediaPath != null ? Value(mediaPath) : const Value.absent(),
          mediaThumbnailPath: mediaThumbnailPath != null
              ? Value(mediaThumbnailPath)
              : const Value.absent(),
          ocrText: ocrText != null ? Value(ocrText) : const Value.absent(),
          reminderAt:
              reminderAt != null ? Value(reminderAt) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (tags != null) {
        await (_db.delete(_db.dropTags)..where((t) => t.dropId.equals(id))).go();
        for (final tag in tags.toSet()) {
          final cleanTag = tag.trim().replaceAll('#', '');
          if (cleanTag.isNotEmpty) {
            await _db.into(_db.dropTags).insert(
                  DropTagsCompanion.insert(dropId: id, tag: cleanTag),
                  mode: InsertMode.insertOrIgnore,
                );
          }
        }
      }
    });
  }

  Future<void> setTriageStatus(int id, String status, {NotificationService? notifier}) async {
    await (_db.update(_db.drops)..where((d) => d.id.equals(id))).write(
      DropsCompanion(
        triageStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (status == 'archived') {
      await notifier?.cancelDropReminder(id);
    }
  }

  Future<void> togglePinned(int id) async {
    final current = await (_db.select(_db.drops)..where((d) => d.id.equals(id)))
        .getSingleOrNull();
    if (current != null) {
      await (_db.update(_db.drops)..where((d) => d.id.equals(id))).write(
        DropsCompanion(
          isPinned: Value(!current.isPinned),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<void> deleteDrop(int id, {NotificationService? notifier}) async {
    await notifier?.cancelDropReminder(id);
    await (_db.delete(_db.drops)..where((d) => d.id.equals(id))).go();
  }

  Future<void> deleteDrops(List<int> ids, {NotificationService? notifier}) async {
    if (ids.isEmpty) return;
    if (notifier != null) {
      for (final id in ids) {
        await notifier.cancelDropReminder(id);
      }
    }
    await (_db.delete(_db.drops)..where((d) => d.id.isIn(ids))).go();
  }

  Future<void> bulkSetTriageStatus(List<int> ids, String status, {NotificationService? notifier}) async {
    if (ids.isEmpty) return;
    if (status == 'archived' && notifier != null) {
      for (final id in ids) {
        await notifier.cancelDropReminder(id);
      }
    }
    await (_db.update(_db.drops)..where((d) => d.id.isIn(ids))).write(
      DropsCompanion(
        triageStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> bulkAddTag(List<int> ids, String tag) async {
    final cleanTag = tag.trim().replaceAll('#', '');
    if (cleanTag.isEmpty || ids.isEmpty) return;

    await _db.transaction(() async {
      for (final id in ids) {
        await _db.into(_db.dropTags).insert(
              DropTagsCompanion.insert(dropId: id, tag: cleanTag),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  }

  Future<void> setReminder(
    int id,
    DateTime? reminderAt, {
    NotificationService? notifier,
  }) async {
    await (_db.update(_db.drops)..where((d) => d.id.equals(id))).write(
      DropsCompanion(
        reminderAt: Value(reminderAt),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (notifier != null) {
      if (reminderAt != null && reminderAt.isAfter(DateTime.now())) {
        final drop = await (_db.select(_db.drops)..where((d) => d.id.equals(id)))
            .getSingleOrNull();
        if (drop != null) {
          final title = drop.title ??
              (drop.content.length > 50
                  ? '${drop.content.substring(0, 50)}...'
                  : drop.content);
          await notifier.scheduleDropReminder(
            id: id,
            title: title,
            when: reminderAt,
          );
        }
      } else {
        await notifier.cancelDropReminder(id);
      }
    }
  }

  Future<List<Drop>> dropsWithReminders() async {
    final now = DateTime.now();
    return (_db.select(_db.drops)
          ..where((d) =>
              d.reminderAt.isNotNull() &
              d.reminderAt.isBiggerThanValue(now) &
              d.triageStatus.equals('inbox')))
        .get();
  }

  Future<void> updateOcrText(int id, String ocrText) async {
    await (_db.update(_db.drops)..where((d) => d.id.equals(id))).write(
      DropsCompanion(
        ocrText: Value(ocrText),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<String>> watchAllTags() {
    return _db
        .customSelect(
          'SELECT DISTINCT tag FROM drop_tags ORDER BY tag COLLATE NOCASE ASC;',
          readsFrom: {_db.dropTags},
        )
        .watch()
        .map((rows) => rows.map((r) => r.read<String>('tag')).toList());
  }

  Future<List<String>> getAllTags() async {
    final rows = await _db.customSelect(
      'SELECT DISTINCT tag FROM drop_tags ORDER BY tag COLLATE NOCASE ASC;',
      readsFrom: {_db.dropTags},
    ).get();
    return rows.map((r) => r.read<String>('tag')).toList();
  }
}
