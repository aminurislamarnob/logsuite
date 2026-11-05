import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_providers.dart';
import '../models/drop_with_tags.dart';
import '../repository/drop_repository.dart';

final dropSummarizerProvider = Provider<DropSummarizer>((ref) {
  return DropSummarizer(ref);
});

class DropSummarizer {
  final Ref _ref;

  DropSummarizer(this._ref);

  /// Summarizes a drop's text/article content.
  /// If [aiClientProvider] has an active AI key/client, uses it to generate 2-3 bullets.
  /// Otherwise, falls back to an offline extractive summary.
  Future<String> summarizeDrop(DropWithTags item) async {
    final client = await _ref.read(aiClientProvider.future);
    final textToSummarize = _buildContextText(item);

    if (textToSummarize.trim().isEmpty) {
      return 'No content available to summarize.';
    }

    if (client != null) {
      try {
        final schema = {
          'type': 'object',
          'properties': {
            'summary': {
              'type': 'string',
              'description':
                  'A concise 2-3 bullet point summary of the text or web article, formatted with bullet points (•).',
            },
          },
          'required': ['summary'],
        };

        final response = await client.complete(
          system:
              'You are an executive summary assistant. Read the provided text or link metadata and extract the core thesis in 2 to 3 concise bullet points. Each bullet must start with "• ". Do not add any introductory or concluding pleasantries.',
          user: textToSummarize,
          schema: schema,
        );

        final decoded = jsonDecode(response.text);
        if (decoded is Map && decoded['summary'] is String) {
          final summary = (decoded['summary'] as String).trim();
          if (summary.isNotEmpty) {
            await _ref.read(dropRepositoryProvider).updateDrop(
                  item.id,
                  description: summary,
                );
            return summary;
          }
        }
      } catch (e) {
        debugPrint('AI summarization failed, falling back to extractive: $e');
      }
    }

    // Offline extractive fallback
    final fallback = _extractiveSummary(textToSummarize);
    await _ref.read(dropRepositoryProvider).updateDrop(
          item.id,
          description: fallback,
        );
    return fallback;
  }

  String _buildContextText(DropWithTags item) {
    final parts = <String>[];
    if (item.title != null && item.title!.isNotEmpty) {
      parts.add('Title: ${item.title}');
    }
    if (item.drop.sourceDomain != null && item.drop.sourceDomain!.isNotEmpty) {
      parts.add('Source: ${item.drop.sourceDomain}');
    }
    if (item.drop.ocrText != null && item.drop.ocrText!.isNotEmpty) {
      parts.add('Extracted OCR Text:\n${item.drop.ocrText}');
    }
    if (item.content.isNotEmpty) {
      parts.add('Content:\n${item.content}');
    }
    return parts.join('\n\n');
  }

  String _extractiveSummary(String text) {
    // Splits into sentences, takes up to top 3 non-empty meaningful sentences
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sentences = clean
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().length > 15)
        .take(3)
        .toList();

    if (sentences.isEmpty) {
      return '• ${clean.length > 120 ? "${clean.substring(0, 117)}..." : clean}';
    }

    return sentences.map((s) => '• ${s.trim()}').join('\n');
  }
}
