import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:logsuite/presentation/drop/services/drop_media_storage.dart';

void main() {
  late Directory tempDir;
  late DropMediaStorage storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('logsuite-drop-media-test');
    storage = DropMediaStorage(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('saves image and generates thumbnail in sandboxed directory', () async {
    // Create dummy image file
    final sampleImg = img.Image(width: 800, height: 600);
    img.fill(sampleImg, color: img.ColorRgb8(255, 0, 0));
    final sampleFile = File('${tempDir.path}/test_source.jpg');
    await sampleFile.writeAsBytes(img.encodeJpg(sampleImg));

    final saved = await storage.save(sampleFile);

    expect(File(saved.originalPath).existsSync(), isTrue);
    expect(File(saved.thumbnailPath).existsSync(), isTrue);
    expect(saved.originalPath, contains('drop_media'));
    expect(saved.thumbnailPath, contains('thumbs'));

    // Check thumbnail dimensions
    final thumbBytes = await File(saved.thumbnailPath).readAsBytes();
    final thumbImg = img.decodeImage(thumbBytes);
    expect(thumbImg, isNotNull);
    expect(thumbImg!.width, lessThanOrEqualTo(480));
  });

  test('deletes media file', () async {
    final sampleFile = File('${tempDir.path}/to_delete.jpg');
    await sampleFile.writeAsString('dummy');
    expect(sampleFile.existsSync(), isTrue);

    await storage.delete(sampleFile.path);
    expect(sampleFile.existsSync(), isFalse);
  });
}
