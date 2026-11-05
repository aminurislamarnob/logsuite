import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class DropMetadata {
  final String? title;
  final String? description;
  final String? previewImageUrl;
  final String? faviconUrl;
  final String? sourceDomain;
  final String assetType;

  const DropMetadata({
    this.title,
    this.description,
    this.previewImageUrl,
    this.faviconUrl,
    this.sourceDomain,
    required this.assetType,
  });
}

class DropMetadataScraper {
  final http.Client _client;

  DropMetadataScraper({http.Client? client}) : _client = client ?? http.Client();

  static String? extractFirstUrl(String text) {
    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(text);
    return match?.group(0);
  }

  static String? extractYouTubeVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.host.contains('youtu.be')) {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty && segments.first.isNotEmpty) {
        return segments.first;
      }
    }

    if (uri.host.contains('youtube.com')) {
      if (uri.path.contains('/shorts/')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('shorts');
        if (idx != -1 && idx + 1 < segments.length) {
          return segments[idx + 1];
        }
      }
      return uri.queryParameters['v'];
    }

    return null;
  }

  Future<DropMetadata?> scrape(String text) async {
    final url = extractFirstUrl(text);
    if (url == null) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }

    final domain = uri.host.replaceFirst('www.', '');

    // Check if YouTube video
    final ytVideoId = extractYouTubeVideoId(url);
    if (ytVideoId != null) {
      final thumbnail = 'https://img.youtube.com/vi/$ytVideoId/hqdefault.jpg';
      String? title;
      String? author;

      try {
        final oembedUri = Uri.parse(
          'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
        );
        final res = await _client.get(oembedUri).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          title = data['title'] as String?;
          author = data['author_name'] as String?;
        }
      } catch (_) {
        // Fallback gracefully
      }

      return DropMetadata(
        title: title ?? 'YouTube Video',
        description: author != null ? 'Channel: $author' : 'Video',
        previewImageUrl: thumbnail,
        faviconUrl: 'https://www.youtube.com/s/desktop/favicon.ico',
        sourceDomain: 'youtube.com',
        assetType: 'video',
      );
    }

    // Check if Vimeo video
    if (domain.contains('vimeo.com')) {
      return DropMetadata(
        title: 'Vimeo Video',
        description: 'Watch video',
        sourceDomain: domain,
        assetType: 'video',
      );
    }

    // Standard Web Link / Article OpenGraph Scraping
    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return DropMetadata(
          sourceDomain: domain,
          assetType: 'article',
        );
      }

      final doc = html_parser.parse(response.body);

      // Extract Title: og:title -> twitter:title -> <title>
      var title = doc
          .querySelector('meta[property="og:title"]')
          ?.attributes['content']
          ?.trim();
      title ??= doc
          .querySelector('meta[name="twitter:title"]')
          ?.attributes['content']
          ?.trim();
      title ??= doc.querySelector('title')?.text.trim();

      // Extract Description: og:description -> twitter:description -> meta description
      var description = doc
          .querySelector('meta[property="og:description"]')
          ?.attributes['content']
          ?.trim();
      description ??= doc
          .querySelector('meta[name="twitter:description"]')
          ?.attributes['content']
          ?.trim();
      description ??= doc
          .querySelector('meta[name="description"]')
          ?.attributes['content']
          ?.trim();

      // Extract Image: og:image -> twitter:image
      var image = doc
          .querySelector('meta[property="og:image"]')
          ?.attributes['content']
          ?.trim();
      image ??= doc
          .querySelector('meta[name="twitter:image"]')
          ?.attributes['content']
          ?.trim();
      if (image != null && !image.startsWith('http')) {
        image = uri.resolve(image).toString();
      }

      // Favicon
      var favicon = doc
          .querySelector('link[rel="icon"]')
          ?.attributes['href']
          ?.trim();
      favicon ??= doc
          .querySelector('link[rel="shortcut icon"]')
          ?.attributes['href']
          ?.trim();
      if (favicon != null && !favicon.startsWith('http')) {
        favicon = uri.resolve(favicon).toString();
      }
      favicon ??= 'https://$domain/favicon.ico';

      return DropMetadata(
        title: title,
        description: description,
        previewImageUrl: image,
        faviconUrl: favicon,
        sourceDomain: domain,
        assetType: 'article',
      );
    } catch (_) {
      return DropMetadata(
        sourceDomain: domain,
        assetType: 'article',
      );
    }
  }
}
