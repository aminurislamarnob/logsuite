import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logsuite/presentation/drop/services/drop_metadata_scraper.dart';

void main() {
  test('extracts YouTube video IDs from various URL formats', () {
    expect(
      DropMetadataScraper.extractYouTubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(
      DropMetadataScraper.extractYouTubeVideoId('https://youtu.be/dQw4w9WgXcQ?si=123'),
      'dQw4w9WgXcQ',
    );
    expect(
      DropMetadataScraper.extractYouTubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
  });

  test('scrapes YouTube video with oembed response', () async {
    final mockClient = MockClient((request) async {
      if (request.url.host == 'www.youtube.com' && request.url.path == '/oembed') {
        return http.Response(
          jsonEncode({
            'title': 'Never Gonna Give You Up',
            'author_name': 'Rick Astley',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not found', 404);
    });

    final scraper = DropMetadataScraper(client: mockClient);
    final meta = await scraper.scrape('Check this video: https://youtu.be/dQw4w9WgXcQ');

    expect(meta, isNotNull);
    expect(meta!.assetType, 'video');
    expect(meta.title, 'Never Gonna Give You Up');
    expect(meta.description, 'Channel: Rick Astley');
    expect(meta.previewImageUrl, contains('dQw4w9WgXcQ'));
    expect(meta.sourceDomain, 'youtube.com');
  });

  test('scrapes OpenGraph tags from web article', () async {
    const html = '''
      <!DOCTYPE html>
      <html>
        <head>
          <title>Fallback Title</title>
          <meta property="og:title" content="Building Beautiful Flutter Apps" />
          <meta property="og:description" content="A comprehensive guide to Flutter animations and performance." />
          <meta property="og:image" content="https://example.com/cover.png" />
          <link rel="icon" href="/favicon.png" />
        </head>
        <body>
          <h1>Content</h1>
        </body>
      </html>
    ''';

    final mockClient = MockClient((request) async {
      return http.Response(html, 200, headers: {'content-type': 'text/html'});
    });

    final scraper = DropMetadataScraper(client: mockClient);
    final meta = await scraper.scrape('https://example.com/flutter-guide');

    expect(meta, isNotNull);
    expect(meta!.assetType, 'article');
    expect(meta.title, 'Building Beautiful Flutter Apps');
    expect(meta.description, contains('A comprehensive guide'));
    expect(meta.previewImageUrl, 'https://example.com/cover.png');
    expect(meta.faviconUrl, 'https://example.com/favicon.png');
    expect(meta.sourceDomain, 'example.com');
  });

  test('falls back to HTML title and handles network failures gracefully', () async {
    final mockClient = MockClient((request) async {
      throw http.ClientException('Offline');
    });

    final scraper = DropMetadataScraper(client: mockClient);
    final meta = await scraper.scrape('https://offline-example.org/news');

    expect(meta, isNotNull);
    expect(meta!.assetType, 'article');
    expect(meta.sourceDomain, 'offline-example.org');
  });
}
