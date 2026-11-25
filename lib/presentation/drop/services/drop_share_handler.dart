import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/ocr_service.dart';
import '../repository/drop_repository.dart';
import 'drop_media_storage.dart';

final dropShareHandlerProvider = Provider<DropShareHandler>((ref) {
  return DropShareHandler(ref);
});

class DropShareHandler {
  final Ref _ref;
  StreamSubscription? _intentSub;
  bool _initialized = false;

  DropShareHandler(this._ref);

  void initialize() {
    if (_initialized || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    _initialized = true;

    // Listen to media sharing when app is running in background/foreground
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _handleSharedMedia(files),
      onError: (err) {
        debugPrint('Error receiving share stream: $err');
      },
    );

    // Get initial media when app opened from cold start via share
    ReceiveSharingIntent.instance.getInitialMedia().then((media) {
      if (media.isNotEmpty) {
        _handleSharedMedia(media);
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final repo = _ref.read(dropRepositoryProvider);
    var createdAny = false;

    for (final file in files) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        final text = file.path.trim();
        if (text.isNotEmpty) {
          await repo.createDrop(
            content: text,
            assetType: (text.startsWith('http://') || text.startsWith('https://'))
                ? 'article'
                : 'clip',
          );
          createdAny = true;
        }
      } else if (file.type == SharedMediaType.image) {
        try {
          final storage = await DropMediaStorage.create();
          final saved = await storage.save(File(file.path));

          String? ocrText;
          try {
            final ocr = _ref.read(ocrServiceProvider);
            ocrText = await ocr.extractText(File(saved.originalPath));
          } catch (_) {}

          final caption = (ocrText != null && ocrText.isNotEmpty)
              ? ocrText.split('\n').first.trim()
              : 'Shared Image';

          await repo.createDrop(
            content: caption,
            assetType: 'image',
            mediaPath: saved.originalPath,
            mediaThumbnailPath: saved.thumbnailPath,
            ocrText: ocrText,
          );
          createdAny = true;
        } catch (e) {
          debugPrint('Failed to save shared image: $e');
        }
      }
    }

    if (createdAny) {
      final router = _ref.read(appRouterProvider);
      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      if (currentPath != '/drop') {
        router.push('/drop');
      }
    }
  }

  void dispose() {
    _intentSub?.cancel();
  }
}
