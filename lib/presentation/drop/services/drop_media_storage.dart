import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final dropMediaStorageProvider = Provider<DropMediaStorage>((ref) {
  throw UnimplementedError('Initialize with directory');
});

class DropSavedMedia {
  final String originalPath;
  final String thumbnailPath;

  const DropSavedMedia({
    required this.originalPath,
    required this.thumbnailPath,
  });
}

class DropMediaStorage {
  final Directory root;

  DropMediaStorage(this.root);

  static Future<DropMediaStorage> create() async {
    final docs = await getApplicationDocumentsDirectory();
    return DropMediaStorage(docs);
  }

  Directory get dir => Directory(p.join(root.path, 'drop_media'));
  Directory get thumbsDir => Directory(p.join(root.path, 'drop_media', 'thumbs'));

  static String _token() {
    final rand = Random();
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '${now}_$r';
  }

  Future<DropSavedMedia> save(File source) async {
    await dir.create(recursive: true);
    await thumbsDir.create(recursive: true);

    final ext = p.extension(source.path).toLowerCase();
    final safeExt = (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp')
        ? ext
        : '.jpg';

    final baseName = _token();
    final destFile = await source.copy(p.join(dir.path, '$baseName$safeExt'));

    // Generate downscaled thumbnail for 60fps scrolling
    final thumbFile = File(p.join(thumbsDir.path, '${baseName}_thumb.jpg'));
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final resized = img.copyResize(
          decoded,
          width: decoded.width > 480 ? 480 : decoded.width,
        );
        await thumbFile.writeAsBytes(img.encodeJpg(resized, quality: 80), flush: true);
      } else {
        await source.copy(thumbFile.path);
      }
    } catch (_) {
      // Fallback: use copied file as thumbnail
      await source.copy(thumbFile.path);
    }

    return DropSavedMedia(
      originalPath: destFile.path,
      thumbnailPath: thumbFile.path,
    );
  }

  Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
