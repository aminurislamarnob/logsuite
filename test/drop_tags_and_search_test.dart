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

  test('searches across OCR extracted text from screenshots', () async {
    await repo.createDrop(
      content: 'Invoice screenshot',
      assetType: 'image',
      ocrText: 'Invoice #9482 Total: \$450.00 Acme Corp',
    );
    await repo.createDrop(
      content: 'Random coffee cup photo',
      assetType: 'image',
      ocrText: 'Cappuccino Starbucks',
    );

    final results = await repo.getDrops(query: 'Acme Corp');
    expect(results.length, 1);
    expect(results.first.content, 'Invoice screenshot');
    expect(results.first.ocrText, contains('\$450.00'));
  });

  test('combines asset type filter and tag filter with search query', () async {
    await repo.createDrop(
      content: 'https://youtube.com/watch?v=123',
      title: 'Advanced Flutter Riverpod Tutorial',
      assetType: 'video',
      tags: ['flutter', 'code'],
    );
    await repo.createDrop(
      content: 'https://youtube.com/watch?v=456',
      title: 'Beginner Python Tutorial',
      assetType: 'video',
      tags: ['python', 'code'],
    );
    await repo.createDrop(
      content: 'https://medium.com/flutter-article',
      title: 'Flutter Architecture Patterns',
      assetType: 'article',
      tags: ['flutter', 'architecture'],
    );

    // Filter only videos with tag 'flutter'
    final flutterVideos = await repo.getDrops(assetType: 'video', tag: 'flutter');
    expect(flutterVideos.length, 1);
    expect(flutterVideos.first.title, contains('Advanced Flutter'));

    // Filter only videos with tag 'code' and query 'Riverpod'
    final queried = await repo.getDrops(assetType: 'video', tag: 'code', query: 'Riverpod');
    expect(queried.length, 1);
    expect(queried.first.title, contains('Advanced Flutter'));

    // Filter videos with tag 'code' and query 'Beginner'
    final beginnerVideos = await repo.getDrops(assetType: 'video', tag: 'code', query: 'Beginner');
    expect(beginnerVideos.length, 1);
    expect(beginnerVideos.first.title, contains('Beginner Python'));
  });
}
