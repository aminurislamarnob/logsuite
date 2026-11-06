import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'common.dart';

/// Facebook / LinkedIn style in-app browser screen.
///
/// Opens web links inside the application with a compact top header displaying
/// the page title and verified domain (`🔒 domain.com`), a thin loading progress
/// bar, back/forward history controls, and one-tap **Open in external browser**
/// actions in both the header/toolbar and the overflow menu.
class InAppBrowserScreen extends StatefulWidget {
  const InAppBrowserScreen({
    super.key,
    required this.initialUrl,
    this.initialTitle,
  });

  final String initialUrl;
  final String? initialTitle;

  /// Normalizes [rawUrl] and opens it inside [InAppBrowserScreen], or falls back
  /// to the system handler for non-web schemes (`mailto:`, `tel:`, etc.).
  static Future<void> open(
    BuildContext context,
    String rawUrl, {
    String? initialTitle,
  }) async {
    final normalized = normalizeUrl(rawUrl);
    if (normalized == null) {
      if (context.mounted) {
        brandToast(context, 'Invalid link');
      }
      return;
    }

    final uri = Uri.parse(normalized);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      await openInExternalBrowser(context, normalized);
      return;
    }

    if (!context.mounted) return;
    AppHaptics.tap();
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => InAppBrowserScreen(
          initialUrl: normalized,
          initialTitle: initialTitle,
        ),
      ),
    );
  }

  /// Launches [rawUrl] directly in the device's default external browser.
  static Future<bool> openInExternalBrowser(
    BuildContext context,
    String rawUrl,
  ) async {
    final normalized = normalizeUrl(rawUrl);
    if (normalized == null) {
      if (context.mounted) {
        brandToast(context, 'Could not open link');
      }
      return false;
    }

    final uri = Uri.parse(normalized);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        brandToast(context, 'Could not open external browser');
      }
      return launched;
    } catch (_) {
      if (context.mounted) {
        brandToast(context, 'Could not open external browser');
      }
      return false;
    }
  }

  /// Extracts or normalizes a URL string into a valid URI string.
  static String? normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(trimmed);
    final candidate = match != null ? match.group(0)! : trimmed;

    var uri = Uri.tryParse(candidate);
    if (uri == null) return null;

    if (!uri.hasScheme) {
      uri = Uri.tryParse('https://$candidate');
    }
    if (uri == null || (!uri.hasScheme)) return null;
    return uri.toString();
  }

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  WebViewController? _controller;
  late String _currentUrl;
  String? _pageTitle;
  int _progress = 0;
  bool _isLoading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _errorDescription;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _pageTitle = widget.initialTitle;
    _initWebView();
  }

  void _initWebView() {
    // Guard against unit/widget test environments where no native
    // WebViewPlatform implementation is registered.
    if (WebViewPlatform.instance == null) {
      _isLoading = false;
      return;
    }

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _progress = progress;
                _isLoading = progress < 100;
              });
            },
            onPageStarted: (url) {
              if (!mounted) return;
              setState(() {
                _currentUrl = url;
                _isLoading = true;
                _errorDescription = null;
              });
              _syncNavigationState();
            },
            onPageFinished: (url) async {
              if (!mounted) return;
              setState(() {
                _currentUrl = url;
                _isLoading = false;
                _progress = 100;
              });
              await _syncNavigationState();
              await _syncTitle();
            },
            onWebResourceError: (error) {
              // Ignore subresource/iframe errors so ad/tracker failures don't
              // mask a successfully loaded main page.
              if (error.isForMainFrame == false) return;
              if (!mounted) return;
              setState(() {
                _isLoading = false;
                _errorDescription = error.description;
              });
            },
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (uri != null &&
                  uri.scheme != 'http' &&
                  uri.scheme != 'https' &&
                  uri.scheme != 'about' &&
                  uri.scheme != 'data' &&
                  uri.scheme != 'javascript') {
                InAppBrowserScreen.openInExternalBrowser(context, request.url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        );

      _controller = controller;
      controller.loadRequest(Uri.parse(_currentUrl));
    } catch (_) {
      _isLoading = false;
    }
  }

  Future<void> _syncNavigationState() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    } catch (_) {}
  }

  Future<void> _syncTitle() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final title = await controller.getTitle();
      if (!mounted) return;
      if (title != null && title.trim().isNotEmpty) {
        setState(() => _pageTitle = title.trim());
      }
    } catch (_) {}
  }

  Uri? get _currentUri => Uri.tryParse(_currentUrl);

  String get _displayHost {
    final host = _currentUri?.host ?? '';
    if (host.startsWith('www.')) {
      return host.substring(4);
    }
    return host.isNotEmpty ? host : _currentUrl;
  }

  bool get _isSecure => _currentUri?.scheme == 'https';

  String get _displayTitle {
    final title = _pageTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    return _displayHost;
  }

  Future<void> _handleBackNavigation() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      AppHaptics.selection();
      await controller.goBack();
      await _syncNavigationState();
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _reload() async {
    AppHaptics.tap();
    setState(() {
      _errorDescription = null;
      _isLoading = true;
    });
    await _controller?.reload();
  }

  Future<void> _copyLink() async {
    AppHaptics.tap();
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    if (mounted) {
      brandToast(context, 'Link copied to clipboard');
    }
  }

  Future<void> _shareLink() async {
    AppHaptics.tap();
    await SharePlus.instance.share(ShareParams(text: _currentUrl));
  }

  Future<void> _openExternally() async {
    AppHaptics.medium();
    await InAppBrowserScreen.openInExternalBrowser(context, _currentUrl);
  }

  void _showMoreMenu() {
    AppHaptics.tap();
    brandSheet(
      context: context,
      builder: (sheetContext) => SheetScaffold(
        title: _displayHost,
        child: TileColumn(
          children: [
            BrandTile(
              leading: const AppIcon(AppIcons.externalLink),
              title: const Text('Open in external browser'),
              subtitle: Text(
                _currentUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _openExternally();
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.replay),
              title: const Text('Reload page'),
              onTap: () {
                Navigator.pop(sheetContext);
                _reload();
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.copy),
              title: const Text('Copy link'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyLink();
              },
            ),
            BrandTile(
              leading: const AppIcon(AppIcons.share),
              title: const Text('Share link'),
              onTap: () {
                Navigator.pop(sheetContext);
                _shareLink();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final cs = theme.colorScheme;

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              // Facebook / LinkedIn style compact top bar
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    bottom: BorderSide(color: brand.hairline, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('in_app_browser_close'),
                      tooltip: 'Close browser',
                      icon: const AppIcon(AppIcons.close, size: 20),
                      onPressed: () {
                        AppHaptics.tap();
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _copyLink,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon(
                                    _isSecure ? AppIcons.lock : AppIcons.globe,
                                    size: 11,
                                    color: _isSecure
                                        ? brand.success
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      _displayHost,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontSize: 11.5,
                                            color: cs.onSurfaceVariant,
                                            height: 1.1,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('in_app_browser_open_external_top'),
                      tooltip: 'Open in external browser',
                      icon: const AppIcon(AppIcons.externalLink, size: 19),
                      onPressed: _openExternally,
                    ),
                    IconButton(
                      key: const Key('in_app_browser_more'),
                      tooltip: 'More options',
                      icon: const AppIcon(AppIcons.moreVertical, size: 19),
                      onPressed: _showMoreMenu,
                    ),
                  ],
                ),
              ),

              // Thin loading progress bar
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress > 0 && _progress < 100
                      ? _progress / 100.0
                      : null,
                  minHeight: 2.5,
                  backgroundColor: brand.hairline.withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                )
              else
                const SizedBox(height: 2.5),

              // Main WebView or Error/Fallback View
              Expanded(
                child: _buildBody(context, brand),
              ),

              // Bottom navigation & action bar (like Facebook / LinkedIn in-app browser)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    top: BorderSide(color: brand.hairline, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      key: const Key('in_app_browser_back'),
                      tooltip: 'Back',
                      icon: AppIcon(
                        AppIcons.chevronLeft,
                        size: 20,
                        color: _canGoBack
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                      onPressed: _canGoBack
                          ? () async {
                              AppHaptics.selection();
                              await _controller?.goBack();
                              await _syncNavigationState();
                            }
                          : null,
                    ),
                    IconButton(
                      key: const Key('in_app_browser_forward'),
                      tooltip: 'Forward',
                      icon: AppIcon(
                        AppIcons.chevronRight,
                        size: 20,
                        color: _canGoForward
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                      onPressed: _canGoForward
                          ? () async {
                              AppHaptics.selection();
                              await _controller?.goForward();
                              await _syncNavigationState();
                            }
                          : null,
                    ),
                    IconButton(
                      key: const Key('in_app_browser_reload'),
                      tooltip: 'Reload',
                      icon: const AppIcon(AppIcons.replay, size: 18),
                      onPressed: _reload,
                    ),
                    IconButton(
                      key: const Key('in_app_browser_share'),
                      tooltip: 'Share link',
                      icon: const AppIcon(AppIcons.share, size: 18),
                      onPressed: _shareLink,
                    ),
                    IconButton(
                      key: const Key('in_app_browser_open_external_bottom'),
                      tooltip: 'Open in external browser',
                      icon: const AppIcon(AppIcons.externalLink, size: 18),
                      onPressed: _openExternally,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BrandColors brand) {
    final cs = Theme.of(context).colorScheme;
    if (_errorDescription != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: brand.canvas,
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  AppIcons.globe,
                  size: 32,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to load page',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorDescription!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandButton(
                    label: 'Retry',
                    icon: AppIcons.replay,
                    kind: BrandButtonKind.outline,
                    expand: false,
                    onPressed: _reload,
                  ),
                  const SizedBox(width: 10),
                  BrandButton(
                    label: 'Open in Browser',
                    icon: AppIcons.externalLink,
                    expand: false,
                    onPressed: _openExternally,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.globe, size: 36, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                _displayTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _currentUrl,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              BrandButton(
                label: 'Open in External Browser',
                icon: AppIcons.externalLink,
                expand: false,
                onPressed: _openExternally,
              ),
            ],
          ),
        ),
      );
    }

    return WebViewWidget(controller: controller);
  }
}
