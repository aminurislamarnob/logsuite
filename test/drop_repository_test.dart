import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logsuite/core/database/app_database.dart';
import 'package:logsuite/presentation/drop/repository/drop_repository.dart';

void main() {
  late AppDatabase db;
  late DropRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DropRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates and retrieves a text drop with tags', () async {
    final id = await repo.createDrop(
      content: 'Remember to check the documentation #dev #flutter',
      assetType: 'clip',
      tags: ['dev', 'flutter'],
    );

    expect(id, greaterThan(0));

    final drops = await repo.getDrops();
    expect(drops.length, 1);
    expect(drops.first.content, contains('Remember to check'));
    expect(drops.first.assetType, 'clip');
    expect(drops.first.tags, containsAll(['dev', 'flutter']));
    expect(drops.first.isInbox, isTrue);
  });

  test('toggles pinned status and sorts pinned items to top', () async {
    final id1 = await repo.createDrop(content: 'First drop', isPinned: false);
    final id2 = await repo.createDrop(content: 'Second drop', isPinned: false);

    await repo.togglePinned(id1);

    final drops = await repo.getDrops();
    expect(drops.first.id, id1);
    expect(drops.first.isPinned, isTrue);
    expect(drops.last.id, id2);
    expect(drops.last.isPinned, isFalse);
  });

  test('manages triage lifecycle between inbox and archived', () async {
    final id = await repo.createDrop(
      content: 'https://example.com/article',
      assetType: 'article',
      triageStatus: 'inbox',
    );

    var inbox = await repo.getDrops(triageStatus: 'inbox');
    var archived = await repo.getDrops(triageStatus: 'archived');
    expect(inbox.length, 1);
    expect(archived.length, 0);

    // Archive it
    await repo.setTriageStatus(id, 'archived');

    inbox = await repo.getDrops(triageStatus: 'inbox');
    archived = await repo.getDrops(triageStatus: 'archived');
    expect(inbox.length, 0);
    expect(archived.length, 1);
    expect(archived.first.id, id);
    expect(archived.first.isArchived, isTrue);
  });

  test('filters drops by tag and asset type', () async {
    await repo.createDrop(
      content: 'Article 1',
      assetType: 'article',
      tags: ['tech'],
    );
    await repo.createDrop(
      content: 'Video 1',
      assetType: 'video',
      tags: ['tech'],
    );
    await repo.createDrop(
      content: 'Recipe 1',
      assetType: 'clip',
      tags: ['food'],
    );

    final techDrops = await repo.getDrops(tag: 'tech');
    expect(techDrops.length, 2);

    final techVideos = await repo.getDrops(tag: 'tech', assetType: 'video');
    expect(techVideos.length, 1);
    expect(techVideos.first.content, 'Video 1');

    final foodDrops = await repo.getDrops(tag: 'food');
    expect(foodDrops.length, 1);
    expect(foodDrops.first.content, 'Recipe 1');
  });

  test('searches drops by content query', () async {
    await repo.createDrop(content: 'Flutter state management with Riverpod');
    await repo.createDrop(content: 'Cooking pasta carbonara');

    final searchResults = await repo.getDrops(query: 'Riverpod');
    expect(searchResults.length, 1);
    expect(searchResults.first.content, contains('Riverpod'));
  });

  test('performs bulk operations: status change and deletion', () async {
    final id1 = await repo.createDrop(content: 'Item 1');
    final id2 = await repo.createDrop(content: 'Item 2');
    final id3 = await repo.createDrop(content: 'Item 3');

    await repo.bulkSetTriageStatus([id1, id2], 'archived');

    var archived = await repo.getDrops(triageStatus: 'archived');
    expect(archived.map((d) => d.id), containsAll([id1, id2]));

    await repo.deleteDrops([id1, id2, id3]);
    final allDrops = await repo.getDrops();
    expect(allDrops.isEmpty, isTrue);
  });
}
