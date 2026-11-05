import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../repository/drop_repository.dart';

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
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
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

      _controller.clear();
      _focusNode.unfocus();
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: bottomInset > 0 ? bottomInset + 8 : 12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: brand.hairline, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossEventAlign.center,
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Drop a link, note or #tag...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                    : const AppIcon(AppIcons.arrowUp, color: Colors.white, size: 20),
                tooltip: 'Drop',
                onPressed: _isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CrossEventAlign {
  static const CrossAxisAlignment center = CrossAxisAlignment.center;
}
