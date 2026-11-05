import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/ocr_service.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/formatters.dart';
import '../models/drop_with_tags.dart';
import '../repository/drop_repository.dart';

class DropLightboxViewer extends ConsumerStatefulWidget {
  final DropWithTags item;

  const DropLightboxViewer({super.key, required this.item});

  static Future<void> show(BuildContext context, DropWithTags item) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) => DropLightboxViewer(item: item),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  ConsumerState<DropLightboxViewer> createState() => _DropLightboxViewerState();
}

class _DropLightboxViewerState extends ConsumerState<DropLightboxViewer> {
  bool _isExtractingOcr = false;
  String? _ocrText;

  @override
  void initState() {
    super.initState();
    _ocrText = widget.item.ocrText;
  }

  Future<void> _handleOcrText() async {
    final imagePath = widget.item.mediaPath;
    if (imagePath == null) return;

    if (_ocrText != null && _ocrText!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _ocrText!));
      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extracted text copied to clipboard!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isExtractingOcr = true);
    try {
      final ocrService = ref.read(ocrServiceProvider);
      final text = await ocrService.extractText(File(imagePath));
      if (text != null && text.isNotEmpty) {
        setState(() => _ocrText = text);
        await ref.read(dropRepositoryProvider).updateOcrText(widget.item.id, text);
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Text extracted & copied to clipboard!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No readable text detected in this image.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isExtractingOcr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.item.mediaPath;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      body: SafeArea(
        child: Stack(
          children: [
            // Pinch-to-zoom interactive image viewer
            Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: imagePath != null
                    ? Image.file(
                        File(imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    : (widget.item.previewImageUrl != null
                        ? Image.network(
                            widget.item.previewImageUrl!,
                            fit: BoxFit.contain,
                          )
                        : const SizedBox.shrink()),
              ),
            ),

            // Top Control Bar
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Container(
                    decoration: const ShapeDecoration(
                      color: Colors.black45,
                      shape: CircleBorder(),
                    ),
                    child: IconButton(
                      icon: const AppIcon(AppIcons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Spacer(),
                  // OCR Action Button
                  Container(
                    decoration: const ShapeDecoration(
                      color: Colors.black45,
                      shape: StadiumBorder(),
                    ),
                    child: TextButton.icon(
                      icon: _isExtractingOcr
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const AppIcon(
                              AppIcons.document,
                              color: Colors.white,
                              size: 16,
                            ),
                      label: Text(
                        _ocrText != null ? 'Copy Text' : 'Extract Text',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      onPressed: _isExtractingOcr ? null : _handleOcrText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (imagePath != null)
                    Container(
                      decoration: const ShapeDecoration(
                        color: Colors.black45,
                        shape: CircleBorder(),
                      ),
                      child: IconButton(
                        icon: const AppIcon(AppIcons.share, color: Colors.white),
                        onPressed: () {
                          SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(imagePath)],
                              text: widget.item.content,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Bottom Info Bar
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.item.content.isNotEmpty &&
                              widget.item.content != 'image')
                            Text(
                              widget.item.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          Text(
                            Fmt.fullDate(widget.item.createdAt),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_ocrText != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'OCR Ready',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
